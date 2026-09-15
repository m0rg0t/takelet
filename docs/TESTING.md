# Testing

## Unit and transport checks

```sh
sh scripts/swift-check.sh test
sh scripts/build-app.sh
```

The suite covers time mapping, reversible edits, multiple zooms, click-based Auto Zoom,
cursor interpolation/styling, project-format migration and portable assets, narration
holds and edits, cancellation and retakes, workspace undo/redo, ElevenLabs request/error
contracts, AI results, and fragmented/interleaved JSONL transport, timeouts and EOF.
Tests require Python 3 but no provider login, inference or screen access. A generated
MP3 test fixture exercises audio measurement and installation without a paid request.

GitHub Actions builds/tests on macOS, packages the developer app, and checks tracked files for local artifacts and obvious credentials. A local pass does not mean the remote workflow has run.

## Native media check

```sh
sh scripts/swift-check.sh build
TAKELET_BIN_DIR="${TMPDIR:-/private/tmp}/takelet-swift/build/debug"
"$TAKELET_BIN_DIR/takelet-media-check" artifacts/media-check-01
```

Use a new destination. The executable generates synthetic footage and audio, with no private recording, screen permission or paid service needed. Native AVFoundation decoding/encoding needs normal macOS process services; unusually restricted execution environments may prevent them from working. The expanded cursor/narration media check needs a local Homebrew `ffmpeg` to generate actual MP3 and 60 fps test fixtures. This is a developer-check dependency; the Takelet app does not invoke ffmpeg.

The fixture is six seconds at 1920×1080/30 fps, with a moving object and audio pulses at source times 1.0, 3.5 and 5.0 seconds. The project removes `[2, 3)`, applies two zooms with different scales and focus points, and uses Dawn with 9% padding. The check:

1. Saves and reopens the portable project without metadata changes.
2. Exports 1920×1080 and 3840×2160 MP4.
3. Checks five-second duration, 30 fps and an audio track.
4. Compares four sampled preview/export frames at each resolution; mean pixel error must be below 8 on the 0–255 scale.
5. Verifies audio pulses at output times 1.0, 2.5 and 4.0 seconds, within 80 ms.
6. Cancels during export preparation, checks that no destination is created, then reuses the exporter successfully.
7. Checks that the gradient background is present in the exported pixels.
8. Compares against a composition without zooms: both zooms must visibly change
   their frames, while the gap and the ending must exactly retain the fitted view.

Outputs include a sample project, MP4s, PNG frames and `validation.json`.

### Initial evidence

On an Apple Silicon development Mac running macOS 26.5.2 with Swift 6.2.4, both exports passed. The pulse offset was approximately 0.1 ms and sampled mean pixel errors were below 0.7/255. These are short synthetic checks; the 4K output upscales a 1080p source. They do not establish native 4K capture quality, ten-minute performance or all-codec support.

The GUI opened the generated project and played/scrubbed the composed video after replacing the SwiftUI player bridge with AppKit `AVPlayerView`. Restoring a cut changed output duration from five to six seconds; Undo restored five seconds and Redo restored six. Saving succeeded. Window enumeration was denied by macOS screen-recording permissions, so live capture remains unverified.

### Design update

The updated suite passes 28 tests, including loading older documents without a background field. The Dawn/9% padding fixture passed at both export resolutions: mean sampled pixel errors were below 0.35/255, audio pulse offsets remained approximately 0.1 ms, and cancellation during preparation left no destination file.

The redesigned native window was checked in light and dark appearance. The real filmstrip loaded, playback advanced, and the accessible filmstrip action moved the playhead to one second. Changing Dawn to Tide updated the preview; Undo restored Dawn and Redo reapplied Tide. The final SDK compatibility build repeated this Undo/Redo check successfully. Restoring the `[2, 3)` cut changed the output from five to six seconds, and Undo restored five seconds with no unsaved changes. A fresh screenshot using only generated footage appears in the README and project site. The original System appearance preference was restored after review.

## Manual checks still required

