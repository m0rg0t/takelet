import Foundation
import XCTest
@testable import ProjectCore

final class ProjectAssetTests: XCTestCase {
    private struct Fixture {
        let root: URL
        let source: URL
        let narrationSource: URL
        let cursorSource: URL
        let narrationPath: String
        let cursorPath: String
        let project: Project
    }

    private func fixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let source = root.appendingPathComponent("source.mov")
        let narrationSource = root.appendingPathComponent("narration.mp3")
        let cursorSource = root.appendingPathComponent("cursor.png")
        try Data("source-media".utf8).write(to: source)
        try Data("narration-audio".utf8).write(to: narrationSource)
        try Data("cursor-image".utf8).write(to: cursorSource)

        let narrationPath = "media/narration/\(UUID().uuidString).mp3"
        let cursorPath = "media/cursors/\(UUID().uuidString).png"
        var project = Project(title: "Portable assets", duration: 4, width: 1920, height: 1080)
        project.cursorMode = .separate
        project.cursorStyle = CursorStyle(shape: .customImage, imageFile: cursorPath)
        project.narrations = [NarrationSegment(
            start: 0,
            end: 2,
            script: "Welcome to the walkthrough.",
            voiceID: "voice-1",
            voiceName: "Narrator",
            languageCode: "en",
            audioFile: narrationPath,
            audioDuration: 2.5
        )]
        return Fixture(
            root: root,
            source: source,
            narrationSource: narrationSource,
            cursorSource: cursorSource,
            narrationPath: narrationPath,
            cursorPath: cursorPath,
            project: project
        )
    }

    func testVersionTwoMigratesWithCurrentDefaults() throws {
        let json = """
        {"version":2,"title":"Version two","sourceFile":"media/source.mov","sourceDuration":10,
        "sourceWidth":1920,"sourceHeight":1080,"cuts":[],"zooms":[],"padding":0.06,
        "background":"dawn","cursor":[]}
        """
        let project = try JSONDecoder().decode(Project.self, from: Data(json.utf8))
        try project.validate()

        XCTAssertEqual(project.version, 4)
        XCTAssertEqual(project.background, .dawn)
        XCTAssertEqual(project.cursorMode, .embedded)
        XCTAssertEqual(project.cursorStyle, .default)
        XCTAssertTrue(project.narrations.isEmpty)
        XCTAssertEqual(project.sourceAudioVolume, 1)
        XCTAssertEqual(project.narrationVolume, 1)
        XCTAssertTrue(project.annotations.isEmpty)

        let encoded = try JSONEncoder().encode(project)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(object["version"] as? Int, 4)
        XCTAssertNotNil(object["cursorMode"])
        XCTAssertNotNil(object["cursorStyle"])
        XCTAssertNotNil(object["narrations"])
        XCTAssertNotNil(object["sourceAudioVolume"])
        XCTAssertNotNil(object["narrationVolume"])
        XCTAssertNotNil(object["annotations"])
    }

    func testNarrationAndCursorAssetsSurviveSaveReopenAndMove() throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let original = fixture.root.appendingPathComponent("original.takelet")
        try ProjectStore.create(
            fixture.project,
            source: fixture.source,
            at: original,
            assets: [
                fixture.narrationPath: fixture.narrationSource,
                fixture.cursorPath: fixture.cursorSource
            ]
        )

        let movedParent = fixture.root.appendingPathComponent("moved")
        try FileManager.default.createDirectory(at: movedParent, withIntermediateDirectories: true)
        let moved = movedParent.appendingPathComponent("portable.takelet")
        try FileManager.default.moveItem(at: original, to: moved)

        XCTAssertEqual(try ProjectStore.load(from: moved), fixture.project)
        let assets = try ProjectStore.assetURLs(for: fixture.project, in: moved)
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(assets[fixture.narrationPath])), Data("narration-audio".utf8))
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(assets[fixture.cursorPath])), Data("cursor-image".utf8))
        XCTAssertEqual(try Data(contentsOf: ProjectStore.sourceURL(in: moved)), Data("source-media".utf8))
    }

    func testCreateAndLoadRejectMissingReferencedAssets() throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let missingOnCreate = fixture.root.appendingPathComponent("missing-create.takelet")
        XCTAssertThrowsError(try ProjectStore.create(
            fixture.project,
            source: fixture.source,
            at: missingOnCreate,
            assets: [fixture.cursorPath: fixture.cursorSource]
        ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: missingOnCreate.path))

        let saved = fixture.root.appendingPathComponent("missing-load.takelet")
        try ProjectStore.create(
            fixture.project,
            source: fixture.source,
            at: saved,
            assets: [
                fixture.narrationPath: fixture.narrationSource,
                fixture.cursorPath: fixture.cursorSource
            ]
        )
        try FileManager.default.removeItem(at: saved.appendingPathComponent(fixture.cursorPath))
        XCTAssertThrowsError(try ProjectStore.load(from: saved))
    }

    func testAssetSymlinkCannotEscapeProjectPackage() throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let package = fixture.root.appendingPathComponent("symlink.takelet")
        try FileManager.default.createDirectory(
            at: package.appendingPathComponent("media/narration"),
            withIntermediateDirectories: true
        )
        let outside = fixture.root.appendingPathComponent("outside.mp3")
        try Data("outside".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(
            at: package.appendingPathComponent(fixture.narrationPath),
            withDestinationURL: outside
        )

        XCTAssertThrowsError(try ProjectStore.assetURL(fixture.narrationPath, in: package))
    }

    func testSavingNeverOverwritesAnImmutableAssetCollision() throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let package = fixture.root.appendingPathComponent("collision.takelet")
        try ProjectStore.create(
            fixture.project,
            source: fixture.source,
            at: package,
            assets: [
                fixture.narrationPath: fixture.narrationSource,
                fixture.cursorPath: fixture.cursorSource
            ]
        )
        let projectJSON = package.appendingPathComponent("project.json")
        let metadataBefore = try Data(contentsOf: projectJSON)
        let narrationDestination = package.appendingPathComponent(fixture.narrationPath)
        let narrationBefore = try Data(contentsOf: narrationDestination)
        let conflicting = fixture.root.appendingPathComponent("different.mp3")
        try Data("different-narration-audio".utf8).write(to: conflicting)

        XCTAssertThrowsError(try ProjectStore.save(
            fixture.project,
            to: package,
            assets: [fixture.narrationPath: conflicting]
        ))
        XCTAssertEqual(try Data(contentsOf: narrationDestination), narrationBefore)
        XCTAssertEqual(try Data(contentsOf: projectJSON), metadataBefore)

        let identical = fixture.root.appendingPathComponent("identical.mp3")
        try narrationBefore.write(to: identical)
        XCTAssertNoThrow(try ProjectStore.save(
            fixture.project,
            to: package,
            assets: [fixture.narrationPath: identical]
        ))
    }
}
