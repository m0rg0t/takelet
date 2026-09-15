#!/bin/bash
# Build and verify a Developer ID signed, notarized Apple Silicon release.
set -euo pipefail
cd "$(dirname "$0")/.."

: "${TAKELET_SIGN_IDENTITY:?Set TAKELET_SIGN_IDENTITY to a Developer ID Application identity.}"
: "${TAKELET_NOTARY_PROFILE:?Set TAKELET_NOTARY_PROFILE to an existing notarytool Keychain profile.}"
if [[ -n "$(git status --porcelain)" ]]; then
    echo "Commit the reviewed source before building a release." >&2
    exit 1
fi
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "The app version must use major.minor.patch." >&2
    exit 1
fi
release_dir="$PWD/build/releases/$version"
if [[ -e "$release_dir" ]]; then
    echo "Release output already exists: $release_dir. Preserve published artifacts; use a new version." >&2
    exit 1
fi
mkdir -p "$release_dir"
app="$release_dir/Takelet.app"
dmg="$release_dir/Takelet-$version-arm64.dmg"
source_commit="$(git rev-parse --verify HEAD)"
TAKELET_BUILD_CONFIGURATION=release TAKELET_APP_OUTPUT="$app" sh scripts/build-app.sh
[[ "$(lipo -archs "$app/Contents/MacOS/Takelet")" == arm64 ]]
codesign -dvvv "$app" 2> "$release_dir/signing.txt"
grep '^Authority=Developer ID Application:' "$release_dir/signing.txt" >/dev/null
grep '^Timestamp=' "$release_dir/signing.txt" >/dev/null
grep 'flags=.*runtime' "$release_dir/signing.txt" >/dev/null
codesign -d --entitlements :- "$app" > "$release_dir/entitlements.plist" 2>/dev/null
python3 - "$release_dir/entitlements.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'rb') as file:
    entitlements = plistlib.load(file)
assert entitlements == {'com.apple.security.device.audio-input': True}, entitlements
PY

notarize() {
    local package="$1" result="$2"
    xcrun notarytool submit "$package" --keychain-profile "$TAKELET_NOTARY_PROFILE" --wait --timeout 15m --output-format json > "$result"
    if [[ "$(plutil -extract status raw -o - "$result")" != Accepted ]]; then
        echo "Notarization was not accepted. Inspect $result before retrying." >&2
        exit 1
    fi
}

ditto -c -k --keepParent "$app" "$release_dir/Takelet-notarization.zip"
notarize "$release_dir/Takelet-notarization.zip" "$release_dir/notarization-app.json"
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=2 "$app"

stage="$(mktemp -d "$release_dir/staging.XXXXXX")"
mount_dir="$release_dir/mounted"
mounted=0
cleanup() {
    if [[ "$mounted" == 1 ]]; then hdiutil detach "$mount_dir" -quiet || true; fi
    rm -rf "$stage"
}
trap cleanup EXIT
ditto "$app" "$stage/Takelet.app"
ln -s /Applications "$stage/Applications"
cat > "$stage/Read Me.txt" <<'TXT'
Takelet — developer preview

Requires macOS 15 or later on an Apple Silicon Mac (M1 or newer).
Drag Takelet into Applications, then open it from Applications.

Screen and microphone access are requested only when recording. You can start
by importing an existing video without granting screen access.

This is an early preview. Live capture and long-recording reliability still
need broader testing. Keep your original recordings.

Source, release notes and support: https://github.com/m0rg0t/takelet
TXT
hdiutil create -volname "Takelet $version" -srcfolder "$stage" -fs HFS+ -format UDZO "$dmg"
codesign --timestamp --sign "$TAKELET_SIGN_IDENTITY" "$dmg"
notarize "$dmg" "$release_dir/notarization-dmg.json"
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
codesign --verify --strict "$dmg"
spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"
hdiutil verify "$dmg"
mkdir -p "$mount_dir"
hdiutil attach "$dmg" -nobrowse -readonly -mountpoint "$mount_dir" -quiet
mounted=1
codesign --verify --deep --strict "$mount_dir/Takelet.app"
xcrun stapler validate "$mount_dir/Takelet.app"
spctl --assess --type execute --verbose=2 "$mount_dir/Takelet.app"
[[ "$(readlink "$mount_dir/Applications")" == /Applications ]]
hdiutil detach "$mount_dir" -quiet
mounted=0
(
    cd "$release_dir"
    shasum -a 256 "$(basename "$dmg")" > SHA256SUMS.txt
)
python3 - "$release_dir" "$source_commit" "$version" <<'PY'
import json, pathlib, subprocess, sys
output = pathlib.Path(sys.argv[1])
record = {
    'version': sys.argv[3], 'source_commit': sys.argv[2], 'architecture': 'arm64',
    'minimum_macos': '15.0', 'configuration': 'release',
    'signing': 'Developer ID Application', 'notarization': 'Accepted',
    'stapled_app_and_dmg': True,
    'swift': subprocess.check_output(['swift', '--version'], text=True).strip(),
}
(output / 'release.json').write_text(json.dumps(record, indent=2) + '\n')
PY
printf '\nVerified release: %s\n' "$dmg"
