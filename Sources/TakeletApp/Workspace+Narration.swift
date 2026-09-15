import Foundation
@preconcurrency import AVFoundation
import ProjectCore
import NarrationCore

extension Workspace {
    var selectedNarration: NarrationSegment? { project?.narrations.first { $0.id == selectedNarrationID } }

    func addNarration() {
        guard canEdit, var next = project else { return }
        let position = sourcePosition
        if let existing = next.narrations.first(where: { $0.start <= position && position < $0.end }) {
            selectNarration(existing.id); return
        }
        guard next.narrations.count < NarrationSegment.maximumCount,
              let retained = next.retainedRanges.first(where: { $0.end > position }) else { return }
        let start = max(position, retained.start)
        let nextStart = next.narrations.filter { $0.start > start }.map(\.start).min() ?? next.sourceDuration
        let end = min(start + 5, retained.end, nextStart)
        guard end - start >= 1.0 / 30 else { status = "Choose a longer uncut interval for narration."; return }
        let settings = ElevenLabsSettings.shared
        let voiceName = settings.voices.first { $0.voiceID == settings.defaultVoiceID }?.name ?? ""
        let language = settings.defaultLanguage.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let segment = NarrationSegment(start: start, end: end, voiceID: settings.defaultVoiceID,
                                       voiceName: voiceName, modelID: language.isEmpty ? NarrationSegment.defaultModelID : "eleven_flash_v2_5",
                                       languageCode: language.isEmpty ? nil : language)
        next.narrations.append(segment); next.narrations.sort { $0.start < $1.start }
        if edit(next, name: "Add Narration") {
            selectedNarrationID = segment.id
            status = "Write a script and choose a voice in Narration. Generate when it is ready."
        }
    }

    func selectNarration(_ id: UUID) {
        guard canEdit, let segment = project?.narrations.first(where: { $0.id == id }) else { return }
        selectedNarrationID = id
        player.pause(); isPlaying = false; seekSource(segment.start)
    }

    @discardableResult func updateNarration(_ segment: NarrationSegment) -> Bool {
        guard canEdit, var next = project,
              let index = next.narrations.firstIndex(where: { $0.id == segment.id }) else { return false }
        next.narrations[index] = Self.revisedNarration(segment, previous: next.narrations[index])
        next.narrations.sort { $0.start < $1.start }
        if next != project, !edit(next, name: "Edit Narration") { return false }
        narrationDrafts.removeValue(forKey: segment.id)
        return true
    }

    static func revisedNarration(_ segment: NarrationSegment, previous: NarrationSegment) -> NarrationSegment {
        var updated = segment
        // Audio belongs to its exact script and synthesis settings. Timing edits can reuse it.
        if previous.script != segment.script || previous.voiceID != segment.voiceID ||
            previous.modelID != segment.modelID || previous.languageCode != segment.languageCode {
            updated.audioFile = nil; updated.audioDuration = nil
        } else {
            updated.audioFile = previous.audioFile; updated.audioDuration = previous.audioDuration
        }
        return updated
    }

    func removeNarration(_ id: UUID) {
        guard canEdit, var next = project else { return }
        next.narrations.removeAll { $0.id == id }
        edit(next, name: "Remove Narration")
    }

    func updateAudioMix(source: Double, narration: Double) {
        guard canEdit, var next = project else { return }
        next.sourceAudioVolume = source; next.narrationVolume = narration
        edit(next, name: "Change Audio Mix")
    }

    func previewNarration(_ id: UUID) {
        guard canEdit, applyInspectorDrafts(),
              let placement = try? project?.makeTimeline().narrations.first(where: { $0.id == id }) else { return }
        seek(placement.outputStart); player.play(); isPlaying = true
    }

    func generateNarration(_ id: UUID, service suppliedService: (any NarrationService)? = nil) {
        guard canEdit, applyInspectorDrafts(), let snapshot = project,
              let segment = snapshot.narrations.first(where: { $0.id == id }) else { return }
        do {
            let request = SpeechRequest(text: segment.script, voiceID: segment.voiceID,
                                        modelID: segment.modelID, languageCode: segment.languageCode)
            try request.validate()
            // Reject wholly cut/frameless intervals before spending provider credits.
            var preflight = snapshot
            let index = preflight.narrations.firstIndex { $0.id == id }!
            preflight.narrations[index].audioFile = "media/narration/\(UUID().uuidString).mp3"
            preflight.narrations[index].audioDuration = 0.01
            try preflight.validate()
            let service = try suppliedService ?? ElevenLabsSettings.shared.service()
            let originalSource = sourceURL
            generatingNarrationID = id; player.pause(); isPlaying = false
            status = "Generating narration with ElevenLabs…"
            narrationTask = Task { [weak self] in
                guard let self else { return }
                var stagedPath: String?
                var installed = false
                defer {
                    if !installed, let stagedPath, let url = assetURLs.removeValue(forKey: stagedPath) {
                        try? FileManager.default.removeItem(at: url)
                    }
                    generatingNarrationID = nil; narrationTask = nil
                }
                do {
                    let audio = try await service.synthesize(request)
                    try Task.checkCancellation()
                    let path = "media/narration/\(UUID().uuidString).mp3"
                    try stageAsset(audio.data, path: path); stagedPath = path
                    let asset = AVURLAsset(url: assetURLs[path]!)
                    let duration = try await asset.load(.duration).seconds
                    let tracks = try await asset.loadTracks(withMediaType: .audio)
                    guard duration.isFinite, duration > 0, duration <= NarrationSegment.maximumAudioDuration,
                          let track = tracks.first else { throw ProjectError("ElevenLabs returned audio that cannot be played.") }
                    let range = try await track.load(.timeRange)
                    guard range.duration.seconds >= duration - 0.1 else { throw ProjectError("The narration audio is incomplete.") }
                    try Task.checkCancellation()
                    // Undo may run during an asynchronous request; never overwrite intervening edits.
                    guard project == snapshot, sourceURL == originalSource else {
                        status = "The project changed during generation. The returned audio was not applied."; return
                    }
                    var next = snapshot
                    next.narrations[index].audioFile = path; next.narrations[index].audioDuration = duration
                    try next.validate()
                    installed = edit(next, name: segment.audioFile == nil ? "Generate Narration" : "Regenerate Narration")
                    if installed {
                        selectedNarrationID = id
                        status = "Narration ready (\(String(format: "%.1f", duration)) s). Preview the timing before export."
                    }
                } catch is CancellationError {
                    status = "Generation cancelled. ElevenLabs may have already processed the request."
                } catch {
                    if Task.isCancelled { status = "Generation cancelled. ElevenLabs may have already processed the request." }
                    else { self.error = error.localizedDescription; status = "Narration was not changed. Generation was not retried." }
                }
            }
        } catch { self.error = error.localizedDescription }
    }

    func cancelNarration() {
        narrationTask?.cancel()
        status = "Cancelling narration…"
    }
}
