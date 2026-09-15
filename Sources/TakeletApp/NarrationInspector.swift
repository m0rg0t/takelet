import SwiftUI
import ProjectCore
import NarrationCore

struct NarrationInspector: View {
    @ObservedObject var workspace: Workspace
    @ObservedObject private var settings = ElevenLabsSettings.shared
    let project: Project
    private var draft: NarrationSegment? {
        get {
            guard let id = workspace.selectedNarrationID else { return nil }
            return workspace.narrationDrafts[id] ?? workspace.selectedNarration
        }
        nonmutating set { if let newValue { workspace.narrationDrafts[newValue.id] = newValue } }
    }
    @State private var sourceVolume = 1.0
    @State private var voiceVolume = 1.0

    var body: some View {
        PanelCard(title: "Voiceover", icon: "waveform") {
            Button("Add Narration at Playhead", systemImage: "plus") { workspace.addNarration() }
                .frame(maxWidth: .infinity).controlSize(.large)
            if !project.narrations.isEmpty {
                Picker("Segment", selection: Binding(get: { workspace.selectedNarrationID }, set: { if let id = $0 { workspace.selectNarration(id) } })) {
                    Text("Choose a segment").tag(nil as UUID?)
                    ForEach(project.narrations) { segment in
                        Text("\(timecode(segment.start)) · \(segment.script.isEmpty ? "New narration" : String(segment.script.prefix(28)))")
                            .tag(Optional(segment.id))
                    }
                }
            }
            if draft != nil { segmentControls }
            else { Text("Add a source interval, write its script, then generate a voiceover.").font(.caption).foregroundStyle(.secondary) }
        }
        PanelCard(title: "Audio mix", icon: "speaker.wave.2") {
            volumeSlider("Original audio", value: $sourceVolume)
            volumeSlider("Narration", value: $voiceVolume)
            Text("Longer narration holds the last retained frame; the original audio is silent during the hold.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onChange(of: project.sourceAudioVolume, initial: true) { _, value in sourceVolume = value }
        .onChange(of: project.narrationVolume, initial: true) { _, value in voiceVolume = value }
    }

    @ViewBuilder private var segmentControls: some View {
        if let segment = draft {
            HStack {
                timeField("Start", keyPath: \.start)
                timeField("End", keyPath: \.end)
            }
            Text("Source seconds · intervals cannot overlap").font(.caption2).foregroundStyle(.secondary)
            TextEditor(text: field(\.script, fallback: ""))
                .font(.body).frame(minHeight: 115, maxHeight: 220)
                .padding(5).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 6))
                .accessibilityLabel("Narration script")
            Text("\(segment.script.count) characters").font(.caption2).foregroundStyle(.secondary)
            if !settings.voices.isEmpty {
                Picker("Voice", selection: Binding(get: { draft?.voiceID ?? "" }, set: { id in
                    draft?.voiceID = id; draft?.voiceName = settings.voices.first { $0.voiceID == id }?.name ?? ""
                })) {
                    if !settings.voices.contains(where: { $0.voiceID == segment.voiceID }) {
                        Text(segment.voiceID.isEmpty ? "Choose a voice" : segment.voiceName.isEmpty ? segment.voiceID : segment.voiceName).tag(segment.voiceID)
                    }
                    ForEach(settings.voices) { voice in Text(voice.name).tag(voice.voiceID) }
                }
            }
            TextField("Voice ID", text: Binding(get: { draft?.voiceID ?? "" }, set: { id in
                draft?.voiceID = id; draft?.voiceName = settings.voices.first { $0.voiceID == id }?.name ?? ""
            }))
                .textFieldStyle(.roundedBorder)
            HStack {
                SettingsLink { Text("API key & voices…") }
                Spacer()
                if settings.loadingVoices {
                    ProgressView().controlSize(.small)
                    Button("Cancel") { settings.cancelVoiceLoading() }.buttonStyle(.borderless)
                }
                else { Button("Refresh Voices") { settings.loadVoices() }.buttonStyle(.borderless) }
            }.font(.caption)
            if let message = settings.message { Text(message).font(.caption2).foregroundStyle(.secondary) }
            Picker("Model", selection: Binding(get: { draft?.modelID ?? NarrationSegment.defaultModelID }, set: {
                draft?.modelID = $0
                if $0 == "eleven_multilingual_v2" { draft?.languageCode = nil }
            })) {
                Text("Multilingual v2").tag("eleven_multilingual_v2")
                Text("Flash v2.5").tag("eleven_flash_v2_5")
                if !["eleven_multilingual_v2", "eleven_flash_v2_5"].contains(segment.modelID) { Text(segment.modelID).tag(segment.modelID) }
            }
            TextField("Language", text: Binding(get: { draft?.languageCode ?? "" }, set: {
                let value = $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                draft?.languageCode = value.isEmpty ? nil : value
            }), prompt: Text("Auto, or en / ru / ISO code"))
                .textFieldStyle(.roundedBorder).disabled(segment.modelID == "eleven_multilingual_v2")
            Text(segment.modelID == "eleven_multilingual_v2"
                 ? "Multilingual v2 detects language automatically. Choose Flash v2.5 to set a language."
                 : "Leave language empty for automatic detection, or enter a two-letter ISO code.")
                .font(.caption2).foregroundStyle(.secondary)
            Button("Save Script & Settings") { if let draft { workspace.updateNarration(draft) } }
                .disabled(segment == workspace.selectedNarration)
            if let audioDuration = workspace.selectedNarration?.audioDuration {
                let placement = try? project.makeTimeline().narrations.first { $0.id == segment.id }
                let held = max(0, audioDuration - (placement?.retainedSourceDuration ?? segment.duration))
                Text("Audio: \(audioDuration, specifier: "%.1f") s · added hold: \(held, specifier: "%.1f") s")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Preview Voiceover", systemImage: "play.fill") { workspace.previewNarration(segment.id) }
                    .disabled(workspace.selectedNarration.map { Workspace.revisedNarration(segment, previous: $0).audioFile == nil } ?? true)
            }
            Button {
                workspace.generateNarration(segment.id)
            } label: {
                Label(workspace.selectedNarration?.audioFile == nil ? "Generate with ElevenLabs" : "Regenerate with ElevenLabs", systemImage: "waveform")
                    .frame(maxWidth: .infinity)
            }.buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(segment.script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || segment.voiceID.isEmpty)
            Text("Generation sends this script to ElevenLabs and uses your account’s credits. Changing text, voice or language requires a new generation.")
                .font(.caption2).foregroundStyle(.secondary)
            Button("Remove Narration", role: .destructive) { workspace.removeNarration(segment.id) }
                .buttonStyle(.borderless).font(.caption)
        }
    }

    private func field<T>(_ keyPath: WritableKeyPath<NarrationSegment, T>, fallback: T) -> Binding<T> {
        Binding(get: { draft?[keyPath: keyPath] ?? fallback }, set: { draft?[keyPath: keyPath] = $0 })
    }
    private func timeField(_ label: String, keyPath: WritableKeyPath<NarrationSegment, Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(label, value: field(keyPath, fallback: 0), format: .number.precision(.fractionLength(0...2)))
                .textFieldStyle(.roundedBorder).accessibilityLabel("Narration \(label.lowercased()) source seconds")
        }
    }
    private func volumeSlider(_ title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack { Text(title); Spacer(); Text("\(Int((value.wrappedValue * 100).rounded()))%") }.font(.caption)
            Slider(value: value, in: 0...1, step: 0.05) { editing in
                if !editing { workspace.updateAudioMix(source: sourceVolume, narration: voiceVolume) }
            }.accessibilityLabel(title)
        }
    }
}
