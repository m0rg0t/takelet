import Foundation

/// An editable voiceover interval expressed in original source time.
public struct NarrationSegment: Codable, Equatable, Sendable, Identifiable {
    public static let defaultModelID = "eleven_multilingual_v2"
    public static let maximumCount = 128
    public static let maximumScriptLength = 10_000
    public static let maximumAudioDuration = 1_800.0

    public var id: UUID
    public var start: Double
    public var end: Double
    public var script: String
    public var voiceID: String
    public var voiceName: String
    public var modelID: String
    /// `nil` asks the speech provider to detect the language automatically.
    public var languageCode: String?
    /// A project-relative immutable asset, such as `media/narration/<UUID>.mp3`.
    public var audioFile: String?
    /// The measured duration of `audioFile`, in seconds.
    public var audioDuration: Double?

    public var duration: Double { end - start }

    public init(
        start: Double,
        end: Double,
        script: String = "",
        voiceID: String = "",
        voiceName: String = "",
        modelID: String = NarrationSegment.defaultModelID,
        languageCode: String? = nil,
        audioFile: String? = nil,
        audioDuration: Double? = nil,
        id: UUID = UUID()
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.script = script
        self.voiceID = voiceID
        self.voiceName = voiceName
        self.modelID = modelID
        self.languageCode = languageCode
        self.audioFile = audioFile
        self.audioDuration = audioDuration
    }
}

/// A half-open interval used by the derived narration timeline.
public struct TimelineInterval: Codable, Equatable, Sendable {
    public var start: Double
    public var end: Double
    public var duration: Double { end - start }

    public init(start: Double, end: Double) {
        self.start = start
        self.end = end
    }

    public func contains(_ time: Double) -> Bool {
        time >= start && time < end
    }
}

/// Metadata needed to render a silent freeze-frame extension.
public struct NarrationHold: Codable, Equatable, Sendable {
    public var narrationID: UUID
    public var sourceFrameTime: Double
    public var sourceFrameInterval: TimelineInterval
    public var duration: Double

    public init(
        narrationID: UUID,
        sourceFrameTime: Double,
        sourceFrameInterval: TimelineInterval,
        duration: Double
    ) {
        self.narrationID = narrationID
        self.sourceFrameTime = sourceFrameTime
        self.sourceFrameInterval = sourceFrameInterval
        self.duration = duration
    }
}

/// A contiguous piece of output. Moving spans retain source audio; hold spans do not.
public struct NarrationTimelineSpan: Codable, Equatable, Sendable {
    public var sourceInterval: TimelineInterval
    public var outputInterval: TimelineInterval
    public var hold: NarrationHold?

    public var isHold: Bool { hold != nil }

    public init(
        sourceInterval: TimelineInterval,
        outputInterval: TimelineInterval,
        hold: NarrationHold? = nil
    ) {
        self.sourceInterval = sourceInterval
        self.outputInterval = outputInterval
        self.hold = hold
    }
}

/// The derived output position occupied by one editable narration segment.
public struct NarrationPlacement: Codable, Equatable, Sendable, Identifiable {
    public var narrationID: UUID
    public var outputStart: Double
    /// Moving retained footage plus any hold. The voice asset's duration remains on the segment.
    public var outputDuration: Double
    public var retainedSourceDuration: Double
    public var heldSourceFrameTime: Double?

    public var id: UUID { narrationID }

    public init(
        narrationID: UUID,
        outputStart: Double,
        outputDuration: Double,
        retainedSourceDuration: Double,
        heldSourceFrameTime: Double?
    ) {
        self.narrationID = narrationID
        self.outputStart = outputStart
        self.outputDuration = outputDuration
        self.retainedSourceDuration = retainedSourceDuration
        self.heldSourceFrameTime = heldSourceFrameTime
    }
}

/// A deterministic edit timeline derived from source-time cuts and narrations.
public struct NarrationTimeline: Codable, Equatable, Sendable {
    public static let maximumOutputDuration = 3_600.0

