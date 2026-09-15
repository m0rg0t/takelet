# Project identity and publication

| Field | Value |
| --- | --- |
| Project name | **Takelet** |
| Pronunciation | “take-let” |
| Repository slug | `takelet` |
| GitHub repository | `m0rg0t/takelet` |
| Project site | <https://m0rg0t.github.io/takelet/> |
| Tagline | Turn screen recordings into clear product demos. |
| Short description | Native macOS screen recorder and demo editor with reversible cuts, smooth zoom, and optional AI assistance. |
| License | MIT |
| Bundle identifier | `io.github.m0rg0t.takelet` |
| Project extension | `.takelet` |
| Current stage | Developer preview, 0.1.0 |

The name comes from a small “take”: one recording shaped into a short demo. A repository availability check is not a trademark clearance.

Suggested GitHub topics: `macos`, `swift`, `swiftui`, `screen-recorder`, `video-editor`, `screencast`, `avfoundation`, `screencapturekit`, `codex`.

## Publication status

The source repository is public at <https://github.com/m0rg0t/takelet>. The initial developer preview was published on September 15, 2026. Both public websites are described in [Project site](SITE.md). The [0.1.0 developer preview](https://github.com/m0rg0t/takelet/releases/tag/v0.1.0) includes a Developer ID signed, Apple-notarized DMG for Apple Silicon and macOS 15 or later.

## Publication checks

1. Review the files and history. Keep recordings, AI evidence, account data and internal planning outside Git.
2. Run [testing](TESTING.md) and publication checks. Keep limitations visible in the README.
3. Push reviewed changes to `m0rg0t/takelet` on `main` or open a pull request.
4. Confirm GitHub Actions completes. Enable private vulnerability reporting and appropriate branch protections.
5. Add screenshots only from synthetic or explicitly shareable content.

MIT applies to this repository's code. No proprietary application assets or private skill collection are included. Review licenses before redistributing any later dependency or bundled helper.

## Downloadable release

Follow [Releasing](RELEASING.md) to build, sign, notarize, staple and verify the app and DMG, generate a checksum, and publish the exact source revision. The DMG remains a prerelease while native capture, recovery/cancellation, permissions and long-recording reliability receive broader testing. The default local development build remains ad-hoc signed.
