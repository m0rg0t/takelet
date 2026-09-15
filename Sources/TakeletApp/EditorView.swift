import SwiftUI
import AVKit
import ProjectCore

private enum InspectorTab: String, CaseIterable { case style = "Style", edit = "Edit" }

struct EditorView: View {
    @StateObject private var workspace = Workspace()
    @Environment(\.undoManager) private var undoManager
    @State private var cutStart = 0.0
    @State private var cutEnd = 1.0
    @State private var padding = 0.06
    @State private var showInspector = true
    @State private var inspectorTab = InspectorTab.style
    @State private var captureExpanded = true

    var body: some View {
        NavigationSplitView {
            sidebar.navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            VStack(spacing: 0) {
                if let project = workspace.project {
                    preview(project)
                    Divider()
                    EditorTimeline(workspace: workspace, project: project) {
                        inspectorTab = .edit; showInspector = true
                    }
                } else { welcome }
                Divider()
                statusBar
            }
            .inspector(isPresented: $showInspector) {
                inspector.inspectorColumnWidth(min: 270, ideal: 290, max: 340)
            }
            .navigationTitle(workspace.project?.title ?? "Takelet")
            .toolbar {
                ToolbarItemGroup {
                    Button("Save Project", systemImage: "square.and.arrow.down") { workspace.saveProject() }
                        .disabled(!workspace.canEdit).help("Save project (⌘S)")
                    Menu {
                        Button("1080p · 30 fps") { workspace.exportVideo(width: 1920) }
                        Button("4K · 30 fps") { workspace.exportVideo(width: 3840) }
                    } label: { Label("Export", systemImage: "arrow.up.right") }
                    .disabled(!workspace.canEdit).help("Export video").accessibilityLabel("Export video")
                    Button("Inspector", systemImage: "sidebar.right") { showInspector.toggle() }
                        .help("Show or hide the inspector")
                }
            }
        }
        .frame(minWidth: 1040, minHeight: 700)
        .focusedSceneValue(\.workspace, workspace)
        .background(WindowBridge(workspace: workspace))
        .onAppear { workspace.undoManager = undoManager }
        .onChange(of: workspace.selectedZoomID) { _, value in
            if value != nil { inspectorTab = .edit; showInspector = true }
        }
        .onChange(of: workspace.project?.padding, initial: true) { _, value in if let value { padding = value } }
        .onChange(of: workspace.project == nil, initial: true) { _, empty in captureExpanded = empty }
        .task(id: workspace.sourceURL) { await workspace.loadThumbnails() }
        .onOpenURL { workspace.openProject($0) }
        .alert("Takelet", isPresented: Binding(get: { workspace.error != nil }, set: { if !$0 { workspace.error = nil } })) {
            Button("OK", role: .cancel) { workspace.error = nil }
        } message: { Text(workspace.error ?? "") }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 10) {
                Image(systemName: "play.rectangle.fill").font(.title2).foregroundStyle(Color.accentColor)
                Text("Takelet").font(.title3.weight(.semibold))
            }.padding(.top, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("MEDIA").font(.caption.weight(.semibold)).tracking(1).foregroundStyle(.secondary)
                            Spacer()
                            if workspace.project != nil { Text("1").font(.caption).foregroundStyle(.secondary) }
                        }
                        if let project = workspace.project { mediaCard(project) }
                        else {
                            VStack(spacing: 8) {
                                Image(systemName: "rectangle.stack").font(.title2).foregroundStyle(.tertiary)
                                Text("Your take lives here").font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity).padding(.vertical, 24)
                                .background(.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
                        }
                        Button { workspace.importVideo() } label: {
                            Label("Import Video…", systemImage: "plus").frame(maxWidth: .infinity)
                        }.controlSize(.large).disabled(workspace.busy || workspace.recording || workspace.exporting)
                        Button("Open Project…", systemImage: "folder") { workspace.openProject() }
                            .buttonStyle(.borderless).font(.callout)
                            .disabled(workspace.busy || workspace.recording || workspace.exporting)
                    }
                    Divider()
                    DisclosureGroup(isExpanded: $captureExpanded) {
                        captureControls.padding(.top, 14)
                    } label: {
                        Label("Record a window", systemImage: "record.circle").font(.subheadline.weight(.medium))
                    }
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 7) {
                Circle().fill(workspace.dirty ? Color.orange : Color.secondary.opacity(0.5)).frame(width: 5, height: 5)
                Text(workspace.project == nil ? "Projects stay on your Mac" : workspace.dirty ? "Unsaved changes" : "All changes saved")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(18).frame(maxHeight: .infinity)
    }

    private func mediaCard(_ project: Project) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                Rectangle().fill(Studio.stage)
                    .overlay {
                        if let image = workspace.thumbnails.first { Image(nsImage: image).resizable().scaledToFit() }
                        else { Image(systemName: "film").foregroundStyle(.white.opacity(0.5)) }
                    }
                Text(timecode(project.sourceDuration)).font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.white).padding(5).background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 4)).padding(6)
            }.aspectRatio(16 / 9, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 8))
            Text(project.title).font(.callout.weight(.medium)).lineLimit(2)
            Text("Original take · \(project.sourceWidth) × \(project.sourceHeight)").font(.caption2).foregroundStyle(.secondary)
        }.padding(9)
            .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(Color.accentColor.opacity(0.35)))
    }

    private var captureControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !workspace.windows.isEmpty {
                Picker("Window", selection: $workspace.selectedWindowID) {
                    ForEach(workspace.windows) { window in Text(window.title).tag(Optional(window.id)) }
                }.labelsHidden().accessibilityLabel("Window to record")
            } else {
                Text("Choose an open app window to start a new take.").font(.caption).foregroundStyle(.secondary)
            }
            Button("Refresh Windows", systemImage: "arrow.clockwise") { workspace.refreshWindows() }
                .disabled(workspace.busy || workspace.recording || workspace.exporting)
            Toggle("System audio", isOn: $workspace.systemAudio)
            Toggle("Microphone", isOn: $workspace.microphone)
            Button(workspace.recording ? "Stop Recording" : "Start Recording", systemImage: workspace.recording ? "stop.fill" : "record.circle") {
                if workspace.recording { workspace.stopRecording() } else { workspace.startRecording() }
            }.buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(workspace.busy || workspace.exporting || (!workspace.recording && workspace.selectedWindowID == nil))
                .keyboardShortcut("r", modifiers: [.command, .shift])
        }.font(.callout)
    }

    private func preview(_ project: Project) -> some View {
        VStack(spacing: 0) {
            HStack {
                Label("Preview", systemImage: "play.rectangle").font(.caption.weight(.medium))
                Spacer()
                Text("16:9").font(.system(.caption, design: .monospaced))
            }.foregroundStyle(.white.opacity(0.6)).padding(.horizontal, 24).padding(.top, 18)
            GeometryReader { geometry in
                let width = max(1, min(geometry.size.width - 56, (geometry.size.height - 40) * 16 / 9))
                NativePlayer(player: workspace.player)
                    .frame(width: width, height: width * 9 / 16)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.white.opacity(0.12)))
                    .shadow(color: .black.opacity(0.4), radius: 22, y: 12)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    .accessibilityLabel("Edited video preview")
            }
            HStack(spacing: 6) {
                Circle().fill(.white.opacity(0.35)).frame(width: 4, height: 4)
                Text("\(project.background.title) · \(Int((project.padding * 100).rounded()))% padding")
            }.font(.caption2).foregroundStyle(.white.opacity(0.45)).padding(.bottom, 15)
        }.frame(minHeight: 260).background(Studio.stage)
    }

    private var welcome: some View {
        VStack(spacing: 24) {
            ZStack {
                RoundedRectangle(cornerRadius: 24).fill(CanvasBackground.dawn.gradient).frame(width: 220, height: 138)
                RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.92)).frame(width: 162, height: 96)
                    .rotationEffect(.degrees(-5)).shadow(color: .black.opacity(0.15), radius: 12, y: 8)
                Image(systemName: "play.fill").font(.largeTitle).foregroundStyle(Color(red: 0.4, green: 0.32, blue: 0.55))
            }.accessibilityHidden(true)
            VStack(spacing: 8) {
                Text("One take. A great demo.").font(.largeTitle.weight(.semibold))
                Text("Bring your recording. Find the story. Make it shine.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Button("Import Video…", systemImage: "plus") { workspace.importVideo() }.buttonStyle(.borderedProminent)
                Button("Open Project…") { workspace.openProject() }
            }.controlSize(.large)
            Text("MOV or MP4 · Up to 10 minutes").font(.caption).foregroundStyle(.tertiary)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(24)
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Make it yours").font(.headline)
                Spacer()
                Image(systemName: "slider.horizontal.3").foregroundStyle(.secondary)
            }.padding(.top, 8)
            Picker("Inspector section", selection: $inspectorTab) {
                ForEach(InspectorTab.allCases, id: \.self) { tab in Text(tab.rawValue).tag(tab) }
            }.pickerStyle(.segmented).labelsHidden()
            if let project = workspace.project {
                ScrollView {
                    VStack(spacing: 14) {
                        if inspectorTab == .style { styleControls(project) }
                        else { editControls(project) }
                    }.padding(.bottom, 8)
                }.disabled(!workspace.canEdit)
            } else {
                Text("Choose a recording to adjust its canvas, pacing and focus.")
                    .font(.callout).foregroundStyle(.secondary).padding(.top, 8)
                Spacer()
            }
        }.padding(16).background(Studio.panel)
    }

    @ViewBuilder private func styleControls(_ project: Project) -> some View {
        PanelCard(title: "Background", icon: "square.on.square") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(CanvasBackground.allCases, id: \.self) { preset in
                    BackgroundSwatch(preset: preset, selected: project.background == preset) {
                        var next = project; next.background = preset; workspace.edit(next, name: "Change Background")
                    }
                }
            }
        }
        PanelCard(title: "Framing", icon: "arrow.up.left.and.arrow.down.right") {
            HStack {
                Text("Padding").font(.callout)
                Spacer()
                Text("\(Int((padding * 100).rounded()))%").font(.system(.callout, design: .monospaced)).foregroundStyle(.secondary)
            }
            Slider(value: $padding, in: 0...0.2, step: 0.01) { editing in
                if !editing { var next = project; next.padding = padding; workspace.edit(next, name: "Change Padding") }
            }.accessibilityLabel("Canvas padding")
            HStack { Text("Edge to edge"); Spacer(); Text("Room to breathe") }.font(.caption2).foregroundStyle(.secondary)
        }
        PanelCard(title: "Output", icon: "rectangle") {
            HStack { Text("Landscape"); Spacer(); DetailBadge(text: "16:9") }.font(.callout)
            Divider()
            HStack { Text("Resolution"); Spacer(); Text("1080p / 4K").foregroundStyle(.secondary) }.font(.caption)
            HStack { Text("Frame rate"); Spacer(); Text("30 fps").foregroundStyle(.secondary) }.font(.caption)
            Text("Choose a resolution in Export.").font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func editControls(_ project: Project) -> some View {
        ZoomInspector(workspace: workspace, project: project)
        PanelCard(title: "Remove a pause", icon: "scissors") {
            HStack(spacing: 10) {
                timeInput("Start", value: $cutStart)
                timeInput("End", value: $cutEnd)
            }
            Button { workspace.cut(start: cutStart, end: cutEnd) } label: {
                Label("Remove Interval", systemImage: "scissors").frame(maxWidth: .infinity)
            }.controlSize(.large)
            if !project.cuts.isEmpty {
                Divider()
                ForEach(project.cuts) { cut in
                    HStack {
                        Text("\(timecode(cut.start)) – \(timecode(cut.end))").font(.system(.caption, design: .monospaced))
                        Spacer()
                        Button("Restore", systemImage: "arrow.uturn.backward") {
                            var next = project; next.cuts.removeAll { $0.id == cut.id }; workspace.edit(next, name: "Restore Interval")
                        }.labelStyle(.iconOnly).buttonStyle(.borderless)
                            .accessibilityLabel("Restore interval \(cut.start) to \(cut.end) seconds").help("Restore this interval")
                    }
                }
            }
            Text("Times refer to the original take.").font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func timeInput(_ label: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(label, value: value, format: .number.precision(.fractionLength(0...2)))
                .textFieldStyle(.roundedBorder).monospacedDigit().accessibilityLabel("\(label) source seconds")
        }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            if workspace.busy { ProgressView().controlSize(.mini) }
            else { Image(systemName: workspace.recording ? "record.circle.fill" : "checkmark.circle").foregroundStyle(workspace.recording ? Color.red : Color.secondary) }
            Text(workspace.status).font(.caption).foregroundStyle(.secondary).lineLimit(1).help(workspace.status)
            Spacer(minLength: 8)
            if workspace.exporting {
                ProgressView(value: workspace.exportProgress).frame(width: 90)
                Button("Cancel") { workspace.cancelExport() }.controlSize(.small)
            }
        }.padding(.horizontal, 20).padding(.vertical, 10).background(Studio.panel)
    }
}

/// Use the AppKit player directly; its native controls also fit a desktop editor better.
struct NativePlayer: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none
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
