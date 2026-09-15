#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
task_cache="${TAKELET_BUILD_CACHE:-${TMPDIR:-/private/tmp}/takelet-swift}"
mkdir -p "$task_cache"
export CLANG_MODULE_CACHE_PATH="$task_cache/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$task_cache/clang"
exec swift "${1:-test}" --scratch-path "$task_cache/build" --cache-path "$task_cache/cache" --config-path "$task_cache/config" --security-path "$task_cache/security" --disable-sandbox
