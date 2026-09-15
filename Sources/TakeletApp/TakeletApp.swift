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
                Section("Takelet Developer Preview") {
                    Text("Recordings and projects are saved on your Mac.")
                    Text("The optional Codex analyzer is currently a separate command-line tool. AI connections and narration settings will appear here in a later build.").foregroundStyle(.secondary)
                }
            }.formStyle(.grouped).frame(width: 460, height: 300).preferredColorScheme(colorScheme)
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
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) { NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { WorkspaceRegistry.shared.canQuit() ? .terminateNow : .terminateCancel }
}
