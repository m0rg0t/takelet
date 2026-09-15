import Foundation

public struct RGB: Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public init(_ red: Double, _ green: Double, _ blue: Double) {
        self.red = red; self.green = green; self.blue = blue
    }
}

/// Shared color definitions keep preset swatches and encoded backgrounds in agreement.
public enum CanvasBackground: String, Codable, CaseIterable, Sendable {
    case midnight, mist, dawn, tide
    public var title: String { rawValue.capitalized }
    public var colors: [RGB] {
        switch self {
        case .midnight: return [RGB(0.065, 0.085, 0.13), RGB(0.065, 0.085, 0.13)]
        case .mist: return [RGB(0.93, 0.94, 0.97), RGB(0.68, 0.73, 0.84)]
        case .dawn: return [RGB(0.96, 0.68, 0.50), RGB(0.42, 0.32, 0.58)]
        case .tide: return [RGB(0.52, 0.79, 0.77), RGB(0.10, 0.29, 0.40)]
        }
    }
}
