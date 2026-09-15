import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
import NarrationCore
import ProjectCore
@testable import TakeletApp

private enum MockNarrationFailure: Error, Sendable {
    case failed
}

private actor MockNarrationService: NarrationService {
    enum Behavior: Sendable {
        case success(SynthesizedAudio)
        case failure
        case waitForCancellation
    }

    private let behavior: Behavior
    private var requests: [SpeechRequest] = []

    init(_ behavior: Behavior) {
        self.behavior = behavior
    }

    func listVoices(pageSize: Int, nextPageToken: String?) async throws -> VoicePage {
        VoicePage(voices: [], hasMore: false)
    }

    func synthesize(_ request: SpeechRequest) async throws -> SynthesizedAudio {
        requests.append(request)
        switch behavior {
        case let .success(audio):
            return audio
        case .failure:
            throw MockNarrationFailure.failed
        case .waitForCancellation:
            try await Task.sleep(for: .seconds(60))
            throw MockNarrationFailure.failed
        }
    }

    func requestCount() -> Int { requests.count }
    func lastRequest() -> SpeechRequest? { requests.last }

    func waitUntilCalled() async {
        while requests.isEmpty { await Task.yield() }
    }
}

final class NarrationWorkspaceTests: XCTestCase {
    private func narration(
        start: Double = 1,
        end: Double = 3,
        audioPath: String? = nil,
        audioDuration: Double? = nil
    ) -> NarrationSegment {
        NarrationSegment(
            start: start,
            end: end,
            script: "Explain this part.",
            voiceID: "voice-1",
            voiceName: "Narrator",
            audioFile: audioPath,
            audioDuration: audioDuration
        )
    }

    private func project(with narrations: [NarrationSegment], cuts: [TimeRange] = []) -> Project {
        var project = Project(title: "Narration", duration: 10, width: 1920, height: 1080)
        project.cuts = cuts
        project.narrations = narrations
        return project
    }

    private func playableAudioData() throws -> Data {
        // 50 ms mono MP3 generated as test data with ffmpeg's `anullsrc` filter.
        let base64 = """
        SUQzBAAAAAAAIlRTU0UAAAAOAAADTGF2ZjYyLjMuMTAwAAAAAAAAAAAAAAD/80DEAAAAA0gAAAAATEFN
        RTMuMTAwVVVVVVVVVVVVVUxBTUUzLjEwMFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV
        VVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVf/zQsRbAAADSAAAAABVVVVVVVVVVVVVVVVVVVVVVVVV
        VUxBTUUzLjEwMFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV
        VVVVVVVVVVVVVVVVf/zQMSkAAADSAAAAABVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV
        VVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV//NC
        xKMAAANIAAAAAFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV
        VVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV
        """
        return try XCTUnwrap(Data(base64Encoded: base64, options: .ignoreUnknownCharacters))
    }

