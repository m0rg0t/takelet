# Editor design

## Reference and direction

The public [Kite demonstrations](https://kite.video/) show a large central preview, compact surrounding tools, and distinct colored timeline layers. Its examples also use backgrounds and framing to give ordinary screen recordings a more deliberate presentation. This research used the website's rendered demos; the Kite desktop app was not installed or tested.

Takelet adapts those interaction patterns to a native Mac workspace. The implementation and assets are original. The goal is an editor where the recording is visually dominant and the controls are easy to scan.

## Implemented changes

- **Media sidebar:** a real source thumbnail, source dimensions/duration, import/open actions and collapsible recording controls.
- **Preview stage:** a quiet graphite surface and a correctly fitted 16:9 player. The surrounding space is editor chrome, not extra letterboxing in the exported video.
- **Timeline:** real source thumbnails, a time ruler, a source playhead, hatched cuts and a separate purple zoom interval. Filmstrip scrubbing maps source time to the edited output. Playback controls show output time.
- **Inspector:** Style and Edit sections, compact cards, paired time fields and a spatial zoom focus picker. Actions apply actual project edits and support Undo.
- **Canvas presets:** Midnight, Mist, Dawn and Tide, plus adjustable padding. Shared color definitions drive the swatches and the AVFoundation/Core Image renderer.
- **Appearance:** System, Light and Dark options in Settings. System is the default; standard Mac controls keep the user's accent color.

## Boundaries

The preview and export share the background implementation. Existing version-1 documents without a background field retain their original Midnight appearance. This change does not add editable cursor rendering, multiple zooms, new output aspect ratios, narration or automatic edits.

Thumbnails are derived locally, limited to ten small frames, and not persisted in project metadata. A missing thumbnail does not prevent playback. Cuts are distinguished by hatching and an icon as well as color; filmstrip scrubbing has an accessibility adjustment action. Native menu commands, window controls, keyboard playback and undo remain available.

## Verification

Compatibility tests cover older project documents and preset persistence. The native media check renders Dawn with padding, verifies a gradient is present in exported pixels, compares preview/export frames, and checks audio after cuts. Manual light/dark and interaction checks are recorded in [testing](TESTING.md).