    public var spans: [NarrationTimelineSpan]
    public var narrations: [NarrationPlacement]
    public var outputDuration: Double

    public init(
        spans: [NarrationTimelineSpan],
        narrations: [NarrationPlacement],
        outputDuration: Double
    ) {
        self.spans = spans
        self.narrations = narrations
        self.outputDuration = outputDuration
    }

    /// Builds a timeline without reading media or project state.
    ///
    /// Hold durations are exact audio excesses and are not rounded to frames. The referenced
    /// source frame is a complete nominal frame aligned to `frameRate` and contained in the
    /// segment after cuts. A renderer should insert/extend video for a hold without source audio.
    public static func build(
        sourceDuration: Double,
        cuts: [TimeRange],
        narrations: [NarrationSegment],
        frameRate: Double = 30
    ) throws -> NarrationTimeline {
        guard sourceDuration.isFinite, sourceDuration > 0, sourceDuration <= 601 else {
            throw ProjectError("Narration timing requires a recording between 0 and 601 seconds.")
        }
        guard frameRate.isFinite, frameRate >= 1, frameRate <= 240 else {
            throw ProjectError("Narration frame rate must be between 1 and 240 fps.")
        }

        let sortedCuts = cuts.sorted { lhs, rhs in
            lhs.start == rhs.start ? lhs.end < rhs.end : lhs.start < rhs.start
        }
        guard Set(cuts.map(\.id)).count == cuts.count else {
            throw ProjectError("Cuts must have unique IDs.")
        }
        var previousCutEnd = 0.0
        for cut in sortedCuts {
            guard cut.start.isFinite, cut.end.isFinite,
                  cut.start >= previousCutEnd, cut.end > cut.start, cut.end <= sourceDuration else {
                throw ProjectError("Cuts must be inside the recording and must not overlap.")
            }
            previousCutEnd = cut.end
        }

        guard narrations.count <= NarrationSegment.maximumCount,
              Set(narrations.map(\.id)).count == narrations.count else {
            throw ProjectError("A project supports up to 128 narration segments with unique IDs.")
        }

        let sortedNarrations = narrations.sorted { lhs, rhs in
            lhs.start == rhs.start ? lhs.end < rhs.end : lhs.start < rhs.start
        }
        var previousNarrationEnd = 0.0
        var audioPaths = Set<String>()
        for narration in sortedNarrations {
            try validate(narration, sourceDuration: sourceDuration)
            guard narration.start >= previousNarrationEnd else {
                throw ProjectError("Narration intervals must not overlap.")
            }
            previousNarrationEnd = narration.end
            if let audioFile = narration.audioFile, !audioPaths.insert(audioFile).inserted {
                throw ProjectError("Narration audio files must be unique.")
            }
        }

        let retained = retainedIntervals(sourceDuration: sourceDuration, cuts: sortedCuts)
        let frameDuration = 1 / frameRate
        var derivations: [Derivation] = []
        var holds: [PendingHold] = []

        for narration in sortedNarrations {
            let pieces = retained.compactMap { intersection($0, TimelineInterval(start: narration.start, end: narration.end)) }
            let retainedDuration = pieces.reduce(0) { $0 + $1.duration }
            let hasAudio = narration.audioFile != nil
            var hold: PendingHold?

            if hasAudio {
                guard let lastFrame = pieces.reversed().compactMap({ completeLastFrame(in: $0, frameDuration: frameDuration) }).first else {
                    throw ProjectError("A generated narration must retain at least one complete source frame after cuts.")
                }
                let excess = max(0, narration.audioDuration! - retainedDuration)
                if excess > 0 {
                    let pending = PendingHold(
                        narrationID: narration.id,
                        insertionSourceTime: pieces.last!.end,
                        sourceFrameInterval: lastFrame,
                        duration: excess
                    )
                    holds.append(pending)
                    hold = pending
                }
            }

            derivations.append(Derivation(
                segment: narration,
                pieces: pieces,
                retainedDuration: retainedDuration,
                hold: hold
            ))
        }

        holds.sort { lhs, rhs in
            lhs.insertionSourceTime == rhs.insertionSourceTime
                ? lhs.narrationID.uuidString < rhs.narrationID.uuidString
                : lhs.insertionSourceTime < rhs.insertionSourceTime
        }
        let spans = makeSpans(retained: retained, holds: holds)
        let outputDuration = spans.last?.outputInterval.end ?? 0
        guard outputDuration <= maximumOutputDuration else {
            throw ProjectError("Narration may extend the finished video to at most one hour.")
        }
        let shell = NarrationTimeline(spans: spans, narrations: [], outputDuration: outputDuration)

        let placements = derivations.map { derivation in
            let start: Double
            if let firstPiece = derivation.pieces.first {
                start = shell.outputTime(forSource: firstPiece.start)!
            } else {
                start = outputBoundary(
                    forSource: derivation.segment.start,
                    retained: retained,
                    holds: holds
                )
            }
            let holdDuration = derivation.hold?.duration ?? 0
            return NarrationPlacement(
                narrationID: derivation.segment.id,
                outputStart: start,
                outputDuration: derivation.retainedDuration + holdDuration,
                retainedSourceDuration: derivation.retainedDuration,
                heldSourceFrameTime: derivation.hold?.sourceFrameInterval.start
            )
        }

        return NarrationTimeline(spans: spans, narrations: placements, outputDuration: outputDuration)
    }

