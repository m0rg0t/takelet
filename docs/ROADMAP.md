# Roadmap

## Product goal

Make a clear one-to-five-minute product walkthrough from a single manually recorded take. The first release targets Apple Silicon Macs on macOS 15+, with source recordings up to ten minutes. Local recording and manual editing must remain useful without an AI provider.

## First-release scope

| Area | Target behavior |
| --- | --- |
| Capture | One window, rectangular area, or full display; optional microphone and system audio |
| Editing | Reversible cuts, editable zooms and cursor, simple timeline, undo, autosave and recovery |
| Narration | Live microphone narration or ElevenLabs using the user's API key |
| Script | User-written or generated from selected visual evidence; editable before synthesis |
| Analysis | OpenAI-compatible vision endpoint; optional local Codex connection |
| Pacing | Explicit holds between actions when generated narration needs more time |
| Language | English, Russian, or a custom target language supported by the selected provider |
| Presentation | Tutorial, Product Demo and Internal Walkthrough presets; titles, branding and callouts |
| Output | MP4, 1080p and up to 4K at 30 fps; 16:9, 9:16 and 1:1 with explicit framing |
| Storage | Portable local projects; per-user credentials kept outside projects |

Combining multiple recordings, 3D presentation, team cloud workspaces, Intel support, 60 fps, and hour-long editing are outside this first release.

## Milestones

### M0a — Native media foundation · in progress

Implemented: native app shell, window recorder, portable project, reversible source cuts, one zoom interval, preview and MP4 export. Synthetic save/reopen and 1080p/4K media checks pass.

Exit: record a real browser workflow with cursor and audio, save/reopen it, verify edits in the native player, and compare exported pictures and audio. Screen permissions, moving windows and capture interruption must be exercised. Current synthetic checks cover only part of this exit condition.

### M0b — Analysis feasibility · in progress

Implemented: native frame preparation and a Codex app-server client. A small live experiment confirmed image input, structured results, shared-limit reporting and cancellation. A controlled inserted hold was identified while an annotated protected ending was kept.

Exit: benchmark suggestions on representative recordings, measure missed actions and unsafe cuts, validate an OpenAI-compatible endpoint, and establish acceptable latency and usage. Sparse-frame analysis alone cannot establish safe boundaries.

### M1 — Reliable single-recording editor

Add display/area capture, independent cursor rendering, multiple zoom intervals, timeline interaction, autosave, recovery and richer document handling. Verify Retina/multiple-display geometry, undo/redo, missing assets and ten-minute playback.

### M2 — Narration and pacing

Build provider settings, script review, language/audience controls, ElevenLabs segment generation and retakes. Measure generated audio and insert explicit freeze-frame holds between actions. Recompute downstream timing together. Protect live narration from automatic cuts.

### M3 — Presentation and layouts

Add portrait/square framing, editable backgrounds, titles, logo/color presets, callouts and manual masks. Changing aspect ratio must preserve proportions and allow framing review. A redacted export does not redact the originals in its project package.

### M4 — Pilot and distribution

Exercise long capture, interruptions, disk-full, provider errors, cancellation, privacy controls and accessibility. Measure dropped frames, memory and audio drift. Prepare signed/notarized builds and a release/update process.

## Acceptance example

Record a new browser-editor feature. Restore or accept suggested cuts, adjust zoom, review a script, create narration, correct pacing with holds, and export a 4K/30 landscape walkthrough. Produce portrait and square versions with a framing review. Reopen the portable project on another supported Mac and continue editing.

This is the release target, not a description of the current preview. Re-estimate delivery after the media and analysis proofs are complete.
