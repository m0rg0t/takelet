import SwiftUI

@main struct TakeletApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @AppStorage("appearance") private var appearance = "system"
    private var colorScheme: ColorScheme? { appearance == "dark" ? .dark : appearance == "light" ? .light : nil }
    var body: some Scene {
        WindowGroup { EditorView().preferredColorScheme(colorScheme) }
            .defaultSize(width: 1280, height: 820)
            .windowToolbarStyle(.unified)
            .commands { TakeletCommands() }
        Settings {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $appearance) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                }
                ElevenLabsSettingsView(settings: .shared)
                Section("Takelet Developer Preview") {
                    Text("Recordings and projects are saved on your Mac.")
                    Text("The optional Codex analyzer is currently a separate command-line tool.").foregroundStyle(.secondary)
                }
            }.formStyle(.grouped).frame(width: 540, height: 620).preferredColorScheme(colorScheme)
        }
    }
}

struct TakeletCommands: Commands {
    @FocusedValue(\.workspace) private var workspace
    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Open Project…") { workspace?.openProject() }.keyboardShortcut("o").disabled(workspace == nil)
            Button("Import Video…") { workspace?.importVideo() }.keyboardShortcut("i").disabled(workspace == nil)
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save Project") { workspace?.saveProject() }.keyboardShortcut("s").disabled(workspace?.canEdit != true)
            Button("Export 1080p…") { workspace?.exportVideo(width: 1920) }.keyboardShortcut("e").disabled(workspace?.canEdit != true)
            Button("Export 4K…") { workspace?.exportVideo(width: 3840) }.keyboardShortcut("e", modifiers: [.command, .shift]).disabled(workspace?.canEdit != true)
        }
        CommandMenu("Recording") {
            Button("Refresh Windows") { workspace?.refreshWindows() }.keyboardShortcut("r", modifiers: [.command, .option])
            Button(workspace?.recording == true ? "Stop Recording" : "Start Recording") {
                if workspace?.recording == true { workspace?.stopRecording() } else { workspace?.startRecording() }
            }.keyboardShortcut("r", modifiers: [.command, .shift]).disabled(workspace?.busy == true || workspace?.exporting == true)
        }
        CommandMenu("Zoom") {
            Button("Add Zoom at Playhead") { workspace?.addZoom() }
                .keyboardShortcut("z", modifiers: [.command, .option]).disabled(workspace?.canEdit != true)
            Button("Auto Zoom from Clicks") { workspace?.generateClickZooms() }
                .keyboardShortcut("z", modifiers: [.command, .option, .shift])
                .disabled(workspace?.canEdit != true || workspace?.project?.cursor.isEmpty != false)
            Divider()
            Button("Remove Selected Zoom") {
                if let id = workspace?.selectedZoomID { workspace?.removeZoom(id) }
            }.keyboardShortcut(.delete, modifiers: [.command])
                .disabled(workspace?.canEdit != true || workspace?.selectedZoom == nil)
        }
        CommandMenu("Narration") {
            Button("Add Narration at Playhead") { workspace?.addNarration() }
                .keyboardShortcut("n", modifiers: [.command, .option]).disabled(workspace?.canEdit != true)
            Button("Generate Selected Narration") {
                if let id = workspace?.selectedNarrationID { workspace?.generateNarration(id) }
            }.keyboardShortcut("g", modifiers: [.command, .option])
                .disabled(workspace?.canEdit != true || workspace?.selectedNarration == nil)
            Button("Cancel Generation") { workspace?.cancelNarration() }
                .keyboardShortcut(".", modifiers: [.command]).disabled(workspace?.generatingNarrationID == nil)
            Divider()
            Button("Remove Selected Narration") {
                if let id = workspace?.selectedNarrationID { workspace?.removeNarration(id) }
            }.keyboardShortcut(.delete, modifiers: [.command, .option])
                .disabled(workspace?.canEdit != true || workspace?.selectedNarration == nil)
        }
        CommandMenu("Markup") {
            Button("Add Arrow") { workspace?.addAnnotation(.arrow) }
                .keyboardShortcut("a", modifiers: [.command, .option]).disabled(workspace?.canEdit != true)
            Button("Add Frame") { workspace?.addAnnotation(.frame) }.disabled(workspace?.canEdit != true)
            Button("Add Text") { workspace?.addAnnotation(.text) }.disabled(workspace?.canEdit != true)
            Divider()
            Button("Add Blur Mask") { workspace?.addAnnotation(.blur) }.disabled(workspace?.canEdit != true)
            Button("Add Opaque Mask") { workspace?.addAnnotation(.cover) }
                .keyboardShortcut("k", modifiers: [.command, .option]).disabled(workspace?.canEdit != true)
            Divider()
            Button("Duplicate Selected Annotation") {
                if let id = workspace?.selectedAnnotationID { workspace?.duplicateAnnotation(id) }
            }.disabled(workspace?.canEdit != true || workspace?.selectedAnnotation == nil)
            Button("Remove Selected Annotation") {
                if let id = workspace?.selectedAnnotationID { workspace?.removeAnnotation(id) }
            }.disabled(workspace?.canEdit != true || workspace?.selectedAnnotation == nil)
        }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) { NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { WorkspaceRegistry.shared.canQuit() ? .terminateNow : .terminateCancel }
}
