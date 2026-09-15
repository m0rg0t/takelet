import Foundation
import XCTest
@testable import ProjectCore

final class AnnotationTests: XCTestCase {
    private func project() -> Project {
        Project(title: "Annotations", duration: 10, width: 1920, height: 1080)
    }

    func testKindsDirectionsAndDefaultsExposeRendererContract() throws {
        XCTAssertEqual(AnnotationKind.allCases, [.arrow, .frame, .text, .blur, .cover])
        XCTAssertEqual(AnnotationKind.allCases.map(\.title), ["Arrow", "Frame", "Text", "Blur", "Opaque Mask"])
        XCTAssertEqual(AnnotationKind.allCases.filter(\.isMask), [.blur, .cover])
        XCTAssertEqual(AnnotationDirection.allCases, [.downRight, .downLeft, .upRight, .upLeft])

        let annotation = Annotation(kind: .arrow, start: 1, end: 2)
        XCTAssertEqual(annotation.bounds, AnnotationBounds())
        XCTAssertEqual(annotation.color, .orange)
        XCTAssertEqual(annotation.text, "Callout")
        XCTAssertEqual(annotation.direction, .downRight)
        XCTAssertEqual(annotation.strokeWidth, 0.006)
        XCTAssertEqual(annotation.fontSize, 0.05)
        XCTAssertEqual(annotation.blurRadius, 0.02)
        try annotation.validate(duration: 10)
    }

    func testBoundsValidateEdgesAndGeometryHelpersClampSafely() throws {
        try AnnotationBounds(x: 0, y: 0, width: 1, height: 1).validate()
        try AnnotationBounds(x: 0.99, y: 0.99, width: 0.01, height: 0.01).validate()
        try AnnotationBounds(x: 0.1, y: 0.7, width: (0.1 + 0.01) - 0.1, height: (0.7 + 0.01) - 0.7).validate()
        try AnnotationBounds(x: 0.7, y: 0.3, width: 0.3.nextUp, height: 0.2).validate()

        let bounds = AnnotationBounds()
        XCTAssertEqual(bounds.translated(dx: 10, dy: 10), AnnotationBounds(x: 0.6, y: 0.8, width: 0.4, height: 0.2))
        XCTAssertEqual(bounds.translated(dx: -10, dy: -10), AnnotationBounds(x: 0, y: 0, width: 0.4, height: 0.2))
        XCTAssertEqual(bounds.resized(width: 2, height: -1), AnnotationBounds(x: 0.3, y: 0.3, width: 0.7, height: 0.01))

        let malformed = AnnotationBounds(x: .nan, y: .infinity, width: -.infinity, height: .nan)
        let safelyMoved = malformed.translated(dx: .nan, dy: .infinity)
        let safelyResized = malformed.resized(width: .nan, height: .infinity)
        XCTAssertNoThrow(try safelyMoved.validate())
        XCTAssertNoThrow(try safelyResized.validate())

        for invalid in [
            AnnotationBounds(x: -0.01),
            AnnotationBounds(y: -0.01),
            AnnotationBounds(width: 0.009),
            AnnotationBounds(height: 0.009),
            AnnotationBounds(x: 0.7, width: 0.4),
            AnnotationBounds(y: 0.9, height: 0.2),
            AnnotationBounds(x: .nan),
            AnnotationBounds(height: .infinity)
        ] {
            XCTAssertThrowsError(try invalid.validate())
        }
    }

    func testAnnotationUsesHalfOpenSourceTimeAndValidatesLimits() throws {
        let annotation = Annotation(kind: .text, start: 1, end: 3, text: "Look here")
        XCTAssertEqual(annotation.duration, 2)
        XCTAssertFalse(annotation.isVisible(atSource: 0.999))
        XCTAssertTrue(annotation.isVisible(atSource: 1))
        XCTAssertTrue(annotation.isVisible(atSource: 2.999))
        XCTAssertFalse(annotation.isVisible(atSource: 3))
        XCTAssertFalse(annotation.isVisible(atSource: .nan))
        try annotation.validate(duration: 10)
        try Annotation(kind: .frame, start: 0, end: 10, strokeWidth: 0.001, fontSize: 0.015, blurRadius: 0.003).validate(duration: 10)
        try Annotation(kind: .blur, start: 0, end: 10, strokeWidth: 0.03, fontSize: 0.18, blurRadius: 0.08).validate(duration: 10)

        var invalid = annotation
        invalid.end = 11
        XCTAssertThrowsError(try invalid.validate(duration: 10))
        invalid = annotation; invalid.start = .nan
        XCTAssertThrowsError(try invalid.validate(duration: 10))
        invalid = annotation; invalid.text = String(repeating: "a", count: 501)
        XCTAssertThrowsError(try invalid.validate(duration: 10))
        invalid = annotation; invalid.text = "  \n "
        XCTAssertThrowsError(try invalid.validate(duration: 10))
        invalid = annotation; invalid.strokeWidth = 0.0009
        XCTAssertThrowsError(try invalid.validate(duration: 10))
        invalid = annotation; invalid.fontSize = .infinity
        XCTAssertThrowsError(try invalid.validate(duration: 10))
        invalid = annotation; invalid.blurRadius = 0.081
        XCTAssertThrowsError(try invalid.validate(duration: 10))
        invalid = annotation; invalid.color.red = -0.01
        XCTAssertThrowsError(try invalid.validate(duration: 10))
    }

