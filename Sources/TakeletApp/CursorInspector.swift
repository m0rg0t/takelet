import SwiftUI
import ProjectCore

struct CursorInspector: View {
    @ObservedObject var workspace: Workspace
    let project: Project
    private var draft: CursorStyle {
        get { workspace.cursorDraft ?? project.cursorStyle }
        nonmutating set { workspace.cursorDraft = newValue }
    }
    private var cursorBinding: Binding<CursorStyle> { Binding(get: { draft }, set: { draft = $0 }) }

    var body: some View {
        PanelCard(title: "Cursor", icon: "cursorarrow") {
            if project.cursorMode == .embedded {
                Text("This video already contains its cursor. New Takelet recordings keep the cursor separate so you can change its appearance.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Toggle("Show cursor", isOn: Binding(get: { !draft.hidden }, set: { draft.hidden = !$0 }))
                Picker("Shape", selection: Binding(get: { draft.shape }, set: { shape in
                    guard draft.shape != shape else { return }
                    draft.shape = shape
                    let defaults = CursorStyle(shape: shape)
                    draft.hotspotX = defaults.hotspotX; draft.hotspotY = defaults.hotspotY
                })) {
                    Text("Arrow").tag(CursorShape.arrow)
                    Text("Circle").tag(CursorShape.circle)
                    Text("Crosshair").tag(CursorShape.crosshair)
                    if draft.imageFile != nil { Text("Custom PNG").tag(CursorShape.customImage) }
                }
                Button("Import PNG…", systemImage: "photo") { workspace.importCursorImage() }
                    .help("Import a transparent PNG, up to 2048×2048 pixels")
                slider("Size", value: cursorBinding.size, range: 8...256, valueLabel: "\(Int(draft.size)) px")
                slider("Smoothing", value: cursorBinding.smoothing, range: 0...1, valueLabel: "\(Int(draft.smoothing * 100))%")
                if draft.shape != .customImage {
                    ColorPicker("Color", selection: Binding(get: {
                        Color(.sRGB, red: draft.color.red, green: draft.color.green, blue: draft.color.blue, opacity: draft.color.alpha)
                    }, set: { color in
                        if let rgb = NSColor(color).usingColorSpace(.sRGB) {
                            draft.color = CursorRGBA(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent, alpha: rgb.alphaComponent)
                        }
                    }), supportsOpacity: false)
                }
                Toggle("Highlight clicks", isOn: cursorBinding.clickHalo)
                if draft.shape == .customImage {
                    Text("Hotspot — the point that marks a click").font(.caption).foregroundStyle(.secondary)
                    FocusPicker(x: cursorBinding.hotspotX, y: cursorBinding.hotspotY)
                    slider("Hotspot X", value: cursorBinding.hotspotX, range: 0...1, valueLabel: "\(Int(draft.hotspotX * 100))%")
                    slider("Hotspot Y", value: cursorBinding.hotspotY, range: 0...1, valueLabel: "\(Int(draft.hotspotY * 100))%")
                }
                Button { workspace.updateCursor(draft) } label: {
                    Text("Apply Cursor").frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).disabled(draft == project.cursorStyle)
                Text("Cursor size follows the video zoom. The same style appears in preview and export.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, valueLabel: String) -> some View {
        VStack(spacing: 6) {
            HStack { Text(title); Spacer(); Text(valueLabel).monospacedDigit().foregroundStyle(.secondary) }.font(.caption)
            Slider(value: value, in: range).accessibilityLabel(title)
        }
    }
}