    private func temporaryPNG() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("takelet-cursor-\(UUID().uuidString).png")
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 2,
            height: 2,
            bitsPerComponent: 8,
            bytesPerRow: 8,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 0.5))
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    @MainActor func testDraftsMarkDirtyAndNarrationDraftSurvivesSelectionChanges() {
        let workspace = Workspace()
        defer { workspace.close() }
        let first = narration(start: 1, end: 3)
        let second = narration(start: 4, end: 6)
        workspace.project = project(with: [first, second])
        workspace.dirty = false
        workspace.selectedNarrationID = first.id

        var draft = first
        draft.script = "Visible but not applied yet"
        workspace.narrationDrafts[first.id] = draft

        XCTAssertTrue(workspace.dirty)
        workspace.selectNarration(second.id)
        XCTAssertEqual(workspace.narrationDrafts[first.id], draft)
        workspace.selectNarration(first.id)
        XCTAssertEqual(workspace.narrationDrafts[first.id]?.script, "Visible but not applied yet")
        XCTAssertEqual(workspace.project?.narrations.first { $0.id == first.id }?.script, first.script)
    }

    @MainActor func testSaveProjectAppliesCursorAndNarrationDraftsAsOneUndoableEdit() throws {
        let workspace = Workspace()
        defer { workspace.close() }
        let undo = UndoManager()
        undo.groupsByEvent = false
        workspace.undoManager = undo
        let segment = narration()
        var initial = project(with: [segment])
        initial.cursorMode = .separate
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("takelet-draft-source-\(UUID().uuidString).mov")
        let package = FileManager.default.temporaryDirectory
            .appendingPathComponent("takelet-draft-save-\(UUID().uuidString).takelet")
        try Data("source".utf8).write(to: source)
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: package)
        }
        try ProjectStore.create(initial, source: source, at: package)
        workspace.project = initial
        workspace.projectURL = package
        workspace.sourceURL = try ProjectStore.sourceURL(in: package)

        var cursor = initial.cursorStyle
        cursor.size = 88
        cursor.smoothing = 0.82
        workspace.cursorDraft = cursor
        var narrationDraft = segment
        narrationDraft.script = "The visible revised script"
        workspace.narrationDrafts[segment.id] = narrationDraft

        undo.beginUndoGrouping()
        workspace.saveProject()
        undo.endUndoGrouping()

        XCTAssertEqual(workspace.project?.cursorStyle, cursor)
        XCTAssertEqual(workspace.project?.narrations[0].script, narrationDraft.script)
        let persisted = try ProjectStore.load(from: package)
        XCTAssertEqual(persisted.cursorStyle, cursor)
        XCTAssertEqual(persisted.narrations[0].script, narrationDraft.script)
        XCTAssertNil(workspace.cursorDraft)
        XCTAssertTrue(workspace.narrationDrafts.isEmpty)
        XCTAssertEqual(undo.undoActionName, "Apply Inspector Changes")
        XCTAssertFalse(workspace.dirty)

        undo.undo()
        XCTAssertEqual(workspace.project, initial)
        XCTAssertTrue(workspace.dirty)
        undo.redo()
        XCTAssertEqual(workspace.project?.cursorStyle, cursor)
        XCTAssertEqual(workspace.project?.narrations[0].script, narrationDraft.script)
        XCTAssertFalse(workspace.dirty)
    }

    @MainActor func testInvalidNarrationDraftPreventsAtomicCommitAndServiceCall() async {
        let service = MockNarrationService(.failure)
        let workspace = Workspace()
        defer { workspace.close() }
        let first = narration(start: 1, end: 3)
        let second = narration(start: 4, end: 6)
        var initial = project(with: [first, second])
        initial.cursorMode = .separate
        workspace.project = initial

        var cursor = initial.cursorStyle
        cursor.size = 72
        workspace.cursorDraft = cursor
        var overlapping = first
        overlapping.end = 5
        workspace.narrationDrafts[first.id] = overlapping

        workspace.generateNarration(first.id, service: service)

        XCTAssertEqual(workspace.project, initial)
        XCTAssertEqual(workspace.cursorDraft, cursor)
        XCTAssertEqual(workspace.narrationDrafts[first.id], overlapping)
        XCTAssertNil(workspace.narrationTask)
        XCTAssertNil(workspace.generatingNarrationID)
        XCTAssertNotNil(workspace.error)
        let requestCount = await service.requestCount()
        XCTAssertEqual(requestCount, 0)
    }

    @MainActor func testDirectGenerateUsesVisibleNarrationDraftInputs() async {
        let service = MockNarrationService(.failure)
        let workspace = Workspace()
        defer { workspace.close() }
        let segment = narration()
        workspace.project = project(with: [segment])
        workspace.selectedNarrationID = segment.id

        var draft = segment
        draft.script = "Generate the text currently visible in the inspector."
        draft.voiceID = "voice-visible"
        draft.voiceName = "Visible Voice"
        draft.modelID = "eleven_flash_v2_5"
        draft.languageCode = "en"
        workspace.narrationDrafts[segment.id] = draft

        workspace.generateNarration(segment.id, service: service)
        let task = workspace.narrationTask
        await task?.value

        let request = await service.lastRequest()
        XCTAssertEqual(request?.text, draft.script)
        XCTAssertEqual(request?.voiceID, draft.voiceID)
        XCTAssertEqual(request?.modelID, draft.modelID)
        XCTAssertEqual(request?.languageCode, draft.languageCode)
        XCTAssertEqual(workspace.project?.narrations[0].script, draft.script)
        XCTAssertEqual(workspace.project?.narrations[0].voiceID, draft.voiceID)
        XCTAssertTrue(workspace.narrationDrafts.isEmpty)
    }

    @MainActor func testCursorPNGImportPreservesPendingSizeAndSmoothing() throws {
        let png = try temporaryPNG()
        defer { try? FileManager.default.removeItem(at: png) }
        let workspace = Workspace()
        defer { workspace.close() }
        var initial = project(with: [])
        initial.cursorMode = .separate
        workspace.project = initial

        var pending = initial.cursorStyle
        pending.size = 104
        pending.smoothing = 0.91
        pending.clickHalo = false
        workspace.cursorDraft = pending

        try workspace.installCursorImage(from: png)

        let installed = try XCTUnwrap(workspace.project?.cursorStyle)
        XCTAssertEqual(installed.shape, .customImage)
        XCTAssertEqual(installed.size, pending.size)
        XCTAssertEqual(installed.smoothing, pending.smoothing)
        XCTAssertEqual(installed.clickHalo, pending.clickHalo)
        XCTAssertEqual(installed.hotspotX, 0.5)
        XCTAssertEqual(installed.hotspotY, 0.5)
        XCTAssertNotNil(installed.imageFile)
        XCTAssertNotNil(workspace.assetURLs[try XCTUnwrap(installed.imageFile)])
        XCTAssertNil(workspace.cursorDraft)
    }

    @MainActor func testSourceAndOutputPositioningIncludesCutsAndUpstreamHold() throws {
        let workspace = Workspace()
        defer { workspace.close() }
        let held = narration(
            start: 0,
            end: 1,
            audioPath: "media/narration/\(UUID().uuidString).mp3",
            audioDuration: 4
        )
        let following = NarrationSegment(start: 4, end: 5, script: "Next")
        workspace.project = project(
            with: [held, following],
            cuts: [TimeRange(start: 2, end: 4)]
        )

        workspace.playhead = 2
        XCTAssertEqual(workspace.sourcePosition, 29.0 / 30, accuracy: 1e-9)
        workspace.addNarration()
        XCTAssertEqual(workspace.project?.narrations.count, 2)
        XCTAssertEqual(workspace.selectedNarrationID, held.id)
        XCTAssertEqual(workspace.playhead, 0)

        workspace.selectNarration(following.id)
        XCTAssertEqual(workspace.selectedNarrationID, following.id)
        XCTAssertEqual(workspace.playhead, 5)
        workspace.previewNarration(following.id)
        XCTAssertEqual(workspace.playhead, 5)
        XCTAssertTrue(workspace.isPlaying)

        workspace.playhead = 7
        workspace.addNarration()
        let added = try XCTUnwrap(workspace.selectedNarration)
        XCTAssertEqual(added.start, 6)
        XCTAssertEqual(added.end, 10)
        XCTAssertEqual(workspace.project?.narrations.count, 3)
        workspace.removeNarration(added.id)
        XCTAssertNil(workspace.selectedNarrationID)
        XCTAssertEqual(workspace.project?.narrations.map(\.id), [held.id, following.id])

        workspace.updateAudioMix(source: 0.2, narration: 0.8)
        XCTAssertEqual(workspace.project?.sourceAudioVolume, 0.2)
        XCTAssertEqual(workspace.project?.narrationVolume, 0.8)
    }

    @MainActor func testTimingAndVoiceNameKeepAudioButSynthesisInputsInvalidateIt() {
        let workspace = Workspace()
        defer { workspace.close() }
        let path = "media/narration/\(UUID().uuidString).mp3"
        let original = narration(audioPath: path, audioDuration: 4)
        let initial = project(with: [original])
        workspace.project = initial
        workspace.assetURLs[path] = URL(fileURLWithPath: "/tmp/immutable-existing.mp3")

        var timing = original
        timing.start = 0.5
        timing.end = 2.5
        XCTAssertTrue(workspace.updateNarration(timing))
        XCTAssertEqual(workspace.project?.narrations[0].audioFile, path)
        XCTAssertEqual(workspace.project?.narrations[0].audioDuration, 4)
        XCTAssertEqual(workspace.project?.narrations[0].start, 0.5)

        var renamed = timing
        renamed.voiceName = "Renamed voice"
        XCTAssertTrue(workspace.updateNarration(renamed))
        XCTAssertEqual(workspace.project?.narrations[0].audioFile, path)

        var changedScript = original
        changedScript.script = "A revised script."
        var changedVoice = original
        changedVoice.voiceID = "voice-2"
        var changedModel = original
        changedModel.modelID = "eleven_flash_v2_5"
        var changedLanguage = original
        changedLanguage.languageCode = "ru"
        for changed in [changedScript, changedVoice, changedModel, changedLanguage] {
            workspace.project = initial
            XCTAssertTrue(workspace.updateNarration(changed))
            XCTAssertNil(workspace.project?.narrations[0].audioFile)
            XCTAssertNil(workspace.project?.narrations[0].audioDuration)
            XCTAssertEqual(workspace.project?.narrations[0].start, original.start)
            XCTAssertEqual(workspace.project?.narrations[0].end, original.end)
            XCTAssertEqual(workspace.assetURLs[path], URL(fileURLWithPath: "/tmp/immutable-existing.mp3"))
        }
    }

    @MainActor func testUndoRedoRestoresReferencesWithoutDeletingImmutableAudio() {
        let workspace = Workspace()
        defer { workspace.close() }
        let undo = UndoManager()
        undo.groupsByEvent = false
        workspace.undoManager = undo
        let path = "media/narration/\(UUID().uuidString).mp3"
        let segment = narration(audioPath: path, audioDuration: 2)
        let initial = project(with: [segment])
        let assetURL = URL(fileURLWithPath: "/tmp/immutable-retake.mp3")
        workspace.project = initial
        workspace.assetURLs[path] = assetURL

        var changed = segment
        changed.script = "Changed script"
        undo.beginUndoGrouping()
        XCTAssertTrue(workspace.updateNarration(changed))
        undo.endUndoGrouping()
        XCTAssertNil(workspace.project?.narrations[0].audioFile)
        XCTAssertEqual(workspace.assetURLs[path], assetURL)

        undo.undo()
        XCTAssertEqual(workspace.project, initial)
        XCTAssertEqual(workspace.project?.narrations[0].audioFile, path)
        XCTAssertEqual(workspace.assetURLs[path], assetURL)
        undo.redo()
        XCTAssertNil(workspace.project?.narrations[0].audioFile)
        XCTAssertEqual(workspace.assetURLs[path], assetURL)
    }

    @MainActor func testInvalidRequestAndFramelessPreflightNeverCallService() async {
        let service = MockNarrationService(.failure)
        let workspace = Workspace()
        defer { workspace.close() }
        var invalid = NarrationSegment(start: 0, end: 1)
        invalid.script = ""
        invalid.voiceID = ""
        workspace.project = project(with: [invalid])
        workspace.generateNarration(invalid.id, service: service)
        XCTAssertNotNil(workspace.error)
        XCTAssertNil(workspace.narrationTask)
        var requestCount = await service.requestCount()
        XCTAssertEqual(requestCount, 0)

        workspace.error = nil
        let cutDraft = narration(start: 2.2, end: 2.8)
        workspace.project = project(
            with: [cutDraft],
            cuts: [TimeRange(start: 2, end: 3)]
        )
        workspace.generateNarration(cutDraft.id, service: service)
        XCTAssertNotNil(workspace.error)
        XCTAssertNil(workspace.narrationTask)
        requestCount = await service.requestCount()
        XCTAssertEqual(requestCount, 0)
    }

    @MainActor func testServiceErrorPreservesExistingAudioAndRecoversControls() async {
        let service = MockNarrationService(.failure)
        let workspace = Workspace()
        defer { workspace.close() }
        let path = "media/narration/\(UUID().uuidString).mp3"
        let initial = project(with: [narration(audioPath: path, audioDuration: 2)])
        workspace.project = initial
        workspace.assetURLs[path] = URL(fileURLWithPath: "/tmp/original.mp3")

        workspace.generateNarration(initial.narrations[0].id, service: service)
        let task = workspace.narrationTask
        await task?.value

        XCTAssertEqual(workspace.project, initial)
        XCTAssertEqual(workspace.assetURLs, [path: URL(fileURLWithPath: "/tmp/original.mp3")])
        XCTAssertNil(workspace.generatingNarrationID)
        XCTAssertNil(workspace.narrationTask)
        XCTAssertTrue(workspace.canEdit)
        XCTAssertNotNil(workspace.error)
        let requestCount = await service.requestCount()
        XCTAssertEqual(requestCount, 1)
    }

    @MainActor func testUnplayableReturnedAudioIsRemovedWithoutReplacingOriginal() async {
        let service = MockNarrationService(.success(SynthesizedAudio(
            data: Data("not playable audio".utf8),
            contentType: "audio/mpeg"
        )))
        let workspace = Workspace()
        defer { workspace.close() }
        let path = "media/narration/\(UUID().uuidString).mp3"
        let originalURL = URL(fileURLWithPath: "/tmp/original-after-invalid-response.mp3")
        let initial = project(with: [narration(audioPath: path, audioDuration: 2)])
        workspace.project = initial
        workspace.assetURLs[path] = originalURL

        workspace.generateNarration(initial.narrations[0].id, service: service)
        let task = workspace.narrationTask
        await task?.value

        XCTAssertEqual(workspace.project, initial)
        XCTAssertEqual(workspace.assetURLs, [path: originalURL])
        XCTAssertTrue(workspace.canEdit)
        XCTAssertNotNil(workspace.error)
    }

    @MainActor func testCancellationBlocksEditsThenPreservesAudioAndRecovers() async {
        let service = MockNarrationService(.waitForCancellation)
        let workspace = Workspace()
        defer { workspace.close() }
        let path = "media/narration/\(UUID().uuidString).mp3"
        let originalURL = URL(fileURLWithPath: "/tmp/original-cancelled.mp3")
        let segment = narration(audioPath: path, audioDuration: 2)
        let initial = project(with: [segment])
        workspace.project = initial
        workspace.assetURLs[path] = originalURL

        workspace.generateNarration(segment.id, service: service)
        let task = workspace.narrationTask
        await service.waitUntilCalled()
        XCTAssertEqual(workspace.generatingNarrationID, segment.id)
        XCTAssertFalse(workspace.canEdit)

        var changed = segment
        changed.script = "Should not apply"
        XCTAssertFalse(workspace.updateNarration(changed))
        workspace.updateAudioMix(source: 0, narration: 0)
        workspace.removeNarration(segment.id)
        workspace.addNarration()
        workspace.selectNarration(segment.id)
        workspace.cut(start: 8, end: 9)
        XCTAssertEqual(workspace.project, initial)
        XCTAssertNil(workspace.selectedNarrationID)

        workspace.cancelNarration()
        await task?.value
        XCTAssertEqual(workspace.project, initial)
        XCTAssertEqual(workspace.assetURLs, [path: originalURL])
        XCTAssertNil(workspace.generatingNarrationID)
        XCTAssertNil(workspace.narrationTask)
        XCTAssertTrue(workspace.canEdit)
        XCTAssertTrue(workspace.status.contains("cancelled"))

        workspace.updateAudioMix(source: 0.4, narration: 0.9)
        XCTAssertEqual(workspace.project?.sourceAudioVolume, 0.4)
        XCTAssertEqual(workspace.project?.narrationVolume, 0.9)
    }

    @MainActor func testSuccessfulRegenerationInstallsPlayableAudioAndKeepsOldAssetForUndo() async throws {
        let audioData = try playableAudioData()
        let service = MockNarrationService(.success(SynthesizedAudio(data: audioData, contentType: "audio/mpeg")))
        let workspace = Workspace()
        defer { workspace.close() }
        let undo = UndoManager()
        undo.groupsByEvent = false
        workspace.undoManager = undo
        let oldPath = "media/narration/\(UUID().uuidString).mp3"
        try workspace.stageAsset(audioData, path: oldPath)
        let initial = project(with: [narration(audioPath: oldPath, audioDuration: 0.12)])
        workspace.project = initial

        undo.beginUndoGrouping()
        workspace.generateNarration(initial.narrations[0].id, service: service)
        let task = workspace.narrationTask
        await task?.value
        undo.endUndoGrouping()

        let generated = try XCTUnwrap(workspace.selectedNarration)
        let newPath = try XCTUnwrap(generated.audioFile)
        XCTAssertNotEqual(newPath, oldPath)
        XCTAssertGreaterThan(try XCTUnwrap(generated.audioDuration), 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(workspace.assetURLs[newPath]).path))
        XCTAssertNotNil(workspace.assetURLs[oldPath])
        let request = await service.lastRequest()
        XCTAssertEqual(request?.text, initial.narrations[0].script)

        undo.undo()
        XCTAssertEqual(workspace.project, initial)
        XCTAssertNotNil(workspace.assetURLs[newPath])
        XCTAssertNotNil(workspace.assetURLs[oldPath])
        undo.redo()
        XCTAssertEqual(workspace.project?.narrations[0].audioFile, newPath)
    }
}