    /// Maps output to source. Every time inside a hold maps to its frozen source frame.
    public func sourceTime(forOutput time: Double) -> Double? {
        guard time.isFinite, time >= 0, time < outputDuration else { return nil }
        guard let span = spans.first(where: { $0.outputInterval.contains(time) }) else { return nil }
        if let hold = span.hold { return hold.sourceFrameTime }
        return span.sourceInterval.start + time - span.outputInterval.start
    }

    /// Maps retained source to its moving-footage occurrence, never to a hold occurrence.
    public func outputTime(forSource time: Double) -> Double? {
        guard time.isFinite, time >= 0 else { return nil }
        guard let span = spans.first(where: { $0.hold == nil && $0.sourceInterval.contains(time) }) else { return nil }
        return span.outputInterval.start + time - span.sourceInterval.start
    }
}

private extension NarrationTimeline {
    struct PendingHold {
        var narrationID: UUID
        var insertionSourceTime: Double
        var sourceFrameInterval: TimelineInterval
        var duration: Double
    }

    struct Derivation {
        var segment: NarrationSegment
        var pieces: [TimelineInterval]
        var retainedDuration: Double
        var hold: PendingHold?
    }

    static func validate(_ narration: NarrationSegment, sourceDuration: Double) throws {
        guard narration.start.isFinite, narration.end.isFinite,
              narration.start >= 0, narration.end > narration.start, narration.end <= sourceDuration else {
            throw ProjectError("Narration intervals must be inside the recording.")
        }
        guard narration.script.count <= NarrationSegment.maximumScriptLength,
              narration.voiceID.count <= 256,
              narration.voiceName.count <= 256,
              !narration.modelID.isEmpty, narration.modelID.count <= 128,
              (narration.languageCode?.count ?? 0) <= 32 else {
            throw ProjectError("Narration text or voice metadata is too large or invalid.")
        }
        guard (narration.audioFile == nil) == (narration.audioDuration == nil) else {
            throw ProjectError("Narration audio path and measured duration must be stored together.")
        }
        if let audioDuration = narration.audioDuration {
            guard audioDuration.isFinite, audioDuration > 0,
                  audioDuration <= NarrationSegment.maximumAudioDuration,
                  !narration.script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !narration.voiceID.isEmpty else {
                throw ProjectError("Generated narration requires text, a voice, and a valid measured audio duration.")
            }
        }
        if let audioFile = narration.audioFile {
            let nsPath = audioFile as NSString
            let components = nsPath.pathComponents
            let filename = nsPath.lastPathComponent
            let stem = (filename as NSString).deletingPathExtension
            guard components.count == 3,
                  components[0] == "media", components[1] == "narration",
                  audioFile == components.joined(separator: "/"),
                  (filename as NSString).pathExtension == "mp3",
                  UUID(uuidString: stem) != nil else {
                throw ProjectError("Narration audio must use media/narration/<UUID>.mp3 inside the project.")
            }
        }
    }

