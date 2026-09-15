# Custom cursors and ElevenLabs — implementation and acceptance

This work targets the source build after 0.1.0. The published 0.1.0 DMG does not
contain these features. Completion requires the application workflow, portable
storage and rendered output to agree; a provider client alone is insufficient.

## Cursor workflow

- New Takelet recordings capture the video without its system cursor and record
  cursor samples separately. Existing recordings/imports keep their embedded cursor.
- Choose arrow, circle, crosshair, or an imported PNG; adjust size, color,
  smoothing, visibility, click highlight and the custom image's hotspot.
- Imported PNGs are copied into the portable project. Undo/Redo restores edits.
- Pending cursor and script controls survive inspector/segment switching, mark the
  window as edited, and are validated and committed by Save Project. Both generation
  entry points use the visible draft. PNG import preserves other pending cursor controls.
- Source-time cursor positions stay aligned through cuts, zooms and narration holds.
- Preview and export use the same cursor renderer. Embedded-cursor footage never
  receives a duplicate cursor layer.

## Narration workflow

- Save/remove a personal ElevenLabs key in macOS Keychain. No key belongs in a
  project, repository, ordinary preferences, generated file, or diagnostic log.
- Fetch available voices, select a voice and language, edit a script, and explicitly
  generate narration for a source interval. Generation sends the script to ElevenLabs
  and uses that account's provider credits. Local editing remains available without a key.
- Cancel generation; surface invalid keys, quota/rate limits and provider errors.
  An uncertain synthesis request must not be retried automatically.
- Keep generated audio as an immutable project asset. Regenerate a segment, remove
  it, or restore it using Undo/Redo. Changed script/settings must not masquerade as
  already generated speech.
- Measure actual audio duration. Longer narration adds a frozen frame after the
  segment; downstream video, cursor, zooms and audio share the same time mapping.
  Shorter narration leaves the remaining video time intact.
- Control source and narration volume independently. Hear the same mix in preview
  and exported MP4. Save/reopen/move a project without losing generated audio.

## Verification

- Unit tests: cursor interpolation, smoothing, click timing, validation, schema
  migration, asset paths/storage, narration timing, edits and undo/redo.
- Mock HTTP tests: ElevenLabs request/response contracts, errors, secret handling,
  pagination and cancellation. These do not prove live provider access.
- Synthetic native media: visible cursor/hotspot movement, zoom/cut alignment,
  narration longer/shorter than video, frozen frames, audio mix/timing, 1080p/4K,
  cancellation and portable project round-trip.
- Native UI: cursor controls, custom PNG import, script/voice/language controls,
  generation/cancellation, preview, save/reopen and export.
- With a user-configured key: generate a short synthetic narration through the real
  ElevenLabs service, play it, and verify its inclusion in an exported video.
- Capture a permitted test window to verify clean video plus cursor samples. Synthetic
  media checks alone do not establish screen-capture geometry or very short click accuracy.
