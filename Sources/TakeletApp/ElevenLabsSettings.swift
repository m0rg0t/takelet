import SwiftUI
import NarrationCore

@MainActor final class ElevenLabsSettings: ObservableObject {
    static let shared = ElevenLabsSettings()
    @Published var apiKeyDraft = ""
    @Published private(set) var hasKey = false
    @Published private(set) var voices: [Voice] = []
    @Published private(set) var loadingVoices = false
    @Published var message: String?
    @Published var defaultVoiceID: String { didSet { defaults.set(defaultVoiceID, forKey: "elevenlabs.voiceID") } }
    @Published var defaultLanguage: String { didSet { defaults.set(defaultLanguage, forKey: "elevenlabs.language") } }
    private let keyStore: any APIKeyStore
    private let defaults: UserDefaults
    private var voicesTask: Task<Void, Never>?
    private var requestID = UUID()

    init(keyStore: any APIKeyStore = KeychainAPIKeyStore(), defaults: UserDefaults = .standard) {
        self.keyStore = keyStore; self.defaults = defaults
        defaultVoiceID = defaults.string(forKey: "elevenlabs.voiceID") ?? ""
        defaultLanguage = defaults.string(forKey: "elevenlabs.language") ?? ""
    }

    func refreshCredentialStatus() {
        do { hasKey = try keyStore.read()?.isEmpty == false }
        catch { hasKey = false; message = error.localizedDescription }
    }

    func saveKey() {
        do {
            try keyStore.save(apiKeyDraft); apiKeyDraft = ""; hasKey = true
            cancelVoiceLoading(); voices = []
            message = "Key saved in macOS Keychain. Load voices to verify the connection."
        } catch { message = error.localizedDescription }
    }

    func removeKey() {
        do {
            try keyStore.delete(); apiKeyDraft = ""; hasKey = false
            cancelVoiceLoading(); voices = []; message = "ElevenLabs key removed. Local editing is still available."
        } catch { message = error.localizedDescription }
    }

    func service() throws -> any NarrationService {
        guard let key = try keyStore.read(), !key.isEmpty else { throw ElevenLabsError.missingAPIKey }
        return ElevenLabsClient(apiKey: key)
    }

    func loadVoices() {
        guard !loadingVoices else { return }
        do {
            let client = try service()
            let request = UUID(); requestID = request; loadingVoices = true; message = nil
            voicesTask = Task {
                defer { if requestID == request { loadingVoices = false; voicesTask = nil } }
                do {
                    var loaded: [Voice] = []; var token: String?; var tokens = Set<String>(); var complete = false
                    for _ in 0..<100 {
                        try Task.checkCancellation()
                        let page = try await client.listVoices(pageSize: 100, nextPageToken: token)
                        loaded.append(contentsOf: page.voices)
                        if !page.hasMore { complete = true; break }
                        guard let next = page.nextPageToken, tokens.insert(next).inserted else {
                            throw ElevenLabsError.malformedResponse("The voice list repeated a page. Try loading it again.")
                        }
                        token = next
                    }
                    guard complete else { throw ElevenLabsError.malformedResponse("This account has more than 10,000 voices. Enter the desired voice ID directly.") }
                    try Task.checkCancellation(); guard requestID == request else { return }
                    var ids = Set<String>()
                    voices = loaded.filter { ids.insert($0.id).inserted }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                    if defaultVoiceID.isEmpty { defaultVoiceID = voices.first?.id ?? "" }
                    hasKey = true; message = "Connected. \(voices.count) voices available."
                } catch is CancellationError { if requestID == request { message = "Voice loading cancelled." } }
                catch { if requestID == request { message = error.localizedDescription } }
            }
        } catch { message = error.localizedDescription }
    }

    func cancelVoiceLoading() {
        requestID = UUID(); voicesTask?.cancel(); voicesTask = nil; loadingVoices = false
    }
}

struct ElevenLabsSettingsView: View {
    @ObservedObject var settings: ElevenLabsSettings

    var body: some View {
        Section("ElevenLabs") {
            SecureField(settings.hasKey ? "Replace API key" : "API key", text: $settings.apiKeyDraft)
                .textContentType(.password)
            HStack {
                Button("Save Key") { settings.saveKey() }.disabled(settings.apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Remove Key", role: .destructive) { settings.removeKey() }.disabled(!settings.hasKey)
                Spacer()
                Label(settings.hasKey ? "Stored in Keychain" : "No key saved", systemImage: settings.hasKey ? "lock.fill" : "key")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("Load Voices") { settings.loadVoices() }.disabled(!settings.hasKey || settings.loadingVoices)
                if settings.loadingVoices {
                    ProgressView().controlSize(.small)
                    Button("Cancel") { settings.cancelVoiceLoading() }
                }
            }
            if !settings.voices.isEmpty {
                Picker("Default voice", selection: $settings.defaultVoiceID) {
                    if !settings.voices.contains(where: { $0.id == settings.defaultVoiceID }) {
                        Text(settings.defaultVoiceID.isEmpty ? "Choose a voice" : settings.defaultVoiceID).tag(settings.defaultVoiceID)
                    }
                    ForEach(settings.voices) { Text($0.name).tag($0.id) }
                }
            }
            TextField("Default voice ID", text: $settings.defaultVoiceID)
                .help("You can paste a voice ID from your ElevenLabs account if it is not listed.")
            TextField("Default language", text: $settings.defaultLanguage, prompt: Text("Auto, or en / ru / another ISO code"))
            Text("An explicit default language selects Flash v2.5 for new segments. An empty language uses Multilingual v2 with automatic detection.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Only the script and voice settings are sent when you choose Generate. ElevenLabs usage is billed to your account. Video and cursor images stay on your Mac.")
                .font(.caption).foregroundStyle(.secondary)
            if let message = settings.message { Text(message).font(.caption).textSelection(.enabled) }
        }.onAppear { settings.refreshCredentialStatus() }
    }
}
