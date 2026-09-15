import Foundation

public struct TimeRange: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var start: Double
    public var end: Double
    public var duration: Double { end - start }
    public init(start: Double, end: Double, id: UUID = UUID()) { self.start = start; self.end = end; self.id = id }
}

public struct Zoom: Codable, Equatable, Sendable {
    public var start: Double = 0
    public var end: Double = 0
    public var scale: Double = 1
    public var x: Double = 0.5
    public var y: Double = 0.5
    public init() {}
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
    public var version = 1
    public var title: String
    public var sourceFile = "media/source.mov"
    public var sourceDuration: Double
    public var sourceWidth: Int
    public var sourceHeight: Int
    public var cuts: [TimeRange] = []
    public var zoom = Zoom()
    public var padding: Double = 0.06
    public var background: CanvasBackground = .midnight
    public var cursor: [CursorSample] = []
    public init(title: String, duration: Double, width: Int, height: Int) {
        self.title = title; sourceDuration = duration; sourceWidth = width; sourceHeight = height
        zoom.end = duration
    }

    private enum CodingKeys: String, CodingKey {
        case version, title, sourceFile, sourceDuration, sourceWidth, sourceHeight, cuts, zoom, padding, background, cursor
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        title = try values.decode(String.self, forKey: .title)
        sourceFile = try values.decode(String.self, forKey: .sourceFile)
        sourceDuration = try values.decode(Double.self, forKey: .sourceDuration)
        sourceWidth = try values.decode(Int.self, forKey: .sourceWidth)
        sourceHeight = try values.decode(Int.self, forKey: .sourceHeight)
        cuts = try values.decode([TimeRange].self, forKey: .cuts)
        zoom = try values.decode(Zoom.self, forKey: .zoom)
        padding = try values.decode(Double.self, forKey: .padding)
        cursor = try values.decode([CursorSample].self, forKey: .cursor)
        // Early version-1 documents predate background presets; retain their original appearance.
        background = try values.decodeIfPresent(CanvasBackground.self, forKey: .background) ?? .midnight
    }

    public func validate() throws {
        guard version == 1, sourceDuration.isFinite, sourceDuration > 0, sourceDuration <= 601,
              sourceWidth > 0, sourceHeight > 0, sourceWidth <= 16384, sourceHeight <= 16384,
              sourceFile == "media/source.mov", padding.isFinite, (0...0.2).contains(padding),
              [zoom.start, zoom.end, zoom.scale, zoom.x, zoom.y].allSatisfy(\.isFinite),
              zoom.start >= 0, zoom.end > zoom.start, zoom.end <= sourceDuration,
              (1...3).contains(zoom.scale), (0...1).contains(zoom.x), (0...1).contains(zoom.y) else {
            throw ProjectError("Invalid project settings or unsupported project version.")
        }
        var previousEnd = 0.0
        guard Set(cuts.map(\.id)).count == cuts.count else { throw ProjectError("Duplicate edit IDs.") }
        for cut in cuts.sorted(by: { $0.start < $1.start }) {
            guard cut.start.isFinite, cut.end.isFinite, cut.start >= previousEnd, cut.end > cut.start, cut.end <= sourceDuration else {
                throw ProjectError("Cuts must be inside the recording and must not overlap.")
            }
            previousEnd = cut.end
        }
        guard outputDuration > 0.05 else { throw ProjectError("Keep at least one frame of the recording.") }
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
    public var outputDuration: Double { sourceDuration - cuts.reduce(0) { $0 + $1.duration } }

    public func sourceTime(forOutput time: Double) -> Double? {
        guard time.isFinite, time >= 0, time < outputDuration else { return nil }
        var offset = 0.0
        for range in retainedRanges {
            if time < offset + range.duration { return range.start + time - offset }
            offset += range.duration
        }
        return nil
    }

    public func outputTime(forSource time: Double) -> Double? {
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
        return project
    }
    public static func save(_ project: Project, to directory: URL) throws {
        try project.validate()
        _ = try sourceURL(in: directory)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(project).write(to: directory.appendingPathComponent("project.json"), options: .atomic)
    }
    public static func create(_ project: Project, source: URL, at directory: URL) throws {
        try project.validate()
        guard !FileManager.default.fileExists(atPath: directory.path) else { throw ProjectError("Choose a new project filename.") }
        let temp = directory.deletingLastPathComponent().appendingPathComponent(".takelet-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temp) }
        try FileManager.default.createDirectory(at: temp.appendingPathComponent("media"), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: temp.appendingPathComponent("media/source.mov"))
        try save(project, to: temp)
        try FileManager.default.moveItem(at: temp, to: directory)
    }
}
