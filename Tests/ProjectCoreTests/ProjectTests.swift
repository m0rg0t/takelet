import Foundation
import XCTest
@testable import ProjectCore

final class ProjectTests: XCTestCase {
    func testEarlyProjectsKeepOriginalBackground() throws {
        let original = fixture()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        json.removeValue(forKey: "background")
        let decoded = try JSONDecoder().decode(Project.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.background, .midnight)
    }

    func testPresentationRoundTripsAndRejectsUnknownPreset() throws {
        var project = fixture(); project.background = .dawn; project.padding = 0.12
        XCTAssertEqual(try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(project)), project)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(project)) as? [String: Any])
        json["background"] = "unknown-preset"
        XCTAssertThrowsError(try JSONDecoder().decode(Project.self, from: JSONSerialization.data(withJSONObject: json)))
    }

    func fixture() -> Project {
        var project = Project(title: "Demo", duration: 10, width: 1920, height: 1080)
        project.cuts = [TimeRange(start: 1, end: 2), TimeRange(start: 4, end: 6)]
        return project
    }
    func testCutBoundariesMapToNextRetainedFrame() throws {
        let p = fixture(); try p.validate()
        XCTAssertEqual(p.outputDuration, 7)
        XCTAssertEqual(p.sourceTime(forOutput: 1), 2)
        XCTAssertEqual(p.sourceTime(forOutput: 3), 6)
        XCTAssertEqual(p.sourceTime(forOutput: 6.5), 9.5)
        XCTAssertNil(p.sourceTime(forOutput: 7))
        XCTAssertNil(p.outputTime(forSource: 1))
        XCTAssertNil(p.outputTime(forSource: 5))
        XCTAssertEqual(p.outputTime(forSource: 6), 3)
    }
    func testMappingRoundTripsRetainedTime() {
        let p = fixture()
        for time in stride(from: 0.0, to: p.outputDuration, by: 0.037) {
            let source = p.sourceTime(forOutput: time)!
            XCTAssertEqual(p.outputTime(forSource: source)!, time, accuracy: 1e-9)
        }
    }
    func testZoomAndCursorUseSourceTimeAfterCuts() {
        var p = fixture(); p.zooms = [Zoom(start: 6, end: 9, scale: 2)]
        let cursorSourceTime = 6.8
        let cursorOutputTime = p.outputTime(forSource: cursorSourceTime)!
        XCTAssertEqual(cursorOutputTime, 3.8, accuracy: 1e-9)
        XCTAssertEqual(p.zoom(atSource: p.sourceTime(forOutput: cursorOutputTime)!)?.amount(at: 6.8), 2)
        XCTAssertEqual(p.zooms[0].amount(at: 6), 1)
        XCTAssertEqual(p.zooms[0].amount(at: 9), 1)
    }
    func testInvalidEditsDoNotReachRendering() {
        for cuts in [[TimeRange(start: -1, end: 1)], [TimeRange(start: 0, end: 10)], [TimeRange(start: 9, end: 11)], [TimeRange(start: 2, end: 4), TimeRange(start: 3, end: 5)], [TimeRange(start: .nan, end: 2)]] {
            var p = fixture(); p.cuts = cuts
            XCTAssertThrowsError(try p.validate())
        }
    }
    func testRestoringCutsReturnsOriginalDuration() throws {
        var p = fixture(); p.cuts.removeAll(); try p.validate()
        XCTAssertEqual(p.outputDuration, 10)
        XCTAssertEqual(p.sourceTime(forOutput: 5), 5)
    }
    func testMalformedZoomAndPathsRejected() {
        var p = fixture(); p.zooms = [Zoom(scale: .infinity)]
        XCTAssertThrowsError(try p.validate())
        p = fixture(); p.zooms = [Zoom(x: 1.1)]
        XCTAssertThrowsError(try p.validate())
        p = fixture(); p.sourceFile = "../private.mov"
        XCTAssertThrowsError(try p.validate())
        p = fixture(); p.version = 99
        XCTAssertThrowsError(try p.validate())
    }
    func testPortableProjectRoundTripAndMissingAsset() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("original.mov")
        try Data("dummy media bytes for document IO".utf8).write(to: source)
        let destination = root.appendingPathComponent("test.takelet")
        let p = fixture()
        try ProjectStore.create(p, source: source, at: destination)
        let moved = root.appendingPathComponent("moved.takelet")
        try FileManager.default.moveItem(at: destination, to: moved)
        XCTAssertEqual(try ProjectStore.load(from: moved), p)
        XCTAssertThrowsError(try ProjectStore.create(p, source: source, at: moved))
        let nestedSource = try ProjectStore.sourceURL(in: moved)
        try FileManager.default.removeItem(at: nestedSource)
        XCTAssertThrowsError(try ProjectStore.load(from: moved))
    }
    func testProjectSourceCannotEscapeViaSymlink() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("test.takelet")
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("media"), withIntermediateDirectories: true)
        let outside = root.appendingPathComponent("outside.mov")
        try Data("outside".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("media/source.mov"), withDestinationURL: outside)
        XCTAssertThrowsError(try ProjectStore.sourceURL(in: directory))
    }
}
