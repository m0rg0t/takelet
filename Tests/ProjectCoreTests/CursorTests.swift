import Foundation
import XCTest
@testable import ProjectCore

final class CursorTests: XCTestCase {
    private func sample(
        _ time: Double,
        _ x: Double,
        _ y: Double = 0.5,
        visible: Bool = true,
        pressed: Bool = false
    ) -> CursorSample {
        CursorSample(time: time, x: x, y: y, visible: visible, pressed: pressed)
    }

    func testStyleDefaultsValidateAndRoundTrip() throws {
        let style = CursorStyle()
        try style.validate()
        XCTAssertEqual(style.shape, .arrow)
        XCTAssertEqual(style.size, 32)
        XCTAssertTrue(style.clickHalo)
        XCTAssertFalse(style.hidden)
        XCTAssertEqual(try JSONDecoder().decode(CursorStyle.self, from: JSONEncoder().encode(style)), style)
        XCTAssertEqual(try JSONDecoder().decode(CursorRecordingMode.self, from: Data("\"separate\"".utf8)), .separate)
    }

    func testStyleRejectsInvalidNumbersAndNonPortableImages() throws {
        var style = CursorStyle(size: 7)
        XCTAssertThrowsError(try style.validate())
        style = CursorStyle(smoothing: .nan)
        XCTAssertThrowsError(try style.validate())
        style = CursorStyle(hotspotX: 1.01)
        XCTAssertThrowsError(try style.validate())
        style = CursorStyle(color: CursorRGBA(red: -0.1))
        XCTAssertThrowsError(try style.validate())
        style = CursorStyle(shape: .customImage)
        XCTAssertThrowsError(try style.validate())
        style.imageFile = "/tmp/cursor.png"
        XCTAssertThrowsError(try style.validate())
        style.imageFile = "media/cursors/not-a-uuid.png"
        XCTAssertThrowsError(try style.validate())
        style.imageFile = "media/cursors/48FC5632-B279-44E5-B42D-37B6D16E833C.png"
        XCTAssertNoThrow(try style.validate())
    }

    func testInterpolatesOnOriginalSourceTimeline() throws {
        let timeline = CursorTimeline(samples: [sample(2, 0.2, 0.8), sample(2.1, 0.8, 0.2)], smoothing: 0)
        XCTAssertNil(timeline.frame(at: 1.99))
        let midpoint = try XCTUnwrap(timeline.frame(at: 2.05))
        XCTAssertEqual(midpoint.position.x, 0.5, accuracy: 1e-9)
        XCTAssertEqual(midpoint.position.y, 0.5, accuracy: 1e-9)
        XCTAssertEqual(timeline.frame(at: 2.1)?.position.x, 0.8)
        XCTAssertEqual(timeline.frame(at: 2.2)?.position.x, 0.8)
        XCTAssertNil(timeline.frame(at: 2.36))
    }

    func testInvisibleOutOfBoundsAndMissingSamplesSplitSpans() throws {
        let timeline = CursorTimeline(samples: [
            sample(0, 0.1), sample(0.1, 0.2),
            sample(0.2, 0.3, visible: false),
            sample(0.3, 0.4), sample(0.4, 1.1), sample(0.5, 0.5),
            sample(1, 0.9), sample(1.1, 1)
        ], smoothing: 0)
        XCTAssertEqual(timeline.frame(at: 0.1)?.position.x, 0.2)
        XCTAssertNil(timeline.frame(at: 0.15))
        XCTAssertNil(timeline.frame(at: 0.2))
        XCTAssertEqual(timeline.frame(at: 0.3)?.position.x, 0.4)
        XCTAssertNil(timeline.frame(at: 0.45))
        XCTAssertNil(timeline.frame(at: 0.8))
        XCTAssertEqual(timeline.frame(at: 1)?.position.x, 0.9)

        let leavesFrame = CursorTimeline(samples: [sample(0, 0.1), sample(0.1, 0.2, visible: false)], smoothing: 0)
        XCTAssertNotNil(leavesFrame.frame(at: 0.099))
        XCTAssertNil(leavesFrame.frame(at: 0.1))
    }

    func testSmoothingRestartsAtEveryVisibilityBoundary() throws {
        let timeline = CursorTimeline(samples: [
            sample(0, 0), sample(0.1, 1), sample(0.2, 0, visible: false),
            sample(0.3, 0.25), sample(0.4, 0.75)
        ], smoothing: 1)
        let smoothedFirstSpan = try XCTUnwrap(timeline.frame(at: 0.1))
        XCTAssertGreaterThan(smoothedFirstSpan.position.x, 0)
        XCTAssertLessThan(smoothedFirstSpan.position.x, 1)
        XCTAssertEqual(try XCTUnwrap(timeline.frame(at: 0.3)).position.x, 0.25, accuracy: 1e-12)
    }

    func testClickHaloStartsOnlyOnObservedPressEdgesAndFadesOnce() throws {
        let timeline = CursorTimeline(samples: [
            sample(0, 0.1, pressed: true), // No prior release: do not invent a click.
            sample(0.1, 0.2, pressed: false),
            sample(0.2, 0.3, pressed: true),
            sample(0.3, 0.4, pressed: true),
            sample(0.4, 0.5, pressed: false),
            sample(0.5, 0.6, pressed: true)
        ], smoothing: 0)
        XCTAssertNil(timeline.frame(at: 0.05)?.halo)
        XCTAssertEqual(timeline.frame(at: 0.2)?.halo?.progress, 0)
        XCTAssertEqual(timeline.frame(at: 0.3)?.halo?.progress ?? -1, 0.1 / CursorTimeline.clickHaloDuration, accuracy: 1e-9)
        XCTAssertEqual(timeline.frame(at: 0.5)?.halo?.progress, 0)
    }

    func testClickStateDoesNotCrossInvisibleOrMissingGaps() {
        let timeline = CursorTimeline(samples: [
            sample(0, 0.1, pressed: false),
            sample(0.1, 0.2, visible: false, pressed: false),
            sample(0.2, 0.3, pressed: true),
            sample(0.7, 0.4, pressed: false),
            sample(0.8, 0.5, pressed: true)
        ], smoothing: 0)
        XCTAssertNil(timeline.frame(at: 0.2)?.halo)
        XCTAssertNil(timeline.frame(at: 0.7)?.halo)
        XCTAssertEqual(timeline.frame(at: 0.8)?.halo?.progress, 0)
    }
}
