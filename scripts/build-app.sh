#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
sh scripts/swift-check.sh build
task_cache="${TAKELET_BUILD_CACHE:-${TMPDIR:-/private/tmp}/takelet-swift}"
app_path="$PWD/build/Takelet.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$task_cache/build/debug/Takelet" "$app_path/Contents/MacOS/Takelet"
cp Resources/Info.plist "$app_path/Contents/Info.plist"
codesign --force --sign - "$app_path"
printf '\nBuilt %s\n' "$app_path"
