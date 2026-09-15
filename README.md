# Takelet

**Turn screen recordings into clear product demos.**

Takelet is a native macOS recorder and editor for short tutorials, feature announcements, and internal walkthroughs. Keep the original take, remove pauses, bring details closer, and export a video you can share.

**Developer preview · macOS 15+ · Apple Silicon · MIT**

[Project site](https://m0rg0t.github.io/takelet/) · [ChatGPT Sites](https://takelet.antonlenev.chatgpt.site/) · [Build from source](#build-and-run) · [Roadmap](docs/ROADMAP.md)

[**Download Takelet 0.1.0 for Apple Silicon**](https://github.com/m0rg0t/takelet/releases/download/v0.1.0/Takelet-0.1.0-arm64.dmg) — a Developer ID signed and Apple-notarized developer preview. Open the DMG, drag Takelet into Applications, then open the app. Requires macOS 15 or later; Intel Macs are not supported.

See the [release notes and checksums](https://github.com/m0rg0t/takelet/releases/tag/v0.1.0) and [roadmap](docs/ROADMAP.md). The experimental Codex analyzer remains available separately from source.

![Takelet editor showing a synthetic demo, source timeline, cuts and zoom controls](docs/images/editor.png)

*The native editor in dark appearance, using generated test footage. See [Editor design](docs/DESIGN.md) for the design direction.*

## What works today

This section describes the current source build. Multiple zooms, click-based Auto
Zoom, editable cursors, ElevenLabs narration, callouts and masks are new since the downloadable
0.1.0 preview and are not in that DMG yet.

- Import one video and save a portable `.takelet` project containing its source and edits.
- Remove and restore source intervals, with undo/redo.
- Add multiple smooth zoom intervals, each with its own timing, scale and focus point.
- Select and remove zooms on the timeline; edit them in the inspector with undo/redo.
- Create editable zooms locally from recorded clicks using **Zoom → Auto Zoom from Clicks**. Existing zooms are preserved; imported videos without click data use manual zooms.
- Scrub a filmstrip of real source frames and see cuts and zoom timing on separate tracks.
- Choose one of four canvas backgrounds, adjust padding, and switch between system, light and dark appearance.
- Preview against a padded background using the same composition engine as export.
- Export 16:9 MP4 at 1080p or 4K, 30 fps, preserving source audio through cuts.
- Style the separate cursor of new Takelet recordings: arrow, circle, crosshair,
  or a custom PNG, with size, color, smoothing, click highlights and an editable hotspot.
- Write narration for source intervals, choose an ElevenLabs voice and generate or
  replace individual takes using your own API key stored in macOS Keychain.
- Fit longer narration with automatic frozen-frame holds, mix original audio and
  narration independently, and carry PNGs and generated speech in the portable project.
- Add timed arrows, frames and text labels; place and resize them on the original frame.
- Apply blur or opaque rectangular masks, with source timing, layer ordering and undo/redo.
- Experiment with a separate command-line analyzer that prepares frames locally and requests reviewable cut suggestions through a local Codex installation.

Window recording with optional system audio and microphone input is implemented.
New captures record a clean picture and sample the cursor separately, including
while the screen is static. Imported videos and older projects retain their embedded
cursor. Live capture geometry and permission handling still need end-to-end validation.

## Build and run

Use an Apple Silicon Mac running macOS 15 or newer, with Xcode's Swift 6 toolchain selected. Python 3 is used by development checks and the optional analysis report. There are no third-party Swift package dependencies.

From the repository root:

```sh
sh scripts/swift-check.sh test
sh scripts/build-app.sh
open build/Takelet.app
```

By default, the build script creates an ad-hoc signed **developer** app. The downloadable DMG uses the separate [signed and notarized release workflow](docs/RELEASING.md). Build caches live in the system temporary directory. The script disables SwiftPM's nested build sandbox; it does not grant macOS screen or microphone permissions.

To keep build caches on another disk, set `TAKELET_BUILD_CACHE` to an absolute directory before invoking the scripts. Executables then live in `$TAKELET_BUILD_CACHE/build/debug`.

### Try it with synthetic footage

```sh
TAKELET_BIN_DIR="${TMPDIR:-/private/tmp}/takelet-swift/build/debug"
"$TAKELET_BIN_DIR/takelet-media-check" artifacts/first-demo
```

In Takelet, choose **Open Project…** and select `artifacts/first-demo/Sample.takelet`. The check generates a six-second recording, removes one second, and creates verified 1080p and 4K exports. Use a new output folder on each run.

To use your own footage, choose **Import Video…**, set cut and zoom intervals in source seconds, then save the project and export. The current limit is one source recording of approximately ten minutes per project; long-recording reliability is still being measured.

### Work with zooms

Scrub to an unzoomed part of the take and choose **Add Zoom** (⌘⌥Z). Select a
purple timeline interval to change its source start/end times, magnification and
focus in **Edit → Zoom & focus**, then choose **Apply Zoom**. **Preview Zoom**
seeks to its full magnification. Right-click an interval to remove it; ⌘Z restores
it. Intervals cannot overlap.

For a Takelet recording with click samples, **Auto Zoom from Clicks** (⌘⌥⇧Z)
adds zooms around spaced mouse-down events in retained footage. It uses no AI or
network connection. Review the results: sampled cursor data can miss short clicks,
and automatic cursor following is not implemented. Repeating the command keeps
existing zooms and does not add duplicates.

Older projects open with their zoom and appearance preserved. Saving writes
project format 4; Takelet 0.1.0 cannot open that newer format. Keep a copy of a
format-1 project if you need to continue opening it in the old release.

### Cursor and narration

For a new Takelet recording, open **Style → Cursor**, adjust the controls and choose
**Apply Cursor**. Import a transparent PNG up to 2048×2048 pixels and 8 MB to use a
custom pointer. The hotspot is the point in that image that marks the click location.

In **Takelet → Settings → ElevenLabs**, save your API key and load voices. Choose
**Narration → Add Narration at Playhead** (⌘⌥N), edit the source interval and script,
then select a voice. Save the draft locally, or choose **Generate with ElevenLabs**
to save it and send it for synthesis. This uses your ElevenLabs account's credits.
Multilingual v2 detects language automatically; Flash v2.5 also accepts a two-letter
language code such as `en` or `ru`. Other languages depend on provider support.

Preview the result before export. Speech longer than its retained source interval
holds the last retained frame and shifts downstream footage. Shorter speech leaves
the remaining video intact. Source audio is silent during a hold; the Audio mix
controls set original-audio and narration volume independently. Generation can be
cancelled and is never retried automatically. Changing a script, voice, model or
language clears that segment's generated take; Undo restores it. Timing edits reuse
the audio and recalculate pacing. Save the project to keep all assets together.

Pending script and cursor controls stay with the workspace when you switch tabs or
segments. **Save Project** and **Export** validate and apply them together; generation from the
menu uses the same current draft as the inspector button.

The client and media path have automated checks; a real synthesis with a user-configured
key and the full native UI workflow still require manual validation.

### Callouts and masks

Open **Markup** in the inspector and choose **Add Callout** or **Add Mask**. Set
source start/end times, or choose **Use Entire Take**. **Place on Frame…** opens
the original frame: drag the outline to move it and a corner to resize it. You can
also enter position and size as percentages. Choose **Apply Annotation** to update
the composed preview. Save and Export also apply pending annotation controls.

Arrows have four directions; frames have adjustable line width; text labels wrap
and fit inside a colored box. Duplicate annotations and change their layer order
in the inspector. Masks always cover callouts and the cursor. Use an opaque mask
for private text; blur softens details. Masks remain at a fixed source position,
so review the full interval when content moves. The original video in the project
package remains unchanged. See [Callouts and masks](docs/ANNOTATIONS.md).

If recording access is missing, **Refresh Windows** requests permission once and
shows an inline **Open System Settings…** action. Enable Takelet under
**Privacy & Security → Screen & System Audio Recording**, then reopen the app.
Import and editing work without screen-recording access.

## AI is optional

Recording, manual editing, saving, and export use local macOS frameworks. Takelet has no application backend.

The experimental `takelet-analyze` CLI can use an existing **Codex-managed ChatGPT login**. Inference shares that account's Codex limits. It sends selected frames when explicitly invoked; it does not turn a ChatGPT subscription into a general API key. No automatic paid API fallback is enabled.

AI cut suggestions and generated scripts are not connected to the editor UI yet.
Configurable OpenAI-compatible analysis providers are planned. ElevenLabs narration
accepts user-written scripts in the editor. Read [AI analysis](docs/AI_ANALYSIS.md)
before running the separate analysis prototype.

## Project status

The automated native media check has passed for 1080p and 4K at 30 fps, including audio timing after a cut and sampled preview/export frame comparisons. Unit tests cover project validation, timeline mapping, AI-result validation, and the Codex transport. This does not establish ten-minute capture reliability or AI cut accuracy on arbitrary recordings.

- [Roadmap and first-release scope](docs/ROADMAP.md)
- [Architecture and project format](docs/ARCHITECTURE.md)
- [Editor design](docs/DESIGN.md)
- [Testing and known limitations](docs/TESTING.md)
- [Experimental AI analysis](docs/AI_ANALYSIS.md)
- [Contributing](CONTRIBUTING.md) · [Security and privacy](SECURITY.md)
- [Project identity and publication checklist](docs/PUBLISHING.md)
- [Project site and GitHub Pages deployment](docs/SITE.md)

## License

[MIT](LICENSE). Takelet is an independent implementation. No third-party application source, branding, or demo assets are bundled.
