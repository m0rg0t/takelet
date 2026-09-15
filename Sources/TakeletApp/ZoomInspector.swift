import SwiftUI
import ProjectCore

struct ZoomInspector: View {
    @ObservedObject var workspace: Workspace
    let project: Project
    @State private var draft = Zoom()

    var body: some View {
        PanelCard(title: "Zoom & focus", icon: "viewfinder") {
            Button("Add Zoom at Playhead", systemImage: "plus") { workspace.addZoom() }
                .help("Add a zoom at the current source position (⌘⌥Z)")
            Button("Auto Zoom from Clicks", systemImage: "cursorarrow.rays") { workspace.generateClickZooms() }
                .disabled(project.cursor.isEmpty)
                .help("Create editable zooms from recorded clicks (⌘⌥⇧Z)")
            Text(project.cursor.isEmpty ? "Imported videos have no click data. Add zooms manually." : "Auto Zoom uses recorded clicks locally. Review each focus point before export.")
                .font(.caption).foregroundStyle(.secondary)
            if !project.zooms.isEmpty {
                Divider()
                Picker("Zoom", selection: Binding(get: { workspace.selectedZoomID }, set: { id in
                    if let id { workspace.selectZoom(id) } else { workspace.selectedZoomID = nil }
                })) {
                    Text("Choose a zoom").tag(Optional<UUID>.none)
                    ForEach(project.zooms.sorted { $0.start < $1.start }) { zoom in
                        Text("\(timecode(zoom.start)) – \(timecode(zoom.end)) · \(zoom.scale, specifier: "%.1f")×").tag(Optional(zoom.id))
                    }
                }.pickerStyle(.menu).accessibilityLabel("Selected zoom")
            }
            if let selected = workspace.selectedZoom {
                timing
                HStack {
                    Text("Magnification").font(.callout)
                    Spacer()
                    Text("\(draft.scale, specifier: "%.1f")×").font(.system(.callout, design: .monospaced)).foregroundStyle(Studio.zoom)
                }
                Slider(value: $draft.scale, in: 1...3, step: 0.1).accessibilityLabel("Zoom scale")
                VStack(alignment: .leading, spacing: 8) {
                    Text("Focus point").font(.caption).foregroundStyle(.secondary)
                    FocusPicker(x: $draft.x, y: $draft.y)
                    HStack(spacing: 8) {
                        Text("X").font(.caption2).foregroundStyle(.secondary)
                        Slider(value: $draft.x, in: 0...1).accessibilityLabel("Horizontal zoom focus")
                        Text("Y").font(.caption2).foregroundStyle(.secondary)
                        Slider(value: $draft.y, in: 0...1).accessibilityLabel("Vertical zoom focus")
                    }
                }
                Button { workspace.updateZoom(draft) } label: {
                    Text("Apply Zoom").frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).disabled(draft == selected)
                HStack {
                    Button("Preview Zoom", systemImage: "play") { workspace.selectZoom(selected.id) }
                        .buttonStyle(.borderless).disabled(draft != selected)
                        .help("Show the applied zoom at full magnification. Apply changes first.")
                    Spacer()
                    Button("Remove", systemImage: "trash", role: .destructive) { workspace.removeZoom(selected.id) }
                        .buttonStyle(.borderless).help("Remove this zoom (⌘Delete). Undo restores it.")
                }.font(.caption)
            } else if !project.zooms.isEmpty {
                Text("Select a zoom above or on the timeline to edit it.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .onChange(of: workspace.selectedZoom, initial: true) { _, zoom in if let zoom { draft = zoom } }
    }

    private var timing: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                timeInput("Start", value: $draft.start)
                timeInput("End", value: $draft.end)
            }
            Text("Source seconds · Zooms cannot overlap").font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func timeInput(_ label: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(label, value: value, format: .number.precision(.fractionLength(0...2)))
                .textFieldStyle(.roundedBorder).monospacedDigit().accessibilityLabel("Zoom \(label.lowercased()) source seconds")
        }
    }
}
