import Foundation
import XCTest
@testable import ProjectCore

final class NarrationTests: XCTestCase {
    private let audioID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

    private func generated(
        start: Double,
        end: Double,
        audioDuration: Double,
        id: UUID = UUID()
    ) -> NarrationSegment {
        NarrationSegment(
            start: start,
            end: end,
            script: "Explain this step.",
            voiceID: "voice-1",
            voiceName: "Narrator",
            audioFile: "media/narration/\(audioID.uuidString).mp3",
            audioDuration: audioDuration,
            id: id
        )
    }

    func testSegmentPersistsEditableAndGeneratedState() throws {
        XCTAssertEqual(NarrationSegment(start: 0, end: 1).modelID, "eleven_multilingual_v2")
        XCTAssertNil(NarrationSegment(start: 0, end: 1).languageCode)

        var segment = generated(start: 1, end: 3, audioDuration: 2.5)
        segment.languageCode = "ru"
        let data = try JSONEncoder().encode(segment)
        XCTAssertEqual(try JSONDecoder().decode(NarrationSegment.self, from: data), segment)
    }

    func testCutAndHoldMapsSourceAndOutputWithHalfOpenBoundaries() throws {
        let narration = generated(start: 1, end: 6, audioDuration: 5)
        let timeline = try NarrationTimeline.build(
            sourceDuration: 10,
            cuts: [TimeRange(start: 2, end: 4)],
            narrations: [narration]
        )

        XCTAssertEqual(timeline.outputDuration, 10, accuracy: 1e-9)
        XCTAssertEqual(timeline.sourceTime(forOutput: 1.5), 1.5)
        XCTAssertEqual(timeline.sourceTime(forOutput: 2), 4)
        XCTAssertEqual(timeline.sourceTime(forOutput: 3), 5)
        XCTAssertEqual(try XCTUnwrap(timeline.sourceTime(forOutput: 4.5)), 179.0 / 30, accuracy: 1e-9)
        XCTAssertEqual(timeline.sourceTime(forOutput: 6), 6)
        XCTAssertNil(timeline.sourceTime(forOutput: 10))
        XCTAssertNil(timeline.outputTime(forSource: 10))

        XCTAssertNil(timeline.outputTime(forSource: 2))
        XCTAssertNil(timeline.outputTime(forSource: 3.999))
        XCTAssertEqual(timeline.outputTime(forSource: 4), 2)
        XCTAssertEqual(try XCTUnwrap(timeline.outputTime(forSource: 179.0 / 30)), 119.0 / 30, accuracy: 1e-9)
        XCTAssertEqual(timeline.outputTime(forSource: 6), 6)

        let placement = try XCTUnwrap(timeline.narrations.first)
        XCTAssertEqual(placement.outputStart, 1)
        XCTAssertEqual(placement.retainedSourceDuration, 3)
        XCTAssertEqual(placement.outputDuration, 5)
        XCTAssertEqual(try XCTUnwrap(placement.heldSourceFrameTime), 179.0 / 30, accuracy: 1e-9)
    }

    func testLongNarrationRetimesDownstreamFootageAndKeepsHoldSilent() throws {
        let downstream = NarrationSegment(start: 5, end: 6, script: "Next step")
        let timeline = try NarrationTimeline.build(
            sourceDuration: 8,
            cuts: [],
            narrations: [generated(start: 1, end: 3, audioDuration: 4), downstream]
        )

        XCTAssertEqual(timeline.outputDuration, 10)
        XCTAssertEqual(timeline.outputTime(forSource: 5), 7)
        XCTAssertEqual(timeline.sourceTime(forOutput: 5.5), 3.5)
        XCTAssertEqual(timeline.narrations[1].outputStart, 7)
        let hold = try XCTUnwrap(timeline.spans.first(where: \.isHold))
        XCTAssertEqual(hold.outputInterval, TimelineInterval(start: 3, end: 5))
        XCTAssertEqual(hold.sourceInterval.duration, 1.0 / 30, accuracy: 1e-12)
        XCTAssertTrue(timeline.spans.filter { $0.hold == nil }.allSatisfy {
            abs($0.sourceInterval.duration - $0.outputInterval.duration) < 1e-12
        })
    }

    func testShortAudioAndDraftDoNotChangeCutOnlyTimeline() throws {
        let short = generated(start: 1, end: 5, audioDuration: 0.5)
        let draft = NarrationSegment(start: 6, end: 7, script: "Draft")
        let timeline = try NarrationTimeline.build(
            sourceDuration: 10,
            cuts: [TimeRange(start: 2, end: 3)],
            narrations: [short, draft]
        )

        XCTAssertEqual(timeline.outputDuration, 9)
        XCTAssertFalse(timeline.spans.contains(where: \.isHold))
        XCTAssertEqual(timeline.narrations[0].outputDuration, 3)
        XCTAssertEqual(timeline.narrations[1].outputDuration, 1)
        XCTAssertEqual(timeline.outputTime(forSource: 7), 6)
    }

