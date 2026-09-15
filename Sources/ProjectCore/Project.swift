import Foundation

public struct TimeRange: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var start: Double
    public var end: Double
    public var duration: Double { end - start }
    public init(start: Double, end: Double, id: UUID = UUID()) { self.start = start; self.end = end; self.id = id }
}

public struct Zoom: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var start: Double
    public var end: Double
    public var scale: Double
    public var x: Double
    public var y: Double
    public var duration: Double { end - start }
    public init(start: Double = 0, end: Double = 2, scale: Double = 1.6, x: Double = 0.5, y: Double = 0.5, id: UUID = UUID()) {
        self.id = id; self.start = start; self.end = end; self.scale = scale; self.x = x; self.y = y
    }
    public func validate(duration: Double) throws {
        guard [start, end, scale, x, y].allSatisfy(\.isFinite),
              start >= 0, end > start, end <= duration,
              (1...3).contains(scale), (0...1).contains(x), (0...1).contains(y) else {
            throw ProjectError("Zoom times must be inside the recording, with a scale from 1× to 3× and a focus inside the frame.")
        }
    }
    /// Coordinates are normalized from the top-left; times are in original source seconds.
    public func amount(at sourceTime: Double) -> Double {
        guard scale > 1, end > start, sourceTime >= start, sourceTime <= end else { return 1 }
        let ramp = min(0.4, (end - start) / 2)
        let progress = min(1, min((sourceTime - start) / ramp, (end - sourceTime) / ramp))
        let eased = progress * progress * (3 - 2 * progress)
        return 1 + (scale - 1) * eased
    }
}

public struct CursorSample: Codable, Equatable, Sendable {
    public var time: Double
    public var x: Double
    public var y: Double
    public var visible: Bool
    public var pressed: Bool
    public init(time: Double, x: Double, y: Double, visible: Bool, pressed: Bool) {
        self.time = time; self.x = x; self.y = y; self.visible = visible; self.pressed = pressed
    }
}

public struct Project: Codable, Equatable, Sendable {
    public var version = 3
    public var title: String
    public var sourceFile = "media/source.mov"
    public var sourceDuration: Double
    public var sourceWidth: Int
    public var sourceHeight: Int
    public var cuts: [TimeRange] = []
    public var zooms: [Zoom] = []
    public var padding: Double = 0.06
    public var background: CanvasBackground = .midnight
    public var cursor: [CursorSample] = []
    public var cursorMode: CursorRecordingMode = .embedded
    public var cursorStyle: CursorStyle = .default
    public var narrations: [NarrationSegment] = []
    public var sourceAudioVolume: Double = 1
    public var narrationVolume: Double = 1
    public init(title: String, duration: Double, width: Int, height: Int) {
        self.title = title; sourceDuration = duration; sourceWidth = width; sourceHeight = height
    }

    private enum CodingKeys: String, CodingKey {
        case version, title, sourceFile, sourceDuration, sourceWidth, sourceHeight, cuts, zooms, padding, background, cursor
        case cursorMode, cursorStyle, narrations, sourceAudioVolume, narrationVolume
    }

    private enum LegacyKeys: String, CodingKey { case zoom }
    private struct LegacyZoom: Decodable {
        let start: Double, end: Double, scale: Double, x: Double, y: Double
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        let storedVersion = version
        title = try values.decode(String.self, forKey: .title)
        sourceFile = try values.decode(String.self, forKey: .sourceFile)
        sourceDuration = try values.decode(Double.self, forKey: .sourceDuration)
        sourceWidth = try values.decode(Int.self, forKey: .sourceWidth)
        sourceHeight = try values.decode(Int.self, forKey: .sourceHeight)
        cuts = try values.decode([TimeRange].self, forKey: .cuts)
        if version == 1 {
            let legacy = try decoder.container(keyedBy: LegacyKeys.self).decode(LegacyZoom.self, forKey: .zoom)
            let zoom = Zoom(start: legacy.start, end: legacy.end, scale: legacy.scale, x: legacy.x, y: legacy.y)
            try zoom.validate(duration: sourceDuration)
            zooms = zoom.scale > 1 ? [zoom] : []
            version = 2
        } else if version == 2 || version == 3 {
            zooms = try values.decode([Zoom].self, forKey: .zooms)
        } else {
            throw ProjectError("This project was created with an unsupported version of Takelet.")
        }
        padding = try values.decode(Double.self, forKey: .padding)
        cursor = try values.decode([CursorSample].self, forKey: .cursor)
        // Early version-1 documents predate background presets; retain their original appearance.
        background = try values.decodeIfPresent(CanvasBackground.self, forKey: .background) ?? .midnight
        if storedVersion == 3 {
            cursorMode = try values.decode(CursorRecordingMode.self, forKey: .cursorMode)
            cursorStyle = try values.decode(CursorStyle.self, forKey: .cursorStyle)
            narrations = try values.decode([NarrationSegment].self, forKey: .narrations)
            sourceAudioVolume = try values.decode(Double.self, forKey: .sourceAudioVolume)
            narrationVolume = try values.decode(Double.self, forKey: .narrationVolume)
        }
        version = 3
    }

