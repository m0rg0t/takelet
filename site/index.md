# Takelet — open-source macOS screen recorder and demo editor

One take. A clearer story.

Takelet is a free, native macOS app for turning screen recordings into focused product demos. It is written in Swift, licensed under MIT, and stores projects locally. The current release is **v0.1.0 developer preview**.

- [Canonical website](https://m0rg0t.github.io/takelet/)
- [GitHub repository](https://github.com/m0rg0t/takelet)
- [Download Takelet 0.1.0 for Apple Silicon](https://github.com/m0rg0t/takelet/releases/download/v0.1.0/Takelet-0.1.0-arm64.dmg)
- [Release notes and checksums](https://github.com/m0rg0t/takelet/releases/tag/v0.1.0)

## Requirements and installation

The downloadable app requires **macOS 15 or later** and **Apple Silicon (arm64)**. Open the DMG, drag Takelet into Applications, and open it. Import a recording to begin editing. The app and disk image are Developer ID signed and notarized by Apple.

Manual editing, saving, and export do not require an account, API key, Xcode, or Python. Building from source requires Xcode's Swift 6 toolchain and Python 3; see the [README](https://raw.githubusercontent.com/m0rg0t/takelet/main/README.md) for build instructions.

## Available in the preview

- Import one video into a portable `.takelet` project that keeps the source recording together with its edits.
- Remove pauses with reversible cuts. Restore a cut or use Undo and Redo; the original recording stays intact.
- Set one smooth zoom and focus point.
- Choose a canvas background and adjust padding.
- Preview the edited video and export a landscape, 16:9 MP4 locally at 1080p or 4K, 30 frames per second.

The website's editor screenshot shows a real Takelet project using generated test footage.

## Experimental and planned features

Window recording is experimental. Capture permissions, live capture, and long-recording reliability still need broader testing. This is an early developer preview, not a stable production release.

Optional analysis is available through a separate experimental Codex command-line workflow. In-app AI review, editable cursors, portrait and square layouts, script review, and narration with the user's own ElevenLabs API key are planned. See the [roadmap](https://raw.githubusercontent.com/m0rg0t/takelet/main/docs/ROADMAP.md).

## Local projects and optional AI

Recording, manual editing, saving, and export use native macOS frameworks. The editor does not need an application backend or account.

The optional Codex analyzer sends selected frames only when explicitly run. It uses the signed-in account's shared Codex limits. A ChatGPT login does not provide a general-purpose OpenAI API key. See [AI analysis and privacy](https://raw.githubusercontent.com/m0rg0t/takelet/main/docs/AI_ANALYSIS.md) before using the analyzer with a recording.

## Open source

Takelet is available under the [MIT license](https://github.com/m0rg0t/takelet/blob/main/LICENSE). Report bugs and request features in [GitHub issues](https://github.com/m0rg0t/takelet/issues). Read the [contribution guide](https://raw.githubusercontent.com/m0rg0t/takelet/main/CONTRIBUTING.md) to contribute.

The canonical site is [GitHub Pages](https://m0rg0t.github.io/takelet/). The [ChatGPT Sites mirror](https://takelet.antonlenev.chatgpt.site/) publishes the same content. A curated documentation index is available at [llms.txt](https://m0rg0t.github.io/takelet/llms.txt).