    static func retainedIntervals(sourceDuration: Double, cuts: [TimeRange]) -> [TimelineInterval] {
        var result: [TimelineInterval] = []
        var position = 0.0
        for cut in cuts {
            if cut.start > position {
                result.append(TimelineInterval(start: position, end: cut.start))
            }
            position = cut.end
        }
        if position < sourceDuration {
            result.append(TimelineInterval(start: position, end: sourceDuration))
        }
        return result
    }

    static func intersection(_ lhs: TimelineInterval, _ rhs: TimelineInterval) -> TimelineInterval? {
        let start = max(lhs.start, rhs.start)
        let end = min(lhs.end, rhs.end)
        return end > start ? TimelineInterval(start: start, end: end) : nil
    }

    static func completeLastFrame(in interval: TimelineInterval, frameDuration: Double) -> TimelineInterval? {
        let epsilon = frameDuration * 1e-9
        let frameIndex = floor((interval.end - frameDuration + epsilon) / frameDuration)
        let start = max(0, frameIndex * frameDuration)
        let end = start + frameDuration
        guard start + epsilon >= interval.start, end <= interval.end + epsilon else { return nil }
        return TimelineInterval(start: start, end: end)
    }

    static func makeSpans(
        retained: [TimelineInterval],
        holds: [PendingHold]
    ) -> [NarrationTimelineSpan] {
        var spans: [NarrationTimelineSpan] = []
        var output = 0.0
        var holdIndex = 0

        for retainedInterval in retained {
            var source = retainedInterval.start
            while holdIndex < holds.count,
                  holds[holdIndex].insertionSourceTime <= retainedInterval.end {
                let pending = holds[holdIndex]
                guard pending.insertionSourceTime >= retainedInterval.start else {
                    holdIndex += 1
                    continue
                }
                if pending.insertionSourceTime > source {
                    let moving = TimelineInterval(start: source, end: pending.insertionSourceTime)
                    spans.append(NarrationTimelineSpan(
                        sourceInterval: moving,
                        outputInterval: TimelineInterval(start: output, end: output + moving.duration)
                    ))
                    output += moving.duration
                }
                let metadata = NarrationHold(
                    narrationID: pending.narrationID,
                    sourceFrameTime: pending.sourceFrameInterval.start,
                    sourceFrameInterval: pending.sourceFrameInterval,
                    duration: pending.duration
                )
                spans.append(NarrationTimelineSpan(
                    sourceInterval: pending.sourceFrameInterval,
                    outputInterval: TimelineInterval(start: output, end: output + pending.duration),
                    hold: metadata
                ))
                output += pending.duration
                source = pending.insertionSourceTime
                holdIndex += 1
            }
            if source < retainedInterval.end {
                let moving = TimelineInterval(start: source, end: retainedInterval.end)
                spans.append(NarrationTimelineSpan(
                    sourceInterval: moving,
                    outputInterval: TimelineInterval(start: output, end: output + moving.duration)
                ))
                output += moving.duration
            }
        }
        return spans
    }

    static func outputBoundary(
        forSource sourceTime: Double,
        retained: [TimelineInterval],
        holds: [PendingHold]
    ) -> Double {
        let retainedBefore = retained.reduce(0.0) { result, interval in
            result + max(0, min(sourceTime, interval.end) - interval.start)
        }
        let holdsBefore = holds.reduce(0.0) { result, hold in
            result + (hold.insertionSourceTime <= sourceTime ? hold.duration : 0)
        }
        return retainedBefore + holdsBefore
    }
}
