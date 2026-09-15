import XCTest
@testable import AnalysisCore

final class AnalysisTests: XCTestCase {
    func fixture(protected: [Span] = []) -> Manifest {
        Manifest(source: "test.mov", duration: 10, audioStatus: "absent",
                 frames: [Frame(id: "a", time: 1, file: "a.jpg", change: 0), Frame(id: "b", time: 5, file: "b.jpg", change: 0), Frame(id: "c", time: 9, file: "c.jpg", change: 1)],
                 candidates: [Span(1, 5)], protected: protected, selectedFrameIDs: ["a", "b", "c"])
    }
    func cut(_ start: Double = 1, _ end: Double = 5, evidence: [String] = ["a", "b"]) -> Suggestion {
        Suggestion(start: start, end: end, decision: "cut", reason: "Observed wait", evidence: evidence, confidence: 0.8)
    }
    func check(_ suggestions: [Suggestion], _ manifest: Manifest? = nil) throws -> [CheckedSuggestion] {
        try validate(Analysis(summary: "Test", suggestions: suggestions), against: manifest ?? fixture())
    }
    func testBoundedEvidenceCanReachReview() throws { XCTAssertTrue(try check([cut()])[0].eligibleForReview) }
    func testSpeechProtectsStaticPicture() throws {
        let result = try check([cut()], fixture(protected: [Span(2, 4)]))[0]
        XCTAssertFalse(result.eligibleForReview)
        XCTAssertTrue(result.issues.contains("Overlaps protected audio or action"))
    }
    func testBothOverlappingCutsRejectedInsteadOfApplyingFirst() throws {
        XCTAssertTrue(try check([cut(1, 4), cut(3, 5)]).allSatisfy { !$0.eligibleForReview })
    }
    func testUnknownAndUnsentEvidenceRejected() throws {
        XCTAssertFalse(try check([cut(evidence: ["unknown"])])[0].eligibleForReview)
        var m = fixture(); m.selectedFrameIDs = ["a", "c"]
        XCTAssertFalse(try check([cut()], m)[0].eligibleForReview)
    }
    func testSparseFramesCannotClaimAnUnbracketedBoundary() throws {
        XCTAssertFalse(try check([cut(evidence: ["a"])])[0].eligibleForReview)
    }
    func testHallucinatedRangeIsRejected() throws {
        for span in [Span(-1, 5), Span(5, 1), Span(1, 11), Span(1, 1), Span(.nan, 5), Span(6, 9)] {
            XCTAssertFalse(try check([cut(span.start, span.end)])[0].eligibleForReview)
        }
    }
    func testUncertaintyNeverBecomesCut() throws {
        var s = cut(); s.decision = "uncertain"
        XCTAssertFalse(try check([s])[0].eligibleForReview)
    }
    func testUnreviewedAudioMustFailClosed() throws {
        var m = fixture(); m.audioStatus = "unreviewed"
        XCTAssertThrowsError(try m.validate())
        m.protected = [Span(0, 10)]
        XCTAssertFalse(try check([cut()], m)[0].eligibleForReview)
    }
    func testInvalidManifestsRejectedBeforeNetwork() throws {
        var m = fixture(); m.frames[1].id = "a"
        XCTAssertThrowsError(try m.validate())
        m = fixture(); m.frames[1].time = 0
        XCTAssertThrowsError(try m.validate())
        m = fixture(); m.selectedFrameIDs = ["a", "a"]
        XCTAssertThrowsError(try m.validate())
        m = fixture(); m.duration = 601
        XCTAssertThrowsError(try m.validate())
    }
    func testStaticRunStopsBeforeVisibleChange() {
        let frames = (0..<8).map { Frame(id: "\($0)", time: Double($0), file: "\($0).jpg", change: $0 == 4 ? 0.2 : 0) }
        XCTAssertEqual(idleCandidates(frames: frames), [Span(0, 3), Span(4, 7)])
    }
    func testMalformedOutputCannotDecode() {
        XCTAssertThrowsError(try JSONDecoder().decode(Analysis.self, from: Data("{\"suggestions\":\"remove everything\"}".utf8)))
    }
    func testProtectedBoundaryTouchDoesNotRemoveProtectedTime() throws {
        XCTAssertTrue(try check([cut()], fixture(protected: [Span(5, 8)]))[0].eligibleForReview)
    }
}
