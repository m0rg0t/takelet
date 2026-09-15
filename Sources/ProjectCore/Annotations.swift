import Foundation

public enum AnnotationKind: String, Codable, CaseIterable, Equatable, Sendable {
    case arrow
    case frame
    case text
    case blur
    case cover

    public var title: String {
        switch self {
        case .arrow: "Arrow"
        case .frame: "Frame"
        case .text: "Text"
        case .blur: "Blur"
        case .cover: "Opaque Mask"
        }
    }

    public var isMask: Bool {
        switch self {
        case .blur, .cover: true
        case .arrow, .frame, .text: false
        }
    }
}

public enum AnnotationDirection: String, Codable, CaseIterable, Equatable, Sendable {
    case downRight
    case downLeft
    case upRight
    case upLeft
}

public struct AnnotationColor: Codable, Equatable, Sendable {
    public static let orange = AnnotationColor(red: 1, green: 0.45, blue: 0.1)

    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double = 1, green: Double = 0.45, blue: Double = 0.1) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public func validate() throws {
        guard [red, green, blue].allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
            throw ProjectError("Annotation color components must be between 0 and 1.")
        }
    }
}

/// A normalized rectangle measured from the source frame's top-left corner.
public struct AnnotationBounds: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double = 0.3, y: Double = 0.3, width: Double = 0.4, height: Double = 0.2) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public func validate() throws {
        // Drag math can land a few binary floating-point units either side of an exact UI boundary.
        let tolerance = 1e-12
        guard [x, y, width, height].allSatisfy(\.isFinite),
              x >= 0, y >= 0, width >= 0.01 - tolerance, height >= 0.01 - tolerance,
              x + width <= 1 + tolerance, y + height <= 1 + tolerance else {
            throw ProjectError("Annotation bounds must be a rectangle inside the source frame.")
        }
    }

    /// Moves the rectangle while preserving a valid size and keeping it inside the frame.
    public func translated(dx: Double, dy: Double) -> AnnotationBounds {
        let safeWidth = Self.dimension(width, fallback: 0.4)
        let safeHeight = Self.dimension(height, fallback: 0.2)
        let safeX = Self.clamp(x.isFinite ? x : 0.3, minimum: 0, maximum: 1 - safeWidth)
        let safeY = Self.clamp(y.isFinite ? y : 0.3, minimum: 0, maximum: 1 - safeHeight)
        let deltaX = dx.isFinite ? dx : 0
        let deltaY = dy.isFinite ? dy : 0
        return AnnotationBounds(
            x: Self.clamp(safeX + deltaX, minimum: 0, maximum: 1 - safeWidth),
            y: Self.clamp(safeY + deltaY, minimum: 0, maximum: 1 - safeHeight),
            width: safeWidth,
            height: safeHeight
        )
    }

    /// Resizes from the current top-left corner and clamps the result to the frame.
    public func resized(width proposedWidth: Double, height proposedHeight: Double) -> AnnotationBounds {
        let safeX = Self.clamp(x.isFinite ? x : 0.3, minimum: 0, maximum: 0.99)
        let safeY = Self.clamp(y.isFinite ? y : 0.3, minimum: 0, maximum: 0.99)
        let fallbackWidth = Self.dimension(width, fallback: 0.4)
        let fallbackHeight = Self.dimension(height, fallback: 0.2)
        let requestedWidth = proposedWidth.isFinite ? proposedWidth : fallbackWidth
        let requestedHeight = proposedHeight.isFinite ? proposedHeight : fallbackHeight
        return AnnotationBounds(
            x: safeX,
            y: safeY,
            width: Self.clamp(requestedWidth, minimum: 0.01, maximum: 1 - safeX),
            height: Self.clamp(requestedHeight, minimum: 0.01, maximum: 1 - safeY)
        )
    }

    private static func dimension(_ value: Double, fallback: Double) -> Double {
        clamp(value.isFinite ? value : fallback, minimum: 0.01, maximum: 1)
    }

    private static func clamp(_ value: Double, minimum: Double, maximum: Double) -> Double {
        min(maximum, max(minimum, value))
    }
}

/// A timed callout or privacy mask anchored to original source time and source coordinates.
public struct Annotation: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var start: Double
    public var end: Double
    public var kind: AnnotationKind
    public var bounds: AnnotationBounds
    public var color: AnnotationColor
    public var text: String
    public var direction: AnnotationDirection
    /// Line thickness normalized to the source frame's shorter edge.
    public var strokeWidth: Double
    /// Text size normalized to the source frame's shorter edge.
    public var fontSize: Double
    /// Blur radius normalized to the source frame's shorter edge.
    public var blurRadius: Double

    public var duration: Double { end - start }

    public init(
        kind: AnnotationKind,
        start: Double,
        end: Double,
        bounds: AnnotationBounds = AnnotationBounds(),
        color: AnnotationColor = .orange,
        text: String = "Callout",
        direction: AnnotationDirection = .downRight,
        strokeWidth: Double = 0.006,
        fontSize: Double = 0.05,
        blurRadius: Double = 0.02,
        id: UUID = UUID()
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.kind = kind
        self.bounds = bounds
        self.color = color
        self.text = text
        self.direction = direction
        self.strokeWidth = strokeWidth
        self.fontSize = fontSize
        self.blurRadius = blurRadius
    }

    public func isVisible(atSource sourceTime: Double) -> Bool {
        sourceTime.isFinite && sourceTime >= start && sourceTime < end
    }

    public func validate(duration sourceDuration: Double) throws {
        guard sourceDuration.isFinite, sourceDuration > 0,
              start.isFinite, end.isFinite,
              start >= 0, end > start, end <= sourceDuration else {
            throw ProjectError("Annotation times must be inside the recording.")
        }
        try bounds.validate()
        try color.validate()
        guard text.count <= 500 else {
            throw ProjectError("Annotation text must contain at most 500 characters.")
        }
        if kind == .text, text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ProjectError("Text annotations need visible text.")
        }
        guard strokeWidth.isFinite, (0.001...0.03).contains(strokeWidth),
              fontSize.isFinite, (0.015...0.18).contains(fontSize),
              blurRadius.isFinite, (0.003...0.08).contains(blurRadius) else {
            throw ProjectError("Annotation stroke, text size, or blur radius is outside the supported range.")
        }
    }
}