    func testDraftMayBeFullyCutButGeneratedNarrationMayNot() throws {
        let cut = TimeRange(start: 1, end: 3)
        let draft = NarrationSegment(start: 1.5, end: 2, script: "Still editable")
        let timeline = try NarrationTimeline.build(sourceDuration: 5, cuts: [cut], narrations: [draft])
        XCTAssertEqual(timeline.narrations[0].outputStart, 1)
        XCTAssertEqual(timeline.narrations[0].outputDuration, 0)

        XCTAssertThrowsError(try NarrationTimeline.build(
            sourceDuration: 5,
            cuts: [cut],
            narrations: [generated(start: 1.5, end: 2, audioDuration: 1)]
        ))
    }

    func testGeneratedNarrationRequiresCompleteAlignedFrame() {
        XCTAssertThrowsError(try NarrationTimeline.build(
            sourceDuration: 2,
            cuts: [TimeRange(start: 0, end: 0.99)],
            narrations: [generated(start: 0, end: 1, audioDuration: 1)]
        ))
    }

    func testNarrationsCannotOverlapAndIDsMustBeUnique() {
        let id = UUID()
        XCTAssertThrowsError(try NarrationTimeline.build(
            sourceDuration: 5,
            cuts: [],
            narrations: [
                NarrationSegment(start: 0, end: 2, id: id),
                NarrationSegment(start: 1, end: 3)
            ]
        ))
        XCTAssertThrowsError(try NarrationTimeline.build(
            sourceDuration: 5,
            cuts: [],
            narrations: [
                NarrationSegment(start: 0, end: 1, id: id),
                NarrationSegment(start: 2, end: 3, id: id)
            ]
        ))
    }

    func testRejectsPathEscapeDuplicateAudioAndUnpairedMetadata() {
        var escaped = generated(start: 0, end: 1, audioDuration: 1)
        escaped.audioFile = "media/narration/../secret.mp3"
        XCTAssertThrowsError(try NarrationTimeline.build(sourceDuration: 5, cuts: [], narrations: [escaped]))

        let first = generated(start: 0, end: 1, audioDuration: 1)
        let second = generated(start: 2, end: 3, audioDuration: 1)
        XCTAssertThrowsError(try NarrationTimeline.build(sourceDuration: 5, cuts: [], narrations: [first, second]))

        var unpaired = NarrationSegment(start: 0, end: 1)
        unpaired.audioDuration = 1
        XCTAssertThrowsError(try NarrationTimeline.build(sourceDuration: 5, cuts: [], narrations: [unpaired]))
    }

    func testRejectsNonfiniteAndBoundedValues() {
        for duration in [Double.nan, .infinity, 0, 602] {
            XCTAssertThrowsError(try NarrationTimeline.build(sourceDuration: duration, cuts: [], narrations: []))
        }

        var invalidTime = NarrationSegment(start: .nan, end: 1)
        XCTAssertThrowsError(try NarrationTimeline.build(sourceDuration: 5, cuts: [], narrations: [invalidTime]))
        invalidTime = generated(start: 0, end: 1, audioDuration: .infinity)
        XCTAssertThrowsError(try NarrationTimeline.build(sourceDuration: 5, cuts: [], narrations: [invalidTime]))

        let tooLong = NarrationSegment(
            start: 0,
            end: 1,
            script: String(repeating: "a", count: NarrationSegment.maximumScriptLength + 1)
        )
        XCTAssertThrowsError(try NarrationTimeline.build(sourceDuration: 5, cuts: [], narrations: [tooLong]))

        let tooMany = (0...NarrationSegment.maximumCount).map { index in
            NarrationSegment(start: Double(index) / 100, end: Double(index + 1) / 100)
        }
        XCTAssertThrowsError(try NarrationTimeline.build(sourceDuration: 5, cuts: [], narrations: tooMany))
    }

    func testRejectsExcessiveTotalOutputDuration() {
        let narrations = (0..<3).map { index -> NarrationSegment in
            let assetID = UUID()
            return NarrationSegment(
                start: Double(index),
                end: Double(index + 1),
                script: "Long narration",
                voiceID: "voice-1",
                voiceName: "Narrator",
                audioFile: "media/narration/\(assetID.uuidString).mp3",
                audioDuration: NarrationSegment.maximumAudioDuration
            )
        }
        XCTAssertThrowsError(try NarrationTimeline.build(sourceDuration: 3, cuts: [], narrations: narrations))
    }

    func testCutsOnlyMappingMatchesLegacyBehavior() throws {
        let timeline = try NarrationTimeline.build(
            sourceDuration: 10,
            cuts: [TimeRange(start: 1, end: 2), TimeRange(start: 4, end: 6)],
            narrations: []
        )
        XCTAssertEqual(timeline.outputDuration, 7)
        XCTAssertEqual(timeline.sourceTime(forOutput: 1), 2)
        XCTAssertEqual(timeline.sourceTime(forOutput: 3), 6)
        XCTAssertEqual(timeline.sourceTime(forOutput: 6.5), 9.5)
        XCTAssertNil(timeline.outputTime(forSource: 1))
        XCTAssertNil(timeline.outputTime(forSource: 5))
        XCTAssertEqual(timeline.outputTime(forSource: 6), 3)
    }
}
