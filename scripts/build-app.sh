#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
configuration="${TAKELET_BUILD_CONFIGURATION:-debug}"
case "$configuration" in debug|release) ;; *) echo "Use debug or release configuration." >&2; exit 1 ;; esac
sh scripts/swift-check.sh build -c "$configuration" --arch arm64 --product Takelet
task_cache="${TAKELET_BUILD_CACHE:-${TMPDIR:-/private/tmp}/takelet-swift}"
app_path="${TAKELET_APP_OUTPUT:-$PWD/build/Takelet.app}"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$task_cache/build/arm64-apple-macosx/$configuration/Takelet" "$app_path/Contents/MacOS/Takelet"
cp Resources/Info.plist "$app_path/Contents/Info.plist"
if [ -n "${TAKELET_SIGN_IDENTITY:-}" ]; then
    codesign --force --timestamp --options runtime --entitlements Resources/Takelet.entitlements --sign "$TAKELET_SIGN_IDENTITY" "$app_path"
else
    codesign --force --sign - "$app_path"
fi
codesign --verify --deep --strict "$app_path"
printf '\nBuilt %s\n' "$app_path"
