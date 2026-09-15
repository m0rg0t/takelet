import SwiftUI
import AVKit
import UniformTypeIdentifiers
import ProjectCore
import MediaEngine

extension UTType { static let takeletProject = UTType(exportedAs: "io.github.m0rg0t.takelet.project", conformingTo: .package) }

@MainActor final class Workspace: ObservableObject {
    @Published var project: Project?
    @Published var projectURL: URL?
    @Published var sourceURL: URL?
    @Published var player = AVPlayer()
    @Published var windows: [CaptureWindow] = []
    @Published var selectedWindowID: UInt32?
    @Published var systemAudio = true
    @Published var microphone = false
    @Published var recording = false
    @Published var busy = false
    @Published var exporting = false
    @Published var exportProgress = 0.0
    @Published var error: String?
    @Published var status = "Create a recording or import a video to begin."
    @Published var playhead = 0.0
    @Published var isPlaying = false
    @Published var thumbnails: [NSImage] = []
    @Published var dirty = false
    @Published var selectedZoomID: UUID?
    weak var undoManager: UndoManager?
    private let recorder = WindowRecorder()
    private let exporter = VideoExporter()
    private var recordingURL: URL?
    private var sourceIsTemporary = false
    private var savedProject: Project?
    private var previewGeneration = 0
    private var observer: Any?
    private var captureLimit: Task<Void, Never>?

