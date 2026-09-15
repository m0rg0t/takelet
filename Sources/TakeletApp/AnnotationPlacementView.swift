import SwiftUI
@preconcurrency import AVFoundation
@preconcurrency import CoreImage
import MediaEngine
import ProjectCore

/// Place source-anchored annotations on the unzoomed frame. The picture uses the
/// export renderer; the selection outline and resize handles are editor-only.
struct AnnotationPlacementView: View {
    @ObservedObject var workspace: Workspace
    let annotationID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var originalDraft: Annotation?
    @State private var sourceImage: CGImage?
    @State private var renderedImage: CGImage?
    @State private var frameTime = 0.0
    @State private var frameRevision = 0
    @State private var frameError: String?
    @State private var renderError: String?
    @State private var dragOrigin: AnnotationBounds?
    @State private var context = CIContext()

    private var draft: Annotation? {
        workspace.annotationDrafts[annotationID] ?? workspace.project?.annotations.first { $0.id == annotationID }
    }

    private var annotations: [Annotation] {
        (workspace.project?.annotations ?? []).map { workspace.annotationDrafts[$0.id] ?? $0 }
    }

    private struct RenderKey: Equatable {
        let annotations: [Annotation]
        let frameRevision: Int
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Place on Frame", systemImage: draft?.kind.symbol ?? "square.and.pencil").font(.title3.weight(.semibold))
                Spacer()
                Text("Original frame · \(timecode(frameTime))").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Text("Drag the outlined area to move it. Drag a corner to resize. The final preview applies the video's zoom and framing.")
                .font(.callout).foregroundStyle(.secondary)
            GeometryReader { geometry in
                let aspect = CGFloat(sourceImage?.width ?? workspace.project?.sourceWidth ?? 16) / CGFloat(sourceImage?.height ?? workspace.project?.sourceHeight ?? 9)
                let width = max(1, min(geometry.size.width - 24, (geometry.size.height - 24) * aspect))
                let size = CGSize(width: width, height: width / aspect)
                ZStack(alignment: .topLeading) {
                    if let renderedImage {
                        Image(decorative: renderedImage, scale: 1).resizable().frame(width: size.width, height: size.height)
                    } else {
                        Rectangle().fill(.black.opacity(0.8))
                        if frameError == nil { ProgressView().position(x: size.width / 2, y: size.height / 2) }
                    }
                    if let draft, (try? draft.bounds.validate()) != nil {
                        selection(draft.bounds, size: size)
                    }
                }.frame(width: size.width, height: size.height)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            }.frame(minHeight: 280).background(Studio.stage, in: RoundedRectangle(cornerRadius: 10))
            if let message = frameError ?? renderError {
                Label(message, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            }
            HStack {
                Text("Position and size can also be entered as percentages in the inspector.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") {
                    if let originalDraft, workspace.project?.annotations.contains(where: { $0.id == annotationID }) == true {
                        if originalDraft == workspace.project?.annotations.first(where: { $0.id == annotationID }) {
                            workspace.annotationDrafts.removeValue(forKey: annotationID)
                        } else { workspace.annotationDrafts[annotationID] = originalDraft }
                    }
                    dismiss()
                }.keyboardShortcut(.cancelAction)
                Button("Apply") {
                    if let draft, workspace.updateAnnotation(draft) { dismiss() }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(!workspace.canEdit || draft == nil || frameError != nil || renderError != nil || renderedImage == nil)
            }
        }.padding(24).frame(minWidth: 700, idealWidth: 920, minHeight: 500, idealHeight: 660)
            .task {
                originalDraft = draft
                guard let draft, let source = workspace.sourceURL, let project = workspace.project else {
                    frameError = "Open a recording to place annotations."; return
                }
                let position = workspace.sourcePosition
                frameTime = draft.isVisible(atSource: position) ? position : max(0, min(draft.start, project.sourceDuration - 0.001))
                let generator = AVAssetImageGenerator(asset: AVURLAsset(url: source))
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: 1600, height: 1000)
                generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
                defer { generator.cancelAllCGImageGeneration() }
                do {
                    sourceImage = try await generator.image(at: CMTime(seconds: frameTime, preferredTimescale: 60000)).image
                    try Task.checkCancellation()
                    frameRevision += 1
                } catch is CancellationError { }
                catch { frameError = error.localizedDescription }
            }
            .task(id: RenderKey(annotations: annotations, frameRevision: frameRevision)) {
                guard let sourceImage, let project = workspace.project else { return }
                do {
                    // Coalesce dragging updates while the outline follows the pointer immediately.
                    try await Task.sleep(for: .milliseconds(80))
                    for annotation in annotations { try annotation.validate(duration: project.sourceDuration) }
                    let renderer = try AnnotationRenderer(annotations: annotations, sourceWidth: project.sourceWidth, sourceHeight: project.sourceHeight)
                    let input = CIImage(cgImage: sourceImage)
                    let output = renderer.composite(over: input, sourceTime: frameTime)
                    guard let image = context.createCGImage(output, from: input.extent) else { throw ProjectError("Cannot render this annotation.") }
                    try Task.checkCancellation()
                    renderedImage = image; renderError = nil
                } catch is CancellationError { }
                catch { renderError = error.localizedDescription }
            }
    }