### Callouts, masks and capture permission guidance (unreleased)

The updated unit suite passes 102 tests. Annotation coverage includes format 4
migration, geometry boundaries and floating-point resize endpoints, half-open
visibility, overlap, portable saves, draft persistence, atomic application with
cursor/narration controls, ordering, duplication and Undo/Redo. Undo invalidates
stale drafts for the changed annotation while preserving unrelated pending edits.

The standalone `takelet-media-check --annotations NEW_OUTPUT_DIRECTORY` check
passed native 1080p and 4K MP4 exports. Both measured 6.0667 seconds including the
synthetic narration hold. Sampled preview/export mean pixel errors were below
0.70/255 at 1080p and 0.54/255 at 4K. The cover exactly matched a solid patch over
the underlying cursor and callouts. Blur changed its rectangle and left the
surrounding pixels unchanged. Annotation-free frames before and after the interval
matched the baseline exactly; active frames and held frames retained the intended
annotations through cuts and zooms. Cyrillic multiline text rendered, impossible
text fits failed explicitly, and the portable annotated project reopened unchanged.

The native UI could not be exercised because the development Mac was locked.
Still check moving/resizing all four corners, switching inspector tabs, duplicate
and overlapping selections, the smallest window size, and Apply/Cancel in the
placement sheet. Permission setup now uses preflight plus inline guidance; exercise
the initial macOS dialog, denial, opening settings and relaunch with permission.
The code change does not grant screen-recording access. These features are in the
source build, not the published 0.1.0 DMG.

### Custom cursors and ElevenLabs (unreleased)

Native synthetic media validation passed at 1080p and 4K. It covers portable PNG/MP3
assets, a cursor hotspot through zoom/cuts, hidden versus embedded cursor behavior,
short and long narration, source-audio silence during a hold, non-frame-aligned hold
boundaries and shared preview/export output. Separate muted-source and muted-narration
exports verify both audio volume controls and source pulses after a hold. Both exports measured approximately
30 fps. Sampled preview/export differences were below 0.39/255; prepared held-frame
differences were zero and encoded differences below 0.03/255. A 60 fps alternating-frame
source stayed exactly frozen throughout its narration hold.

The checks caught two rendering regressions: inheriting variable source timing and
stretching more than one native frame. The builder now explicitly selects 30 fps
composition timing and stretches only a single source tick for a hold. The recorder
also samples cursor state on a separate timer so static clean video does not stop
cursor telemetry.

Workspace tests verify a playable mock MP3 response, actual audio duration measurement,
new immutable asset installation, Undo/Redo preserving old and new takes, script/settings
invalidation, request preflight, provider failure, invalid audio cleanup, cancellation
and locking edits during generation. These tests do not establish live provider access.

Manual cursor controls, PNG import, settings and full narration UI remain unverified
because the development Mac is locked. Real synthesis requires a user-configured key.
Live clean-window recording, initial cursor/video skew, static-screen movement,
very short clicks and window movement still need device testing. See the detailed
[acceptance checklist](CURSOR_NARRATION.md). These source features are not in the
published 0.1.0 DMG.

### Multiple zooms and Auto Zoom (unreleased)

The 40-test suite passes, including batched Undo/Redo with stable zoom IDs, editing
and deleting one zoom without changing another, rejecting overlapping edits, and
mapping the output playhead through cuts when adding a zoom. Core tests cover
legacy active/disabled zoom migration, click edges and held buttons, out-of-frame
clicks, cut boundaries, clipping at neighboring intervals, and repeated generation.

The native media check passed at 1080p and 4K. Both zooms changed the expected
frames; unzoomed gaps matched the baseline exactly. Sampled preview/export mean
pixel error stayed below 0.38/255 and audio offsets were approximately 0.1 ms.
Cancellation and portable project save/reopen passed.

Manual interaction with the new timeline selection and inspector is pending: the
development Mac was locked during this update. Live capture click timing and very
short click detection also remain unverified. The source build includes these
features; the public 0.1.0 DMG does not.

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
