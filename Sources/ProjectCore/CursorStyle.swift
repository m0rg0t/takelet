import Foundation

/// Describes whether the source movie already contains a cursor image.
public enum CursorRecordingMode: String, Codable, CaseIterable, Equatable, Sendable {
    case embedded
    case separate
}

public enum CursorShape: String, Codable, CaseIterable, Equatable, Sendable {
    case arrow
    case circle
    case crosshair
    case customImage

    fileprivate var defaultHotspot: CursorPoint {
        switch self {
        case .arrow: CursorPoint(x: 0.08, y: 0.06)
        case .circle, .crosshair, .customImage: CursorPoint(x: 0.5, y: 0.5)
        }
    }
}

public struct CursorRGBA: Codable, Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double = 1, green: Double = 1, blue: Double = 1, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public func validate() throws {
        guard [red, green, blue, alpha].allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
            throw ProjectError("Cursor color components must be between 0 and 1.")
        }
    }
}

public struct CursorStyle: Codable, Equatable, Sendable {
    public static let `default` = CursorStyle()

    public var shape: CursorShape
    public var color: CursorRGBA
    /// Cursor width in source pixels. Zooming the source also zooms the cursor.
    public var size: Double
    /// Motion smoothing from 0 (raw samples) to 1 (maximum smoothing).
    public var smoothing: Double
    public var clickHalo: Bool
    public var hidden: Bool
    /// Portable custom PNG path, relative to the project package.
    public var imageFile: String?
    /// Normalized hotspot measured from the image's top-left corner.
    public var hotspotX: Double
    public var hotspotY: Double

    public init(
        shape: CursorShape = .arrow,
        color: CursorRGBA = CursorRGBA(),
        size: Double = 32,
        smoothing: Double = 0.35,
        clickHalo: Bool = true,
        hidden: Bool = false,
        imageFile: String? = nil,
        hotspotX: Double? = nil,
        hotspotY: Double? = nil
    ) {
        self.shape = shape
        self.color = color
        self.size = size
        self.smoothing = smoothing
        self.clickHalo = clickHalo
        self.hidden = hidden
        self.imageFile = imageFile
        self.hotspotX = hotspotX ?? shape.defaultHotspot.x
        self.hotspotY = hotspotY ?? shape.defaultHotspot.y
    }

    public func validate() throws {
        try color.validate()
        guard size.isFinite, (8...256).contains(size),
              smoothing.isFinite, (0...1).contains(smoothing),
              hotspotX.isFinite, hotspotY.isFinite,
              (0...1).contains(hotspotX), (0...1).contains(hotspotY) else {
            throw ProjectError("Cursor size, smoothing, or hotspot is invalid.")
        }
        if shape == .customImage, imageFile == nil {
            throw ProjectError("A custom cursor needs a PNG stored inside the project.")
        }
        if let imageFile {
            let components = imageFile.split(separator: "/", omittingEmptySubsequences: false)
            guard components.count == 3,
                  components[0] == "media", components[1] == "cursors",
                  components[2].hasSuffix(".png") else {
                throw ProjectError("Custom cursor images must use media/cursors/<UUID>.png inside the project.")
            }
            let stem = String(components[2].dropLast(4))
            guard UUID(uuidString: stem) != nil else {
                throw ProjectError("Custom cursor images must use a UUID filename.")
            }
        }
    }
}

public struct CursorPoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

public struct CursorHalo: Equatable, Sendable {
    public var position: CursorPoint
    /// Zero at click onset, one when the halo animation finishes.
    public var progress: Double
    public init(position: CursorPoint, progress: Double) { self.position = position; self.progress = progress }
}

public struct CursorFrame: Equatable, Sendable {
    public var position: CursorPoint
    public var pressed: Bool
    public var halo: CursorHalo?
    public init(position: CursorPoint, pressed: Bool, halo: CursorHalo?) {
        self.position = position; self.pressed = pressed; self.halo = halo
    }
}

/// Precomputes cursor motion once, then interpolates it in original source time.
/// Invisible, out-of-bounds, or delayed samples split motion into independent spans.
public struct CursorTimeline: Sendable {
    public static let maximumSampleGap = 0.25
    public static let clickHaloDuration = 0.45

    private struct TimedPoint: Sendable {
        var time: Double
        var point: CursorPoint
        var pressed: Bool
        var span: Int
    }
    private struct Click: Sendable { var time: Double; var point: CursorPoint; var span: Int }

    private let points: [TimedPoint]
    private let clicks: [Click]
    private let spanEndTimes: [Double]

