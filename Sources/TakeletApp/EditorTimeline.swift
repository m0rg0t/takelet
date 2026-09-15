import SwiftUI
import ProjectCore

struct EditorTimeline: View {
    @ObservedObject var workspace: Workspace
    let project: Project
    let editZoom: () -> Void

    private var sourcePosition: Double {
        project.sourceTime(forOutput: min(workspace.playhead, max(0, project.outputDuration - 0.001))) ?? 0
    }

    var body: some View {
        VStack(spacing: 16) {
            transport
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("SOURCE").font(.caption2.weight(.semibold)).foregroundStyle(.secondary).frame(height: 24)
                    Label("Video", systemImage: "film").font(.caption).frame(height: 52)
                    Label("Zoom", systemImage: "viewfinder").font(.caption).foregroundStyle(Studio.zoom).frame(height: 40)
                    Label("Voice", systemImage: "waveform").font(.caption).foregroundStyle(.teal).frame(height: 36)
                }.frame(width: 58, alignment: .leading)
                VStack(spacing: 8) {
                    ruler
                    tracks
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "scissors").foregroundStyle(.secondary)
                Text(project.cuts.isEmpty ? "Click the filmstrip to explore your take" : "\(project.cuts.count) cut\(project.cuts.count == 1 ? "" : "s") · \(String(format: "%.1f", project.sourceDuration - project.retainedDuration)) s removed")
                Spacer()
                Button("Add Zoom", systemImage: "plus") { workspace.addZoom(); editZoom() }
                    .buttonStyle(.borderless).disabled(!workspace.canEdit)
                    .help("Add a zoom at the playhead (⌘⌥Z)")
                Text("Source \(timecode(project.sourceDuration))")
            }.font(.caption).foregroundStyle(.secondary)
        }.padding(20).background(Studio.panel)
    }

    private var transport: some View {
        HStack(spacing: 14) {
            Button {
                workspace.togglePlayback()
            } label: {
                Image(systemName: workspace.isPlaying ? "pause.fill" : "play.fill")
                    .font(.body.weight(.semibold)).frame(width: 30, height: 28)
            }.buttonStyle(.bordered).buttonBorderShape(.circle)
                .keyboardShortcut(.space, modifiers: [])
                .accessibilityLabel(workspace.isPlaying ? "Pause preview" : "Play preview")
                .help("Play or pause (Space)")
            Text(timecode(workspace.playhead)).font(.system(.callout, design: .monospaced).weight(.medium))
            Text("/ \(timecode(project.outputDuration))").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
            Slider(value: Binding(get: { min(workspace.playhead, project.outputDuration) }, set: { workspace.seek($0) }), in: 0...max(0.05, project.outputDuration))
                .accessibilityLabel("Preview position")
            DetailBadge(text: "30 fps")
        }
    }

    private var ruler: some View {
        GeometryReader { geometry in
            ForEach(0..<7) { tick in
                VStack(spacing: 3) {
                    Text((project.sourceDuration * Double(tick) / 6).formatted(.number.precision(.fractionLength(0...1))) + "s")
                        .font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
                    Rectangle().fill(Studio.line).frame(width: 1, height: 5)
                }.position(x: max(14, min(geometry.size.width - 14, geometry.size.width * CGFloat(tick) / 6)), y: 10)
            }
        }.frame(height: 18).accessibilityHidden(true)
    }

    private var tracks: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                VStack(spacing: 8) {
                    filmstrip(width: geometry.size.width).frame(height: 52)
                    zoomTrack(width: geometry.size.width).frame(height: 32)
                    narrationTrack(width: geometry.size.width).frame(height: 28)
                }
                Rectangle().fill(Color.accentColor).frame(width: 2, height: 128)
                    .overlay(alignment: .top) {
                        RoundedRectangle(cornerRadius: 2).fill(Color.accentColor).frame(width: 9, height: 7).offset(y: -4)
                    }
                    .offset(x: min(geometry.size.width - 2, geometry.size.width * sourcePosition / project.sourceDuration))
                    .allowsHitTesting(false)
            }
        }.frame(height: 128)
    }

    private func filmstrip(width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.12))
            if !workspace.thumbnails.isEmpty {
                HStack(spacing: 1) {
                    ForEach(workspace.thumbnails.indices, id: \.self) { index in
                        Image(nsImage: workspace.thumbnails[index]).resizable().scaledToFill()
                            .frame(width: max(0, (width - CGFloat(workspace.thumbnails.count - 1)) / CGFloat(workspace.thumbnails.count)), height: 52).clipped()
                    }
                }
            }
            ForEach(project.cuts) { cut in
                ZStack {
                    Rectangle().fill(Color.red.opacity(0.65))
                    CutHatching().stroke(.white.opacity(0.25), lineWidth: 1)
                    if width * cut.duration / project.sourceDuration > 30 {
                        Image(systemName: "scissors").font(.caption.weight(.semibold)).foregroundStyle(.white)
                    }
                }.frame(width: width * cut.duration / project.sourceDuration).clipped()
                    .offset(x: width * cut.start / project.sourceDuration)
            }
        }.clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor.opacity(0.55)))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in workspace.seekSource(Double(value.location.x / max(1, width)) * project.sourceDuration) })
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Source filmstrip")
            .accessibilityValue("\(timecode(sourcePosition)), \(project.cuts.count) removed intervals")
            .accessibilityAdjustableAction { direction in
                workspace.seekSource(sourcePosition + (direction == .increment ? 1 : -1))
            }
            .help("Scrub the original take. Hatched intervals are removed from the output.")
    }

    private func zoomTrack(width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 7).fill(.primary.opacity(0.035))
            ForEach(project.zooms) { zoom in
                let span = width * zoom.duration / project.sourceDuration
                let selected = workspace.selectedZoomID == zoom.id
                Button {
                    workspace.selectZoom(zoom.id); editZoom()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "viewfinder")
                        if span > 70 { Text("\(zoom.scale, specifier: "%.1f")×").monospacedDigit() }
                    }.font(.caption.weight(.medium)).foregroundStyle(Studio.zoom)
                        .frame(width: max(2, span), height: 32)
                        .background(Studio.zoom.opacity(selected ? 0.28 : 0.15), in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Studio.zoom.opacity(selected ? 1 : 0.25), lineWidth: selected ? 2 : 1))
                }.buttonStyle(.plain).offset(x: width * zoom.start / project.sourceDuration)
                    .disabled(!workspace.canEdit)
                    .accessibilityLabel("Zoom from \(timecode(zoom.start)) to \(timecode(zoom.end)), \(zoom.scale) times")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .help("Select to edit timing and focus. Right-click to remove.")
                    .contextMenu {
                        Button("Edit Zoom") { workspace.selectZoom(zoom.id); editZoom() }
                        Button("Remove Zoom", role: .destructive) { workspace.removeZoom(zoom.id) }
                    }
            }
            if project.zooms.isEmpty {
                Button("Add a zoom", systemImage: "plus") { workspace.addZoom(); editZoom() }
                    .font(.caption).buttonStyle(.borderless).padding(.horizontal, 10).disabled(!workspace.canEdit)
            }
        }
    }

    private func narrationTrack(width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 7).fill(.primary.opacity(0.035))
            ForEach(project.narrations) { narration in
                let span = width * narration.duration / project.sourceDuration
                let selected = workspace.selectedNarrationID == narration.id
                Button { workspace.selectNarration(narration.id) } label: {
                    HStack(spacing: 4) {
                        Image(systemName: narration.audioFile == nil ? "text.bubble" : "waveform")
                        if span > 85 { Text(narration.script.isEmpty ? "Draft" : String(narration.script.prefix(30))).lineLimit(1) }
                    }.font(.caption2).foregroundStyle(.teal)
                        .frame(width: max(2, span), height: 28).clipped()
                        .background(.teal.opacity(selected ? 0.25 : 0.12), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.teal.opacity(selected ? 1 : 0.3), lineWidth: selected ? 2 : 1))
                }.buttonStyle(.plain).offset(x: width * narration.start / project.sourceDuration)
                    .disabled(!workspace.canEdit)
                    .accessibilityLabel("Narration from \(timecode(narration.start)) to \(timecode(narration.end)), \(narration.audioFile == nil ? "draft" : "generated")")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .contextMenu {
                        Button("Edit Narration") { workspace.selectNarration(narration.id) }
                        Button("Remove Narration", role: .destructive) { workspace.removeNarration(narration.id) }
                    }
            }
            if project.narrations.isEmpty {
                Button("Add narration", systemImage: "plus") { workspace.addNarration() }
                    .font(.caption).buttonStyle(.borderless).padding(.horizontal, 10).disabled(!workspace.canEdit)
            }
        }
    }
}

private struct CutHatching: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for x in stride(from: -rect.height, through: rect.width, by: 9) {
            path.move(to: CGPoint(x: x, y: rect.height)); path.addLine(to: CGPoint(x: x + rect.height, y: 0))
        }
        return path
    }
}