    public func validate() throws {
        guard version == 3, sourceDuration.isFinite, sourceDuration > 0, sourceDuration <= 601,
              sourceWidth > 0, sourceHeight > 0, sourceWidth <= 16384, sourceHeight <= 16384,
              sourceFile == "media/source.mov", padding.isFinite, (0...0.2).contains(padding) else {
            throw ProjectError("Invalid project settings or unsupported project version.")
        }
        try cursorStyle.validate()
        guard sourceAudioVolume.isFinite, narrationVolume.isFinite,
              (0...1).contains(sourceAudioVolume), (0...1).contains(narrationVolume) else {
            throw ProjectError("Audio volume must be between 0% and 100%.")
        }
        guard zooms.count <= 512, Set(zooms.map(\.id)).count == zooms.count else {
            throw ProjectError("A project supports up to 512 zooms with unique IDs.")
        }
        var zoomEnd = 0.0
        for zoom in zooms.sorted(by: { $0.start < $1.start }) {
            try zoom.validate(duration: sourceDuration)
            guard zoom.start >= zoomEnd else { throw ProjectError("Zoom intervals must not overlap. Adjust their start or end times.") }
            zoomEnd = zoom.end
        }
        var previousEnd = 0.0
        guard Set(cuts.map(\.id)).count == cuts.count else { throw ProjectError("Duplicate edit IDs.") }
        for cut in cuts.sorted(by: { $0.start < $1.start }) {
            guard cut.start.isFinite, cut.end.isFinite, cut.start >= previousEnd, cut.end > cut.start, cut.end <= sourceDuration else {
                throw ProjectError("Cuts must be inside the recording and must not overlap.")
            }
            previousEnd = cut.end
        }
        let timeline = try makeTimeline()
        guard timeline.outputDuration > 0.05 else { throw ProjectError("Keep at least one frame of the recording.") }
        guard cursor.count <= 40_000, cursor.allSatisfy({
            $0.time.isFinite && $0.time >= 0 && $0.time <= sourceDuration && $0.x.isFinite && $0.y.isFinite
        }), zip(cursor, cursor.dropFirst()).allSatisfy({ $0.time <= $1.time }) else {
            throw ProjectError("Invalid cursor timestamps.")
        }
    }

    public var retainedRanges: [TimeRange] {
        var result: [TimeRange] = []
        var position = 0.0
        for cut in cuts.sorted(by: { $0.start < $1.start }) {
            if cut.start > position { result.append(TimeRange(start: position, end: cut.start)) }
            position = cut.end
        }
        if position < sourceDuration { result.append(TimeRange(start: position, end: sourceDuration)) }
        return result
    }
    public var retainedDuration: Double { sourceDuration - cuts.reduce(0) { $0 + $1.duration } }
    public var outputDuration: Double { (try? makeTimeline().outputDuration) ?? retainedDuration }
    public func makeTimeline() throws -> NarrationTimeline {
        try NarrationTimeline.build(sourceDuration: sourceDuration, cuts: cuts, narrations: narrations)
    }

    public func zoom(atSource time: Double) -> Zoom? {
        zooms.first { time >= $0.start && time < $0.end }
    }

    public func sourceTime(forOutput time: Double) -> Double? {
        if !narrations.isEmpty { return try? makeTimeline().sourceTime(forOutput: time) }
        guard time.isFinite, time >= 0, time < outputDuration else { return nil }
        var offset = 0.0
        for range in retainedRanges {
            if time < offset + range.duration { return range.start + time - offset }
            offset += range.duration
        }
        return nil
    }

    public func outputTime(forSource time: Double) -> Double? {
        if !narrations.isEmpty { return try? makeTimeline().outputTime(forSource: time) }
        guard time.isFinite, time >= 0, time < sourceDuration else { return nil }
        var offset = 0.0
        for range in retainedRanges {
            if time >= range.start && time < range.end { return offset + time - range.start }
            offset += range.duration
        }
        return nil
    }
}

public struct ProjectError: Error, LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public enum ProjectStore {
    public static func sourceURL(in directory: URL) throws -> URL {
        let root = directory.resolvingSymlinksInPath()
        let source = root.appendingPathComponent("media/source.mov").resolvingSymlinksInPath()
        guard source.path.hasPrefix(root.path + "/"), FileManager.default.fileExists(atPath: source.path) else {
            throw ProjectError("The project's source recording is missing or outside the project folder.")
        }
        return source
    }
    public static func load(from directory: URL) throws -> Project {
        let data = try Data(contentsOf: directory.appendingPathComponent("project.json"))
        guard data.count < 12 * 1024 * 1024 else { throw ProjectError("Project metadata is too large.") }
        let project = try JSONDecoder().decode(Project.self, from: data)
        try project.validate()
        _ = try sourceURL(in: directory)
        _ = try assetURLs(for: project, in: directory)
        return project
    }
    public static func save(_ project: Project, to directory: URL, assets: [String: URL] = [:]) throws {
        try project.validate()
        _ = try sourceURL(in: directory)
        try copyAssets(for: project, from: assets, to: directory)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(project).write(to: directory.appendingPathComponent("project.json"), options: .atomic)
    }
    public static func create(_ project: Project, source: URL, at directory: URL, assets: [String: URL] = [:]) throws {
        try project.validate()
        guard !FileManager.default.fileExists(atPath: directory.path) else { throw ProjectError("Choose a new project filename.") }
        let temp = directory.deletingLastPathComponent().appendingPathComponent(".takelet-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temp) }
        try FileManager.default.createDirectory(at: temp.appendingPathComponent("media"), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: temp.appendingPathComponent("media/source.mov"))
        try save(project, to: temp, assets: assets)
        try FileManager.default.moveItem(at: temp, to: directory)
    }
}