    public init(samples: [CursorSample], smoothing: Double) {
        let amount = min(1, max(0, smoothing.isFinite ? smoothing : 0))
        let ordered = samples.enumerated().filter(\.element.time.isFinite).sorted {
            $0.element.time == $1.element.time ? $0.offset < $1.offset : $0.element.time < $1.element.time
        }.map(\.element)

        var spans: [[CursorSample]] = []
        var ends: [Double] = []
        var active: [CursorSample] = []
        for sample in ordered {
            let usable = sample.time.isFinite && sample.x.isFinite && sample.y.isFinite
                && sample.visible && (0...1).contains(sample.x) && (0...1).contains(sample.y)
            let contiguous = active.last.map { sample.time >= $0.time && sample.time - $0.time <= Self.maximumSampleGap } ?? true
            if !usable || !contiguous {
                if let last = active.last {
                    spans.append(active)
                    ends.append(!usable ? max(last.time, sample.time) : last.time + Self.maximumSampleGap)
                    active.removeAll(keepingCapacity: true)
                }
                if !usable { continue }
            }
            active.append(sample)
        }
        if let last = active.last {
            spans.append(active)
            ends.append((last.time + Self.maximumSampleGap).nextUp)
        }

        var builtPoints: [TimedPoint] = []
        var builtClicks: [Click] = []
        builtPoints.reserveCapacity(ordered.count)
        for (spanIndex, span) in spans.enumerated() {
            let smoothed = Self.smooth(span, amount: amount)
            for index in span.indices {
                builtPoints.append(TimedPoint(time: span[index].time, point: smoothed[index], pressed: span[index].pressed, span: spanIndex))
                if index > span.startIndex, !span[index - 1].pressed, span[index].pressed {
                    builtClicks.append(Click(time: span[index].time, point: smoothed[index], span: spanIndex))
                }
            }
        }
        points = builtPoints
        clicks = builtClicks
        spanEndTimes = ends
    }

    public func frame(at sourceTime: Double) -> CursorFrame? {
        guard sourceTime.isFinite, !points.isEmpty else { return nil }
        let upper = points.partitioningIndex { $0.time > sourceTime }
        let current: TimedPoint
        if upper == 0 {
            guard points[0].time == sourceTime else { return nil }
            current = points[0]
        } else if points[upper - 1].time == sourceTime {
            current = points[upper - 1]
        } else if upper == points.count {
            let last = points[points.count - 1]
            guard sourceTime - last.time <= Self.maximumSampleGap else { return nil }
            current = last
        } else {
            let before = points[upper - 1]
            let after = points[upper]
            guard before.span == after.span, after.time - before.time <= Self.maximumSampleGap else { return nil }
            if after.time == before.time {
                current = after
            } else {
                let amount = (sourceTime - before.time) / (after.time - before.time)
                current = TimedPoint(
                    time: sourceTime,
                    point: CursorPoint(
                        x: before.point.x + (after.point.x - before.point.x) * amount,
                        y: before.point.y + (after.point.y - before.point.y) * amount
                    ),
                    pressed: before.pressed,
                    span: before.span
                )
            }
        }

        // A sampled invisible or invalid position takes effect at its timestamp.
        guard sourceTime < spanEndTimes[current.span] else { return nil }

        let clickIndex = clicks.partitioningIndex { $0.time > sourceTime }
        var halo: CursorHalo?
        if clickIndex > 0 {
            let click = clicks[clickIndex - 1]
            let age = sourceTime - click.time
            if click.span == current.span, age >= 0, age < Self.clickHaloDuration {
                halo = CursorHalo(position: click.point, progress: age / Self.clickHaloDuration)
            }
        }
        return CursorFrame(position: current.point, pressed: current.pressed, halo: halo)
    }

    private static func smooth(_ samples: [CursorSample], amount: Double) -> [CursorPoint] {
        guard amount > 0, samples.count > 1 else { return samples.map { CursorPoint(x: $0.x, y: $0.y) } }
        // A time-based exponential filter behaves consistently across capture frame rates.
        let response = 0.008 + amount * 0.12
        var result = [CursorPoint(x: samples[0].x, y: samples[0].y)]
        result.reserveCapacity(samples.count)
        for index in samples.indices.dropFirst() {
            let elapsed = max(0, samples[index].time - samples[index - 1].time)
            let blend = 1 - exp(-elapsed / response)
            let previous = result[index - 1]
            result.append(CursorPoint(
                x: previous.x + (samples[index].x - previous.x) * blend,
                y: previous.y + (samples[index].y - previous.y) * blend
            ))
        }
        return result
    }
}

private extension Array {
    func partitioningIndex(where belongsInSecondPartition: (Element) -> Bool) -> Int {
        var low = startIndex
        var high = endIndex
        while low < high {
            let distance = self.distance(from: low, to: high)
            let middle = index(low, offsetBy: distance / 2)
            if belongsInSecondPartition(self[middle]) { high = middle } else { low = index(after: middle) }
        }
        return low
    }
}
