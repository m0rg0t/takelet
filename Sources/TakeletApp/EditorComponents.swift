import SwiftUI
import ProjectCore

enum Studio {
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let panel = Color(nsColor: .windowBackgroundColor)
    static let line = Color.primary.opacity(0.08)
    static let stage = Color(red: 0.075, green: 0.08, blue: 0.10)
    static let zoom = Color.purple
}

extension CanvasBackground {
    var gradient: LinearGradient {
        LinearGradient(colors: colors.map { Color(red: $0.red, green: $0.green, blue: $0.blue) }, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

struct PanelCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: icon).font(.subheadline.weight(.semibold))
            content
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Studio.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Studio.line))
    }
}

struct DetailBadge: View {
    let text: String
    var body: some View {
        Text(text).font(.caption.weight(.medium)).monospacedDigit()
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(.primary.opacity(0.06), in: Capsule())
    }
}

struct BackgroundSwatch: View {
    let preset: CanvasBackground
    let selected: Bool
    let action: () -> Void
    @State private var hovered = false
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                RoundedRectangle(cornerRadius: 8).fill(preset.gradient)
                    .frame(height: 55)
                    .overlay {
                        RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.9))
                            .frame(width: 44, height: 28).shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                    }
                HStack {
                    Text(preset.title).font(.caption.weight(.medium))
                    Spacer(minLength: 0)
                    if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor).font(.caption) }
                }
            }.padding(7)
                .background(selected ? Color.accentColor.opacity(0.08) : Color.primary.opacity(hovered ? 0.04 : 0), in: RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(selected ? Color.accentColor : Studio.line, lineWidth: selected ? 2 : 1))
                .contentShape(RoundedRectangle(cornerRadius: 11))
        }.buttonStyle(.plain)
            .onHover { hovered = $0 }
            .accessibilityLabel("\(preset.title) background")
            .accessibilityAddTraits(selected ? .isSelected : [])
            .help("Use the \(preset.title) background in preview and export")
    }
}

func timecode(_ seconds: Double) -> String {
    let value = max(0, seconds.isFinite ? seconds : 0)
    let tenths = Int((value * 10).rounded())
    return String(format: "%02d:%04.1f", tenths / 600, Double(tenths % 600) / 10)
}

struct FocusPicker: View {
    @Binding var x: Double
    @Binding var y: Double
    private let columns = ["Left", "Center", "Right"]
    private let rows = ["Top", "Middle", "Bottom"]
    var body: some View {
        VStack(spacing: 1) {
            ForEach(0..<3) { row in
                HStack(spacing: 1) {
                    ForEach(0..<3) { column in
                        Button {
                            x = Double(column) / 2; y = Double(row) / 2
                        } label: {
                            Image(systemName: "plus").font(.caption2)
                                .foregroundStyle(.secondary.opacity(0.6))
                                .frame(maxWidth: .infinity).frame(height: 24)
                                .background(.primary.opacity(0.025))
                        }.buttonStyle(.plain)
                            .accessibilityLabel("Focus \(rows[row].lowercased()) \(columns[column].lowercased())")
                    }
                }
            }
        }.clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                GeometryReader { geometry in
                    Image(systemName: "scope").font(.body.weight(.semibold)).foregroundStyle(Color.accentColor)
                        .position(x: 12 + (geometry.size.width - 24) * x, y: 12 + (geometry.size.height - 24) * y)
                }.allowsHitTesting(false)
            }
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Studio.line))
    }
}
