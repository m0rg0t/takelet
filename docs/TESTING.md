# Testing

## Unit and transport checks

```sh
sh scripts/swift-check.sh test
sh scripts/build-app.sh
```

The current suite has 28 tests covering time mapping, reversible edits, zoom timing, project validation/storage, backward-compatible background presets, AI results, and fragmented/interleaved JSONL transport, timeouts and EOF. Tests require Python 3 but no provider login, inference or screen access.

GitHub Actions builds/tests on macOS, packages the developer app, and checks tracked files for local artifacts and obvious credentials. A local pass does not mean the remote workflow has run.

## Native media check

```sh
sh scripts/swift-check.sh build
TAKELET_BIN_DIR="${TMPDIR:-/private/tmp}/takelet-swift/build/debug"
"$TAKELET_BIN_DIR/takelet-media-check" artifacts/media-check-01
```

Use a new destination. The executable generates synthetic footage and audio, with no private recording, screen permission or paid service needed. Native AVFoundation decoding/encoding needs normal macOS process services; unusually restricted execution environments may prevent them from working.

The fixture is six seconds at 1920×1080/30 fps, with a moving object and audio pulses at source times 1.0, 3.5 and 5.0 seconds. The project removes `[2, 3)`, applies a zoom and uses Dawn with 9% padding. The check:

1. Saves and reopens the portable project without metadata changes.
2. Exports 1920×1080 and 3840×2160 MP4.
3. Checks five-second duration, 30 fps and an audio track.
4. Compares three sampled preview/export frames at each resolution; mean pixel error must be below 8 on the 0–255 scale.
5. Verifies audio pulses at output times 1.0, 2.5 and 4.0 seconds, within 80 ms.
6. Cancels during export preparation, checks that no destination is created, then reuses the exporter successfully.
7. Checks that the gradient background is present in the exported pixels.

Outputs include a sample project, MP4s, PNG frames and `validation.json`.

### Initial evidence

On an Apple Silicon development Mac running macOS 26.5.2 with Swift 6.2.4, both exports passed. The pulse offset was approximately 0.1 ms and sampled mean pixel errors were below 0.7/255. These are short synthetic checks; the 4K output upscales a 1080p source. They do not establish native 4K capture quality, ten-minute performance or all-codec support.

The GUI opened the generated project and played/scrubbed the composed video after replacing the SwiftUI player bridge with AppKit `AVPlayerView`. Restoring a cut changed output duration from five to six seconds; Undo restored five seconds and Redo restored six. Saving succeeded. Window enumeration was denied by macOS screen-recording permissions, so live capture remains unverified.

### Design update

The updated suite passes 28 tests, including loading older documents without a background field. The Dawn/9% padding fixture passed at both export resolutions: mean sampled pixel errors were below 0.35/255, audio pulse offsets remained approximately 0.1 ms, and cancellation during preparation left no destination file.

The redesigned native window was checked in light and dark appearance. The real filmstrip loaded, playback advanced, and the accessible filmstrip action moved the playhead to one second. Changing Dawn to Tide updated the preview; Undo restored Dawn and Redo reapplied Tide. The final SDK compatibility build repeated this Undo/Redo check successfully. Restoring the `[2, 3)` cut changed the output from five to six seconds, and Undo restored five seconds with no unsaved changes. A fresh screenshot using only generated footage appears in the README and project site. The original System appearance preference was restored after review.

## Manual checks still required

### Downloadable 0.1.0 preview

The optimized arm64 app and DMG were signed with Developer ID, accepted by Apple's
notary service and stapled. Signature and Gatekeeper checks passed for both the
distribution image and the app inside the image; disk-image integrity and the
Applications shortcut also passed. The release source passed all 28 tests and
the macOS CI build. The SHA-256 and source/toolchain record accompany the release.

A fresh GUI launch check of this signed Release build is pending because the
development Mac was locked during packaging. The manual editor checks above used
the development build; they do not replace testing an installed download on a
different Mac.

### Remaining application coverage

- Importing varied files, save/reopen through Finder and multiple project windows.
- Browser-window capture with system audio and microphone; permission denial and recovery.
- Moving/resizing a captured window, cursor alignment and very short clicks.
- Repeated stop/start, closing the captured window and capture interruption.
- Export cancellation during encoding; no final/partial destination left behind.
- Ten-minute capture: audio drift, dropped frames, memory and disk behavior.
- Rotated videos, varied aspect ratios/codecs and truncated media.
- Full keyboard navigation and VoiceOver coverage, including smaller windows.

## AI checks

See [AI analysis](AI_ANALYSIS.md). Live inference is opt-in and uses shared account limits. Early short-clip/control experiments established transport and schema feasibility, including cancellation. Natural-recording cut quality, speech protection, provider portability and fresh login remain unverified.

## Before committing or publishing

```sh
python3 scripts/check-public-files.py
git diff --cached --check
```

The script reads the Git index. Stage intended files first and inspect the diff yourself; a pattern check cannot guarantee that content is safe to share. Do not include private recordings/frames, account state or credentials.
