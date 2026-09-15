# Building a downloadable release

Public DMGs require a Developer ID Application certificate and an existing
`notarytool` Keychain profile for the same Apple Developer team. Certificates,
private keys and credentials stay outside the repository. This workflow does not
fall back to an unsigned or unnotarized download.

## Build

Update `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist`
for a new release, run the unit/media checks, review the source and commit it.
From a clean checkout on an Apple Silicon Mac:

```sh
export TAKELET_SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)'
export TAKELET_NOTARY_PROFILE='YourNotaryProfile'
sh scripts/swift-check.sh test
bash scripts/build-dmg.sh
```

`TAKELET_BUILD_CACHE` can put Swift build caches on another disk. The DMG builder
uses optimized Release compilation for arm64 and the minimum macOS version from
the package and Info.plist. It checks the signature, timestamp, hardened runtime
and microphone entitlement, notarizes and staples the app, creates a disk image
with an Applications shortcut, then notarizes and staples the DMG. The final image
is mounted read-only to validate its bundled app and installation shortcut.

Artifacts and local submission evidence live in `build/releases/<version>/`.
Existing output is preserved. If submission is interrupted, inspect the saved
notarization result and resume that Apple submission before starting another one.
Never replace an asset already published under a release tag.

## Publish

1. Confirm the exact source commit has passed CI and perform a launch check of
   the packaged app. Keep capture and performance limitations in the release notes.
2. Create a Git tag for that commit and a GitHub **prerelease** while Takelet is
   a developer preview.
3. Upload only `Takelet-<version>-arm64.dmg`, `SHA256SUMS.txt` and `release.json`.
   Keep local notarization logs, signing diagnostics and intermediate ZIPs local.
4. Download the published DMG and compare its SHA-256 with the locally verified
   artifact. Point the website at the exact versioned release asset.
5. Update the README, landing page and publication status, then publish both
   GitHub Pages and ChatGPT Sites using [the shared site workflow](SITE.md).

Apple's [notarization guide](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
describes the distribution requirements. Notarization does not establish capture
reliability or replace testing on another Mac.
