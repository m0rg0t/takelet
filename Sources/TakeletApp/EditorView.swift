import SwiftUI
import AVKit
import ProjectCore

struct EditorView: View {
    @StateObject private var workspace = Workspace()
    @Environment(\.undoManager) private var undoManager
    @State private var cutStart = 0.0
    @State private var cutEnd = 1.0
    @State private var zoom = Zoom()
    @State private var showInspector = true

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 16) {
                Label("Takelet", systemImage: "record.circle").font(.title2.weight(.semibold))
                Text("A good demo starts with one take.").font(.callout).foregroundStyle(.secondary)
                Divider()
                Label("Record a window", systemImage: "macwindow").font(.headline)
                if workspace.windows.isEmpty {
                    Text("Open the app you want to show, then load its windows.").foregroundStyle(.secondary)
                } else {
                    Picker("Window", selection: $workspace.selectedWindowID) {
                        ForEach(workspace.windows) { window in Text(window.title).tag(Optional(window.id)) }
                    }.labelsHidden().accessibilityLabel("Window to record")
                }
                Button("Refresh Windows", systemImage: "arrow.clockwise") { workspace.refreshWindows() }
                    .disabled(workspace.busy || workspace.recording || workspace.exporting)
                Toggle("System audio", isOn: $workspace.systemAudio)
                Toggle("Microphone", isOn: $workspace.microphone)
                Text("macOS may ask for screen recording and microphone access.").font(.caption).foregroundStyle(.secondary)
                Button(workspace.recording ? "Stop Recording" : "Start Recording", systemImage: workspace.recording ? "stop.fill" : "record.circle") {
                    if workspace.recording { workspace.stopRecording() } else { workspace.startRecording() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(workspace.busy || workspace.exporting || (!workspace.recording && workspace.selectedWindowID == nil))
                .keyboardShortcut("r", modifiers: [.command, .shift])
                Divider()
                Button("Import Video…", systemImage: "square.and.arrow.down") { workspace.importVideo() }
                    .disabled(workspace.busy || workspace.recording || workspace.exporting)
                Button("Open Project…", systemImage: "folder") { workspace.openProject() }
                    .disabled(workspace.busy || workspace.recording || workspace.exporting)
                Spacer()
                Text("Developer preview · 0.1.0").font(.caption).foregroundStyle(.secondary)
            }
            .padding(20).frame(maxHeight: .infinity)
            .navigationSplitViewColumnWidth(min: 225, ideal: 250, max: 310)
        } detail: {
            VStack(spacing: 0) {
                if let project = workspace.project {
                    NativePlayer(player: workspace.player)
                        .frame(minHeight: 260).padding(20)
                        .accessibilityLabel("Edited video preview")
                    timeline(project)
                } else {
                    ContentUnavailableView {
                        Label("Make your next demo", systemImage: "play.rectangle.on.rectangle")
                    } description: {
                        Text("Record a window or import a video.\nTrim the pauses, bring a detail closer, and export.")
                    } actions: {
                        Button("Import Video…") { workspace.importVideo() }.buttonStyle(.borderedProminent)
                        Button("Open Project…") { workspace.openProject() }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Divider()
                HStack {
                    if workspace.busy { ProgressView().controlSize(.small) }
                    if workspace.recording { Image(systemName: "record.circle.fill").foregroundStyle(.red) }
                    Text(workspace.status).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                    Spacer()
                    if workspace.exporting {
                        ProgressView(value: workspace.exportProgress).frame(width: 100)
                        Button("Cancel") { workspace.cancelExport() }
                    }
                }.padding(.horizontal, 20).padding(.vertical, 12)
            }
            .inspector(isPresented: $showInspector) {
                if workspace.project != nil { inspector.inspectorColumnWidth(min: 260, ideal: 280, max: 330) }
                else { Text("Recording details and edits appear here.").foregroundStyle(.secondary).padding() }
            }
            .navigationTitle(workspace.project?.title ?? "Takelet")
            .toolbar {
                ToolbarItemGroup {
                    Button("Save Project", systemImage: "square.and.arrow.down") { workspace.saveProject() }.disabled(!workspace.canEdit)
                    Menu {
                        Button("1080p · 30 fps") { workspace.exportVideo(width: 1920) }
                        Button("4K · 30 fps") { workspace.exportVideo(width: 3840) }
                    } label: { Label("Export", systemImage: "square.and.arrow.up") }.disabled(!workspace.canEdit)
                    Button("Inspector", systemImage: "sidebar.right") { showInspector.toggle() }
                }
            }
        }
        .frame(minWidth: 980, minHeight: 640)
        .focusedSceneValue(\.workspace, workspace)
        .background(WindowBridge(workspace: workspace))
        .onAppear { workspace.undoManager = undoManager }
        .onChange(of: workspace.project) { _, project in if let project { zoom = project.zoom } }
        .onOpenURL { workspace.openProject($0) }
        .alert("Takelet", isPresented: Binding(get: { workspace.error != nil }, set: { if !$0 { workspace.error = nil } })) {
            Button("OK", role: .cancel) { workspace.error = nil }
        } message: { Text(workspace.error ?? "") }
    }

    private func timeline(_ project: Project) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button("Play / Pause", systemImage: "playpause") { workspace.togglePlayback() }.labelStyle(.iconOnly).keyboardShortcut(.space, modifiers: [])
                Text("\(workspace.playhead, specifier: "%.1f") / \(project.outputDuration, specifier: "%.1f") s").monospacedDigit()
                Spacer()
                Text("\(project.sourceWidth) × \(project.sourceHeight) · \(project.cuts.count) cuts").foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { min(workspace.playhead, project.outputDuration) }, set: { workspace.seek($0) }), in: 0...max(0.05, project.outputDuration))
                .accessibilityLabel("Preview position")
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 5).fill(Color.accentColor.opacity(0.25))
                    ForEach(project.cuts) { cut in
                        Rectangle().fill(.red.opacity(0.55))
                            .frame(width: geometry.size.width * cut.duration / project.sourceDuration)
                            .offset(x: geometry.size.width * cut.start / project.sourceDuration)
                    }
                }
            }.frame(height: 24).accessibilityLabel("Original source timeline; removed intervals shown in red")
            Text("Source timeline · red intervals are removed from the preview and export").font(.caption).foregroundStyle(.secondary)
        }.padding(20)
    }

    private var inspector: some View {
        Form {
            Section("Remove a pause") {
                number("Start (source s)", value: $cutStart)
                number("End (source s)", value: $cutEnd)
                Button("Remove Interval") { workspace.cut(start: cutStart, end: cutEnd) }.disabled(!workspace.canEdit)
                if let project = workspace.project {
                    ForEach(project.cuts) { cut in
                        HStack {
                            Text("\(cut.start, specifier: "%.2f")–\(cut.end, specifier: "%.2f") s").monospacedDigit()
                            Spacer()
                            Button("Restore", systemImage: "arrow.uturn.backward") {
                                var next = project; next.cuts.removeAll { $0.id == cut.id }; workspace.edit(next, name: "Restore Interval")
                            }.labelStyle(.iconOnly).accessibilityLabel("Restore interval \(cut.start) to \(cut.end) seconds")
                        }
                    }
                }
            }
            Section("Zoom") {
                number("Start (source s)", value: $zoom.start)
                number("End (source s)", value: $zoom.end)
                LabeledContent("Scale", value: "\(zoom.scale.formatted(.number.precision(.fractionLength(1))))×")
                Slider(value: $zoom.scale, in: 1...3, step: 0.1).accessibilityLabel("Zoom scale")
                Text("Focus point").foregroundStyle(.secondary)
                Slider(value: $zoom.x, in: 0...1).accessibilityLabel("Horizontal zoom focus")
                Slider(value: $zoom.y, in: 0...1).accessibilityLabel("Vertical zoom focus")
                Button("Apply Zoom") { if var next = workspace.project { next.zoom = zoom; workspace.edit(next, name: "Change Zoom") } }.disabled(!workspace.canEdit)
                Text("A smooth zoom stays anchored to the original action after cuts.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Project") {
                if let project = workspace.project {
                    LabeledContent("Source", value: "\(project.sourceDuration.formatted(.number.precision(.fractionLength(1)))) s")
                    LabeledContent("Output", value: "\(project.outputDuration.formatted(.number.precision(.fractionLength(1)))) s")
                    LabeledContent("Cursor samples", value: "\(project.cursor.count)")
                }
                Text("Original media stays intact. Save the .takelet project to keep edits with the recording.").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).disabled(workspace.recording || workspace.busy || workspace.exporting)
    }

    private func number(_ label: String, value: Binding<Double>) -> some View {
        TextField(label, value: value, format: .number.precision(.fractionLength(0...2)))
    }
}

/// Use the AppKit player directly; its native controls also fit a desktop editor better.
struct NativePlayer: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .floating
        view.showsSharingServiceButton = false
        view.videoGravity = .resizeAspect
        view.player = player
        return view
    }
    func updateNSView(_ view: AVPlayerView, context: Context) { if view.player !== player { view.player = player } }
}

private struct WorkspaceFocusKey: FocusedValueKey { typealias Value = Workspace }
extension FocusedValues { var workspace: Workspace? { get { self[WorkspaceFocusKey.self] } set { self[WorkspaceFocusKey.self] = newValue } } }

struct WindowBridge: NSViewRepresentable {
    @ObservedObject var workspace: Workspace
    func makeCoordinator() -> Coordinator { Coordinator(workspace: workspace) }
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            view.window?.isDocumentEdited = workspace.dirty
            view.window?.representedURL = workspace.projectURL
            view.window?.delegate = context.coordinator
        }
    }
    @MainActor final class Coordinator: NSObject, NSWindowDelegate {
        let workspace: Workspace
        init(workspace: Workspace) { self.workspace = workspace }
        func windowShouldClose(_ sender: NSWindow) -> Bool { workspace.canClose }
        func windowWillClose(_ notification: Notification) { workspace.close() }
    }
}
