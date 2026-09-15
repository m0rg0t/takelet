import Foundation

public struct Span: Codable, Equatable, Sendable {
    public var start: Double
    public var end: Double
    public init(_ start: Double, _ end: Double) { self.start = start; self.end = end }
    public func overlaps(_ other: Span) -> Bool { start < other.end && other.start < end }
    public func isValid(duration: Double) -> Bool {
        start.isFinite && end.isFinite && start >= 0 && end > start && end <= duration
    }
}

public struct Frame: Codable, Sendable {
    public var id: String
    public var time: Double
    public var file: String
    public var change: Double
    public init(id: String, time: Double, file: String, change: Double) {
        self.id = id; self.time = time; self.file = file; self.change = change
    }
}

public struct Manifest: Codable, Sendable {
    public var version: Int
    public var source: String
    public var duration: Double
    public var audioStatus: String
    public var frames: [Frame]
    public var candidates: [Span]
    public var protected: [Span]
    public var selectedFrameIDs: [String]
    public init(source: String, duration: Double, audioStatus: String, frames: [Frame], candidates: [Span], protected: [Span], selectedFrameIDs: [String]) {
        version = 1; self.source = source; self.duration = duration; self.audioStatus = audioStatus
        self.frames = frames; self.candidates = candidates; self.protected = protected; self.selectedFrameIDs = selectedFrameIDs
    }

    public func validate() throws {
        guard version == 1, duration.isFinite, duration > 0, duration <= 600,
              ["absent", "unreviewed", "reviewed"].contains(audioStatus),
              !frames.isEmpty, frames.count <= 1201,
              !selectedFrameIDs.isEmpty, selectedFrameIDs.count <= 16 else {
            throw AnalysisError("Invalid or oversized manifest")
        }
        let ids = Set(frames.map(\.id))
        guard ids.count == frames.count,
              Set(selectedFrameIDs).count == selectedFrameIDs.count,
              Set(selectedFrameIDs).isSubset(of: ids),
              frames.allSatisfy({ $0.time.isFinite && $0.time >= 0 && $0.time < duration && $0.change.isFinite }),
              zip(frames, frames.dropFirst()).allSatisfy({ $0.time < $1.time }),
              (candidates + protected).allSatisfy({ $0.isValid(duration: duration) }) else {
            throw AnalysisError("Invalid timestamps or evidence IDs")
        }
        if audioStatus == "unreviewed", !protected.contains(where: { $0.start == 0 && $0.end == duration }) {
            throw AnalysisError("Unreviewed source audio must protect the complete recording")
        }
    }
}

public struct Suggestion: Codable, Sendable {
    public var start: Double
    public var end: Double
    public var decision: String
    public var reason: String
    public var evidence: [String]
    public var confidence: Double
    public init(start: Double, end: Double, decision: String, reason: String, evidence: [String], confidence: Double) {
        self.start = start; self.end = end; self.decision = decision; self.reason = reason
        self.evidence = evidence; self.confidence = confidence
    }
}

public struct Analysis: Codable, Sendable {
    public var summary: String
    public var suggestions: [Suggestion]
    public init(summary: String, suggestions: [Suggestion]) { self.summary = summary; self.suggestions = suggestions }
}

public struct CheckedSuggestion: Codable, Sendable {
    public var suggestion: Suggestion
    public var eligibleForReview: Bool
    public var issues: [String]
}

public struct AnalysisError: Error, CustomStringConvertible, Sendable {
    public var description: String
    public init(_ text: String) { description = text }
}

/// A cut can only reach review if it is bounded by local evidence and does not remove protected audio/actions.
/// Eligibility NEVER applies an edit. Local candidates remain heuristic, not a safety guarantee.
public func validate(_ analysis: Analysis, against manifest: Manifest) throws -> [CheckedSuggestion] {
    try manifest.validate()
    guard analysis.suggestions.count <= 32 else { throw AnalysisError("Too many model suggestions") }
    let evidence = Dictionary(uniqueKeysWithValues: manifest.frames.filter { manifest.selectedFrameIDs.contains($0.id) }.map { ($0.id, $0.time) })
    let cuts = analysis.suggestions.filter { $0.decision == "cut" }
    return analysis.suggestions.map { s in
        let span = Span(s.start, s.end)
        var issues: [String] = []
        if !span.isValid(duration: manifest.duration) { issues.append("Invalid source interval") }
        if !["cut", "keep", "uncertain"].contains(s.decision) { issues.append("Unknown decision") }
        if !s.confidence.isFinite || !(0...1).contains(s.confidence) { issues.append("Invalid confidence") }
        if s.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append("Missing reason") }
        if s.evidence.isEmpty || !s.evidence.allSatisfy({ evidence[$0] != nil }) { issues.append("Missing or unseen frame evidence") }
        if s.decision == "cut" {
            if !manifest.candidates.contains(where: { $0.start <= s.start && s.end <= $0.end }) { issues.append("Outside locally detected candidate") }
            if manifest.protected.contains(where: { $0.overlaps(span) }) { issues.append("Overlaps protected audio or action") }
            let times = s.evidence.compactMap { evidence[$0] }
            if !(times.contains(where: { $0 <= s.start }) && times.contains(where: { $0 >= s.end })) { issues.append("Evidence does not bracket the cut") }
            if cuts.filter({ Span($0.start, $0.end).overlaps(span) }).count > 1 { issues.append("Overlapping cut suggestions") }
            if s.end - s.start < 0.5 { issues.append("Cut too short for sampling precision") }
        }
        return CheckedSuggestion(suggestion: s, eligibleForReview: s.decision == "cut" && issues.isEmpty, issues: issues)
    }
}

/// Consecutive low-change samples suggest a possible pause. A small UI action can still be meaningful.
public func idleCandidates(frames: [Frame], threshold: Double = 0.003, minimum: Double = 2) -> [Span] {
    guard frames.count > 1 else { return [] }
    var result: [Span] = []
    var beginning: Double?
    for i in 1..<frames.count {
        if frames[i].change <= threshold {
            if beginning == nil { beginning = frames[i - 1].time }
        } else if let start = beginning {
            let end = frames[i - 1].time
            if end - start >= minimum { result.append(Span(start, end)) }
            beginning = nil
        }
    }
    if let start = beginning, let end = frames.last?.time, end - start >= minimum { result.append(Span(start, end)) }
    return result
}

public func makeAnalysisSchema() -> [String: Any] { [
    "type": "object", "additionalProperties": false,
    "required": ["summary", "suggestions"],
    "properties": [
        "summary": ["type": "string"],
        "suggestions": ["type": "array", "items": [
            "type": "object", "additionalProperties": false,
            "required": ["start", "end", "decision", "reason", "evidence", "confidence"],
            "properties": [
                "start": ["type": "number"], "end": ["type": "number"],
                "decision": ["type": "string", "enum": ["cut", "keep", "uncertain"]],
                "reason": ["type": "string"],
                "evidence": ["type": "array", "items": ["type": "string"]],
                "confidence": ["type": "number"]
            ]
        ]]
    ]
] }
