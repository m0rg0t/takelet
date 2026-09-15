import Foundation
import XCTest
@testable import ProjectCore

final class ZoomTests: XCTestCase {
    private func project() -> Project { Project(title: "Zooms", duration: 10, width: 1920, height: 1080) }
    private func sample(_ time: Double, pressed: Bool, x: Double = 0.7, visible: Bool = true) -> CursorSample {
        CursorSample(time: time, x: x, y: 0.3, visible: visible, pressed: pressed)
    }

    func testLegacyActiveZoomMigratesWithoutChangingItsCurve() throws {
        let json = """
        {"version":1,"title":"Old demo","sourceFile":"media/source.mov","sourceDuration":10,
        "sourceWidth":1920,"sourceHeight":1080,"cuts":[],"padding":0.06,"cursor":[],
        "zoom":{"start":1,"end":4,"scale":2,"x":0.7,"y":0.3}}
        """
        let p = try JSONDecoder().decode(Project.self, from: Data(json.utf8))
        try p.validate()
        XCTAssertEqual(p.version, 4)
        XCTAssertEqual(p.background, .midnight)
        XCTAssertEqual(p.cursorMode, .embedded)
        XCTAssertEqual(p.cursorStyle, .default)
        XCTAssertTrue(p.narrations.isEmpty)
        XCTAssertEqual(p.sourceAudioVolume, 1)
        XCTAssertEqual(p.narrationVolume, 1)
        XCTAssertTrue(p.annotations.isEmpty)
        let zoom = try XCTUnwrap(p.zooms.first)
        XCTAssertEqual(p.zooms.count, 1)
        XCTAssertEqual(zoom.x, 0.7)
        XCTAssertEqual(zoom.amount(at: 1), 1)
        XCTAssertEqual(zoom.amount(at: 1.2), 1.5, accuracy: 1e-9)
        XCTAssertEqual(zoom.amount(at: 2), 2)
        XCTAssertEqual(zoom.amount(at: 4), 1)
        let encoded = try JSONEncoder().encode(p)
        XCTAssertEqual(try JSONDecoder().decode(Project.self, from: encoded), p)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNil(object["zoom"])
        XCTAssertNotNil(object["zooms"])
    }