    init() {
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor in
                self?.playhead = time.seconds.isFinite ? time.seconds : 0
                self?.isPlaying = self?.player.rate != 0
            }
        }
        recorder.onFailure = { [weak self] error in
            guard let self else { return }
            self.error = "\(error.localizedDescription) A partial recording, if available, remains in the temporary Takelet folder."
            if recording && !busy { stopRecording() }
        }
        WorkspaceRegistry.shared.add(self)
    }

    var canEdit: Bool { project != nil && !busy && !recording && !exporting }
    var sourcePosition: Double {
        guard let project else { return 0 }
        return project.sourceTime(forOutput: min(playhead, max(0, project.outputDuration - 0.001))) ?? 0
    }
    var selectedZoom: Zoom? { project?.zooms.first { $0.id == selectedZoomID } }
    var canClose: Bool {
        if recording || busy || exporting {
            let alert = NSAlert(); alert.messageText = "Finish the current operation first"; alert.informativeText = "Stop recording or cancel export before closing this window."; alert.runModal(); return false
        }
        guard dirty else { return true }
        let alert = NSAlert(); alert.messageText = "Discard unsaved changes?"; alert.informativeText = "Save the project to keep its recording and edits."
        alert.addButton(withTitle: "Keep Editing"); alert.addButton(withTitle: "Discard Changes")
        return alert.runModal() == .alertSecondButtonReturn
    }

    func refreshWindows() {
        guard !busy, !recording, !exporting else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                windows = try await WindowRecorder.windows()
                if !windows.contains(where: { $0.id == selectedWindowID }) { selectedWindowID = windows.first?.id }
                status = windows.isEmpty ? "No eligible windows found. Open another app and refresh." : "Select the window you want to record."
            } catch { self.error = "\(error.localizedDescription) Enable Takelet in System Settings → Privacy & Security → Screen & System Audio Recording, then reopen Takelet." }
        }
    }

    func startRecording() {
        guard !busy, !recording, !exporting, let window = windows.first(where: { $0.id == selectedWindowID }), canClose else { return }
        busy = true; player.pause()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("takelet-recording-\(UUID().uuidString).mp4")
        recordingURL = url
        Task {
            defer { busy = false }
            do {
                try await recorder.start(window: window, destination: url, systemAudio: systemAudio, microphone: microphone)
                recording = true
                status = "Recording \(window.window.owningApplication?.applicationName ?? "window") — ⌘⇧R to stop."
                captureLimit = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(600)) } catch { return }
                    self?.stopRecording()
                }
            } catch { self.error = error.localizedDescription }
        }
    }

    func stopRecording() {
        guard recording, !busy else { return }
        busy = true; captureLimit?.cancel(); captureLimit = nil
        Task {
            defer { busy = false; recording = false }
            do {
                let samples = try await recorder.stop()
                guard let url = recordingURL else { throw ProjectError("Missing recording destination.") }
                try await install(source: url, temporary: true, cursor: samples)
                status = "Recording ready. Save the project to keep a portable copy."
            } catch { self.error = "\(error.localizedDescription) Recording location: \(recordingURL?.path ?? "unavailable")" }
        }
    }

    func importVideo() {
        guard !busy, !recording, !exporting, canClose else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.movie]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        busy = true
        Task {
            defer { busy = false }
            do { try await install(source: url, temporary: false); status = "Video imported. Save a project to keep a portable copy." }
            catch { self.error = error.localizedDescription }
        }
    }

    private func install(source: URL, temporary: Bool, cursor: [CursorSample] = []) async throws {
        let info = try await MediaInspector.inspect(source)
        var draft = Project(title: source.deletingPathExtension().lastPathComponent, duration: info.duration, width: info.width, height: info.height)
        if temporary { draft.title = "Untitled Demo" }
        draft.cursor = cursor.filter { $0.time <= info.duration }
        try draft.validate()
        selectedZoomID = nil
        project = draft; sourceURL = source; projectURL = nil; sourceIsTemporary = temporary
        savedProject = nil; dirty = true; undoManager?.removeAllActions()
        await refreshPreview()
    }

    func openProject(_ url: URL? = nil) {
        guard !busy, !recording, !exporting, canClose else { return }
        var chosen = url
        if chosen == nil {
            let panel = NSOpenPanel(); panel.allowedContentTypes = [.takeletProject]; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
            guard panel.runModal() == .OK else { return }; chosen = panel.url
        }
        guard let chosen else { return }
        do {
            let loaded = try ProjectStore.load(from: chosen)
            selectedZoomID = nil
            sourceURL = try ProjectStore.sourceURL(in: chosen); projectURL = chosen; project = loaded
            sourceIsTemporary = false; savedProject = loaded; dirty = false; undoManager?.removeAllActions()
            NSDocumentController.shared.noteNewRecentDocumentURL(chosen)
            Task { await refreshPreview() }
            status = "Opened \(chosen.lastPathComponent)."
        } catch { self.error = error.localizedDescription }
    }

    func saveProject() {
        guard let project, let sourceURL, canEdit else { return }
        do {
            if let projectURL { try ProjectStore.save(project, to: projectURL) }
            else {
                let panel = NSSavePanel(); panel.allowedContentTypes = [.takeletProject]; panel.nameFieldStringValue = "\(project.title).takelet"; panel.canCreateDirectories = true
                guard panel.runModal() == .OK, let destination = panel.url else { return }
                try ProjectStore.create(project, source: sourceURL, at: destination)
                if sourceIsTemporary { try? FileManager.default.removeItem(at: sourceURL) }
                self.sourceURL = try ProjectStore.sourceURL(in: destination); projectURL = destination; sourceIsTemporary = false
                NSDocumentController.shared.noteNewRecentDocumentURL(destination)
                Task { await refreshPreview() }
            }
            savedProject = project; dirty = false; status = "Project saved."
        } catch { self.error = error.localizedDescription }
    }

    func edit(_ next: Project, name: String) {
        do { try next.validate() } catch { self.error = error.localizedDescription; return }
        guard let previous = project, previous != next else { return }
        undoManager?.registerUndo(withTarget: self) { target in
            // AppKit invokes this window's undo actions on the main thread. Keep redo registration synchronous.
            MainActor.assumeIsolated { target.edit(previous, name: name) }
        }
        undoManager?.setActionName(name)
        project = next; dirty = next != savedProject
        if let selectedZoomID, !next.zooms.contains(where: { $0.id == selectedZoomID }) { self.selectedZoomID = nil }
        Task { await refreshPreview() }
    }

    func selectZoom(_ id: UUID) {
        guard canEdit, let zoom = project?.zooms.first(where: { $0.id == id }) else { return }
        selectedZoomID = id
        player.pause(); isPlaying = false
        seekSource(zoom.start + min(0.4, zoom.duration / 2))
    }

    func addZoom() {
        guard canEdit, var next = project else { return }
        if let existing = next.zoom(atSource: sourcePosition) {
            selectZoom(existing.id); status = "This position already has a zoom. Select an empty part of the take to add another."; return
        }
        guard let zoom = ZoomPlanner.manualZoom(in: next, at: sourcePosition) else {
            status = "Choose a longer uncut interval without a zoom."; return
        }
        next.zooms.append(zoom); next.zooms.sort { $0.start < $1.start }
        edit(next, name: "Add Zoom"); selectedZoomID = zoom.id
        status = "Zoom added at the playhead. Adjust its timing and focus in the inspector."
    }

    func updateZoom(_ zoom: Zoom) {
        guard canEdit, var next = project, let index = next.zooms.firstIndex(where: { $0.id == zoom.id }) else { return }
        next.zooms[index] = zoom; next.zooms.sort { $0.start < $1.start }
        edit(next, name: "Change Zoom")
    }

    func removeZoom(_ id: UUID) {
        guard canEdit, var next = project else { return }
        next.zooms.removeAll { $0.id == id }
        edit(next, name: "Remove Zoom")
    }

    func generateClickZooms() {
        guard canEdit, var next = project else { return }
        let additions = ZoomPlanner.clickZooms(in: next)
        guard !additions.isEmpty else {
            status = next.cursor.isEmpty ? "Auto Zoom needs click data from Takelet's recorder. Add manual zooms to imported videos." : "No uncovered clicks found with enough room for a zoom. Existing zooms were kept."
            return
        }
        next.zooms.append(contentsOf: additions); next.zooms.sort { $0.start < $1.start }
        edit(next, name: "Auto Zoom from Clicks"); selectedZoomID = additions.first?.id
        status = "Added \(additions.count) editable zoom\(additions.count == 1 ? "" : "s") from clicks. Review timing and focus before export."
    }

    func cut(start: Double, end: Double) {
        guard var next = project else { return }
        next.cuts.append(TimeRange(start: start, end: end)); next.cuts.sort { $0.start < $1.start }
        edit(next, name: "Remove Interval")
    }

    func refreshPreview() async {
        guard let project, let sourceURL else { return }
        previewGeneration += 1; let generation = previewGeneration
        let position = min(playhead, max(0, project.outputDuration - 0.05))
        player.pause(); isPlaying = false
        do {
            let prepared = try await CompositionBuilder.build(project: project, source: sourceURL, width: 1280, height: 720)
            guard generation == previewGeneration else { return }
            let item = AVPlayerItem(asset: prepared.asset); item.videoComposition = prepared.video
            player.replaceCurrentItem(with: item)
            await player.seek(to: CMTime(seconds: position, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        } catch { if generation == previewGeneration { self.error = error.localizedDescription } }
    }

    func togglePlayback() {
        if player.rate == 0 {
            if let project, playhead >= project.outputDuration - 0.04 { seek(0) }
            player.play(); isPlaying = true
        } else { player.pause(); isPlaying = false }
    }
    func seek(_ time: Double) {
        playhead = time
        player.seek(to: CMTime(seconds: time, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func seekSource(_ time: Double) {
        guard let project else { return }
        let source = min(max(time, 0), project.sourceDuration)
        let removed = project.cuts.reduce(0.0) { $0 + min(max(source - $1.start, 0), $1.duration) }
        seek(min(source - removed, max(0, project.outputDuration - 0.001)))
    }

    func loadThumbnails() async {
        thumbnails = []
        guard let sourceURL, let project else { return }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: sourceURL))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 320, height: 180)
        defer { generator.cancelAllCGImageGeneration() }
        var images: [NSImage] = []
        for index in 0..<10 {
            guard !Task.isCancelled else { return }
            let seconds = project.sourceDuration * (Double(index) + 0.5) / 10
            do {
                let frame = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
                images.append(NSImage(cgImage: frame, size: .zero))
            } catch { return } // The player reports media failures; thumbnails are optional.
        }
        guard !Task.isCancelled, self.sourceURL == sourceURL else { return }
        thumbnails = images
    }

    func exportVideo(width: Int) {
        guard let project, let sourceURL, canEdit else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.mpeg4Movie]; panel.nameFieldStringValue = "\(project.title)-\(width == 3840 ? "4K" : "1080p").mp4"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        exporting = true; exportProgress = 0; player.pause()
        Task {
            let progress = Task { [weak self] in
                while !Task.isCancelled {
                    self?.exportProgress = self?.exporter.progress ?? 0
                    do { try await Task.sleep(for: .milliseconds(150)) } catch { break }
                }
            }
            defer { exporting = false; progress.cancel() }
            do {
                try await exporter.export(project: project, source: sourceURL, destination: destination, width: width, height: width == 3840 ? 2160 : 1080)
                status = "Exported \(destination.lastPathComponent)."
                NSWorkspace.shared.activateFileViewerSelecting([destination])
            } catch is CancellationError { status = "Export cancelled." }
            catch { if (error as NSError).code == AVError.operationCancelled.rawValue { status = "Export cancelled." } else { self.error = error.localizedDescription } }
        }
    }
    func cancelExport() { exporter.cancel() }
    func close() { player.pause(); if let observer { player.removeTimeObserver(observer); self.observer = nil }; captureLimit?.cancel() }
}

@MainActor final class WorkspaceRegistry {
    static let shared = WorkspaceRegistry()
    private var workspaces = NSHashTable<Workspace>.weakObjects()
    func add(_ workspace: Workspace) { workspaces.add(workspace) }
    func canQuit() -> Bool { workspaces.allObjects.allSatisfy(\.canClose) }
}