    private func selection(_ bounds: AnnotationBounds, size: CGSize) -> some View {
        let rect = CGRect(x: bounds.x * size.width, y: bounds.y * size.height, width: bounds.width * size.width, height: bounds.height * size.height)
        return ZStack(alignment: .topLeading) {
            Rectangle().fill(.clear).contentShape(Rectangle())
                .overlay(Rectangle().stroke(.white, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3])))
                .frame(width: rect.width, height: rect.height).offset(x: rect.minX, y: rect.minY)
                .gesture(DragGesture(minimumDistance: 1).onChanged { value in
                    let start = dragOrigin ?? bounds; dragOrigin = start
                    changeBounds(start.translated(dx: value.translation.width / size.width, dy: value.translation.height / size.height))
                }.onEnded { _ in dragOrigin = nil })
                .accessibilityLabel("Move annotation")
                .accessibilityHint("Use the inspector position fields for exact placement.")
            ForEach(0..<4) { corner in
                let right = corner % 2 == 1
                let bottom = corner >= 2
                RoundedRectangle(cornerRadius: 3).fill(Color.accentColor)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(.white, lineWidth: 2))
                    .frame(width: 13, height: 13).contentShape(Rectangle().inset(by: -5))
                    .position(x: right ? rect.maxX : rect.minX, y: bottom ? rect.maxY : rect.minY)
                    .gesture(DragGesture(minimumDistance: 1).onChanged { value in
                        let start = dragOrigin ?? bounds; dragOrigin = start
                        let dx = value.translation.width / size.width, dy = value.translation.height / size.height
                        let left = right ? start.x : min(start.x + start.width - 0.01, max(0, start.x + dx))
                        let top = bottom ? start.y : min(start.y + start.height - 0.01, max(0, start.y + dy))
                        let endX = right ? max(start.x + 0.01, min(1, start.x + start.width + dx)) : start.x + start.width
                        let endY = bottom ? max(start.y + 0.01, min(1, start.y + start.height + dy)) : start.y + start.height
                        changeBounds(AnnotationBounds(x: left, y: top, width: endX - left, height: endY - top))
                    }.onEnded { _ in dragOrigin = nil })
                    .accessibilityLabel("Resize annotation corner \(corner + 1)")
            }
        }.frame(width: size.width, height: size.height).disabled(!workspace.canEdit)
    }

    private func changeBounds(_ bounds: AnnotationBounds) {
        guard workspace.canEdit, var next = draft else { return }
        next.bounds = bounds; workspace.annotationDrafts[annotationID] = next
    }
}