    func testLegacyDisabledZoomAndUnsupportedVersions() throws {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(project())) as? [String: Any])
        object["version"] = 1; object.removeValue(forKey: "zooms")
        object["zoom"] = ["start": 0, "end": 10, "scale": 1, "x": 0.5, "y": 0.5]
        XCTAssertTrue(try JSONDecoder().decode(Project.self, from: JSONSerialization.data(withJSONObject: object)).zooms.isEmpty)
        object["version"] = 2
        XCTAssertThrowsError(try JSONDecoder().decode(Project.self, from: JSONSerialization.data(withJSONObject: object)))
        object["version"] = 99
        XCTAssertThrowsError(try JSONDecoder().decode(Project.self, from: JSONSerialization.data(withJSONObject: object)))
    }

    func testIndependentZoomsAndUnzoomedGapAfterCuts() throws {
        var p = project()
        let first = Zoom(start: 0.5, end: 2, scale: 1.5, x: 0.2)
        let second = Zoom(start: 6, end: 9, scale: 2.5, x: 0.8)
        p.zooms = [second, first] // Lookup and validation must not depend on JSON array order.
        p.cuts = [TimeRange(start: 3, end: 5)]
        try p.validate()
        XCTAssertEqual(p.zoom(atSource: 1)?.id, first.id)
        XCTAssertNil(p.zoom(atSource: 2))
        XCTAssertNil(p.zoom(atSource: p.sourceTime(forOutput: 3.5)!))
        XCTAssertEqual(p.zoom(atSource: p.sourceTime(forOutput: 5)!)?.id, second.id)
        XCTAssertEqual(p.zoom(atSource: 7)?.amount(at: 7), 2.5)
        XCTAssertNil(p.zoom(atSource: 9))
        XCTAssertNil(p.zoom(atSource: .nan))
    }

    func testTouchingZoomsAreValidButOverlapAndDuplicateIDsAreRejected() throws {
        var p = project()
        p.zooms = [Zoom(start: 0, end: 2), Zoom(start: 2, end: 4)]
        try p.validate()
        XCTAssertEqual(p.zoom(atSource: 2)?.id, p.zooms[1].id)
        XCTAssertEqual(p.zoom(atSource: 2)?.amount(at: 2), 1)
        p.zooms[1].start = 1.99
        XCTAssertThrowsError(try p.validate())
        p.zooms[1].start = 2; p.zooms[1].id = p.zooms[0].id
        XCTAssertThrowsError(try p.validate())
    }

    func testRemovingOneZoomPreservesTheOtherAndRoundTrips() throws {
        var p = project(); let keep = Zoom(start: 5, end: 9, scale: 2.3, x: 0.9)
        p.zooms = [Zoom(start: 0, end: 2), keep]
        p.zooms.removeFirst()
        let decoded = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(decoded.zooms, [keep])
        XCTAssertNil(decoded.zoom(atSource: 1))
        XCTAssertEqual(decoded.zoom(atSource: 6), keep)
    }

    func testManualZoomRespectsCutsNeighborsAndRecordingEnd() throws {
        var p = project(); p.cuts = [TimeRange(start: 4, end: 6)]; p.zooms = [Zoom(start: 2, end: 3)]
        XCTAssertNil(ZoomPlanner.manualZoom(in: p, at: 2.5))
        XCTAssertNil(ZoomPlanner.manualZoom(in: p, at: 5))
        XCTAssertNil(ZoomPlanner.manualZoom(in: p, at: .nan))
        XCTAssertNil(ZoomPlanner.manualZoom(in: p, at: 10))
        let before = try XCTUnwrap(ZoomPlanner.manualZoom(in: p, at: 1))
        XCTAssertEqual(before.start, 1); XCTAssertEqual(before.end, 2)
        let tail = try XCTUnwrap(ZoomPlanner.manualZoom(in: p, at: 9.99))
        XCTAssertEqual(tail.end, 10); XCTAssertGreaterThanOrEqual(tail.duration, 0.39)
        p.zooms += [before, tail]; try p.validate()
    }

    func testClickZoomsIgnoreHeldButtonsAndCanBeRunAgainWithoutDuplicates() throws {
        var p = project()
        p.cursor = [sample(0, pressed: false), sample(1, pressed: true), sample(1.1, pressed: true), sample(1.2, pressed: false), sample(1.3, pressed: true), sample(3, pressed: false), sample(5, pressed: true, x: 0.2)]
        let zooms = ZoomPlanner.clickZooms(in: p)
        XCTAssertEqual(zooms.count, 2)
        XCTAssertEqual(zooms[0].start, 0.6, accuracy: 1e-9)
        XCTAssertEqual(zooms[0].end, 2.2, accuracy: 1e-9)
        XCTAssertEqual(zooms[0].x, 0.7)
        XCTAssertEqual(zooms[1].x, 0.2)
        p.zooms = zooms; try p.validate()
        XCTAssertTrue(ZoomPlanner.clickZooms(in: p).isEmpty)
    }

    func testClickZoomsSkipCutsInvisibleClicksAndExistingEdits() throws {
        var p = project(); p.cuts = [TimeRange(start: 2, end: 4)]
        let manual = Zoom(start: 6, end: 8, scale: 2.7)
        p.zooms = [manual]
        p.cursor = [sample(1, pressed: true, visible: false), sample(1.1, pressed: true), sample(2, pressed: false), sample(3, pressed: true), sample(4, pressed: false), sample(4.1, pressed: true), sample(6, pressed: false), sample(7, pressed: true)]
        let zooms = ZoomPlanner.clickZooms(in: p)
        XCTAssertEqual(zooms.count, 1)
        XCTAssertEqual(zooms[0].start, 4)
        XCTAssertLessThan(zooms[0].end, manual.start)
        XCTAssertEqual(p.zooms, [manual])
        p.zooms += zooms; try p.validate()
    }

    func testClickZoomsClipToNeighborAndRejectShortGapsOrInvalidFocus() throws {
        var p = project(); p.zooms = [Zoom(start: 2, end: 5)]
        p.cursor = [sample(1.5, pressed: true), sample(5, pressed: false), sample(5.1, pressed: true, x: 2), sample(9.8, pressed: false), sample(9.9, pressed: true)]
        let zooms = ZoomPlanner.clickZooms(in: p)
        XCTAssertEqual(zooms.count, 1)
        XCTAssertEqual(zooms[0].end, 2)
        p.zooms += zooms; try p.validate()
        XCTAssertTrue(ZoomPlanner.clickZooms(in: project()).isEmpty)
    }
}