    func testProjectAllowsOverlapPreservesPaintOrderAndRoundTrips() throws {
        var value = project()
        let arrow = Annotation(kind: .arrow, start: 1, end: 5)
        let blur = Annotation(kind: .blur, start: 2, end: 4)
        let text = Annotation(kind: .text, start: 1, end: 5, text: "Top")
        let cover = Annotation(kind: .cover, start: 1, end: 5)
        value.annotations = [blur, arrow, cover, text]

        try value.validate()
        XCTAssertEqual(value.annotations.filter { !$0.kind.isMask }.map(\.id), [arrow.id, text.id])
        XCTAssertEqual(value.annotations.filter { $0.kind.isMask }.map(\.id), [blur.id, cover.id])
        let decoded = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(value))
        XCTAssertEqual(decoded, value)
        XCTAssertEqual(decoded.annotations.map(\.id), [blur.id, arrow.id, cover.id, text.id])
    }

    func testProjectRejectsDuplicateIDsCountAndInvalidAnnotations() throws {
        var value = project()
        let annotation = Annotation(kind: .frame, start: 1, end: 2)
        value.annotations = [annotation, annotation]
        XCTAssertThrowsError(try value.validate())

        value.annotations = (0...64).map { index in
            Annotation(kind: .arrow, start: Double(index) / 100, end: 9)
        }
        XCTAssertThrowsError(try value.validate())

        value.annotations = [Annotation(kind: .text, start: 1, end: 2, text: "")]
        XCTAssertThrowsError(try value.validate())
    }

    func testVersionThreeMigratesEmptyAndVersionFourRequiresAnnotations() throws {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(project())) as? [String: Any])
        object["version"] = 3
        object.removeValue(forKey: "annotations")
        let versionThree = try JSONDecoder().decode(Project.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(versionThree.version, 4)
        XCTAssertTrue(versionThree.annotations.isEmpty)
        try versionThree.validate()

        object["version"] = 4
        XCTAssertThrowsError(try JSONDecoder().decode(Project.self, from: JSONSerialization.data(withJSONObject: object)))
    }

    func testAnnotationsRemainInSourceTimeAcrossCutAndNarrationHold() throws {
        var value = project()
        value.cuts = [TimeRange(start: 2, end: 4)]
        value.narrations = [NarrationSegment(
            start: 0,
            end: 1,
            script: "Long narration",
            voiceID: "voice",
            audioFile: "media/narration/\(UUID().uuidString).mp3",
            audioDuration: 3
        )]
        let heldFrame = Annotation(kind: .frame, start: 0.9, end: 1)
        let afterCut = Annotation(kind: .text, start: 4, end: 5, text: "After cut")
        value.annotations = [heldFrame, afterCut]
        try value.validate()

        let holdSource = try XCTUnwrap(value.sourceTime(forOutput: 2))
        XCTAssertEqual(holdSource, 29.0 / 30, accuracy: 1e-9)
        XCTAssertTrue(heldFrame.isVisible(atSource: holdSource))
        XCTAssertFalse(heldFrame.isVisible(atSource: try XCTUnwrap(value.sourceTime(forOutput: 3))))

        let shiftedSource = try XCTUnwrap(value.sourceTime(forOutput: 4))
        XCTAssertEqual(shiftedSource, 4, accuracy: 1e-9)
        XCTAssertTrue(afterCut.isVisible(atSource: shiftedSource))
        XCTAssertFalse(afterCut.isVisible(atSource: try XCTUnwrap(value.sourceTime(forOutput: 5))))
    }
}
