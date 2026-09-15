import SwiftUI
import ProjectCore

struct AnnotationInspector: View {
    @ObservedObject var workspace: Workspace
    let project: Project
    @State private var placingAnnotation: Annotation?

    private var draft: Annotation? { workspace.selectedAnnotationDraft }

    var body: some View {
        PanelCard(title: "Callouts & masks", icon: "square.and.pencil") {
            HStack {
                Menu("Add Callout") {
                    ForEach(AnnotationKind.allCases.filter { !$0.isMask }, id: \.self) { kind in
                        Button(kind.title, systemImage: kind.symbol) { workspace.addAnnotation(kind) }
                    }
                }
                Menu("Add Mask") {
                    Button("Blur", systemImage: "drop.halffull") { workspace.addAnnotation(.blur) }
                    Button("Opaque Mask", systemImage: "rectangle.fill") { workspace.addAnnotation(.cover) }
                }
            }
            Text("Attach an annotation to the recording. Its position follows zooms and its timing follows cuts.")
                .font(.caption).foregroundStyle(.secondary)
            if !project.annotations.isEmpty {
                Divider()
                Picker("Annotation", selection: Binding(get: { workspace.selectedAnnotationID }, set: { id in
                    if let id { workspace.selectAnnotation(id) } else { workspace.selectedAnnotationID = nil }
                })) {
                    Text("Choose an annotation").tag(Optional<UUID>.none)
                    ForEach(Array(project.annotations.enumerated()), id: \.element.id) { index, annotation in
                        Text("\(index + 1). \(annotation.kind.title) · \(timecode(annotation.start))").tag(Optional(annotation.id))
                    }
                }.pickerStyle(.menu).accessibilityLabel("Selected callout or mask")
            }
            if let draft {
                HStack(spacing: 8) {
                    numberField("Start", value: binding(\.start), suffix: "source seconds")
                    numberField("End", value: binding(\.end), suffix: "source seconds")
                }
                Button("Use Entire Take", systemImage: "arrow.left.and.right") {
                    var next = draft; next.start = 0; next.end = project.sourceDuration
                    workspace.annotationDrafts[next.id] = next
                }.font(.caption).buttonStyle(.borderless)
                Button("Place on Frame…", systemImage: "arrow.up.left.and.arrow.down.right") { placingAnnotation = draft }
                    .controlSize(.large).frame(maxWidth: .infinity)
                    .help("Drag and resize the annotation on the original frame")
                DisclosureGroup("Position & size") {
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            numberField("Left", value: percentBinding(\.x), suffix: "percent")
                            numberField("Top", value: percentBinding(\.y), suffix: "percent")
                        }
                        HStack(spacing: 8) {
                            numberField("Width", value: percentBinding(\.width), suffix: "percent")
                            numberField("Height", value: percentBinding(\.height), suffix: "percent")
                        }
                    }.padding(.top, 8)
                }.font(.caption)
                if draft.kind == .text {
                    TextField("Callout text", text: binding(\.text), axis: .vertical)
                        .lineLimit(2...6).textFieldStyle(.roundedBorder)
                    Text("\(draft.text.count)/500 characters").font(.caption2).foregroundStyle(.secondary)
                    styleSlider("Text size", value: binding(\.fontSize), range: 0.015...0.18)
                }
                if draft.kind == .arrow {
                    Picker("Direction", selection: binding(\.direction)) {
                        Text("↘ Down right").tag(AnnotationDirection.downRight)
                        Text("↙ Down left").tag(AnnotationDirection.downLeft)
                        Text("↗ Up right").tag(AnnotationDirection.upRight)
                        Text("↖ Up left").tag(AnnotationDirection.upLeft)
                    }.pickerStyle(.menu)
                }
                if draft.kind == .arrow || draft.kind == .frame {
                    styleSlider("Line width", value: binding(\.strokeWidth), range: 0.001...0.03)
                }
                if draft.kind == .blur {
                    styleSlider("Blur strength", value: binding(\.blurRadius), range: 0.003...0.08)
                } else {
                    ColorPicker(draft.kind == .text ? "Label background" : "Color", selection: colorBinding, supportsOpacity: false)
                }
                if draft.kind.isMask {
                    Text("Use an opaque mask for private text. Blur softens details. The original video in a saved project stays unchanged.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button("Apply Annotation") {
                    if workspace.updateAnnotation(draft) { workspace.selectAnnotation(draft.id) }
                }.buttonStyle(.borderedProminent).disabled(draft == workspace.selectedAnnotation)
                HStack {
                    Button("Duplicate", systemImage: "plus.square.on.square") { workspace.duplicateAnnotation(draft.id) }
                    Spacer()
                    Button("Remove", systemImage: "trash", role: .destructive) { workspace.removeAnnotation(draft.id) }
                }.font(.caption).buttonStyle(.borderless)
                HStack {
                    Button("Backward", systemImage: "square.2.layers.3d.bottom.filled") { workspace.moveAnnotation(draft.id, forward: false) }
                    Spacer()
                    Button("Forward", systemImage: "square.2.layers.3d.top.filled") { workspace.moveAnnotation(draft.id, forward: true) }
                }.font(.caption).buttonStyle(.borderless)
                Text("Masks cover callouts. Layer order is shared by preview and export.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .sheet(item: $placingAnnotation) { annotation in
            AnnotationPlacementView(workspace: workspace, annotationID: annotation.id)
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<Annotation, Value>) -> Binding<Value> {
        let snapshot = draft ?? Annotation(kind: .frame, start: 0, end: 1)
        return Binding(get: { workspace.selectedAnnotationDraft?[keyPath: keyPath] ?? snapshot[keyPath: keyPath] }, set: { value in
            guard var next = workspace.selectedAnnotationDraft else { return }
            next[keyPath: keyPath] = value; workspace.annotationDrafts[next.id] = next
        })
    }

    private func percentBinding(_ keyPath: WritableKeyPath<AnnotationBounds, Double>) -> Binding<Double> {
        Binding(get: { (workspace.selectedAnnotationDraft?.bounds[keyPath: keyPath] ?? 0) * 100 }, set: { value in
            guard var next = workspace.selectedAnnotationDraft else { return }
            next.bounds[keyPath: keyPath] = value / 100; workspace.annotationDrafts[next.id] = next
        })
    }

    private var colorBinding: Binding<Color> {
        Binding(get: {
            let color = draft?.color ?? AnnotationColor()
            return Color(red: color.red, green: color.green, blue: color.blue)
        }, set: { value in
            guard var next = draft, let color = NSColor(value).usingColorSpace(.sRGB) else { return }
            next.color = AnnotationColor(red: color.redComponent, green: color.greenComponent, blue: color.blueComponent)
            workspace.annotationDrafts[next.id] = next
        })
    }

    private func styleSlider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text(label); Spacer(); Text("\(value.wrappedValue * 100, specifier: "%.1f")%").monospacedDigit().foregroundStyle(.secondary) }
                .font(.caption)
            Slider(value: value, in: range).accessibilityLabel(label)
        }
    }

    private func numberField(_ label: String, value: Binding<Double>, suffix: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label + (suffix == "percent" ? " %" : " s")).font(.caption).foregroundStyle(.secondary)
            TextField(label, value: value, format: .number.precision(.fractionLength(0...2)))
                .textFieldStyle(.roundedBorder).monospacedDigit().accessibilityLabel("Annotation \(label.lowercased()) \(suffix)")
        }
    }
}

extension AnnotationKind {
    var symbol: String {
        switch self {
        case .arrow: "arrow.up.right"
        case .frame: "rectangle.dashed"
        case .text: "text.bubble"
        case .blur: "drop.halffull"
        case .cover: "rectangle.fill"
        }
    }
}
