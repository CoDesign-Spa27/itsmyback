#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
cache="${TMPDIR:-/tmp}/posturebuddy-tests"
mkdir -p "$cache"
CLANG_MODULE_CACHE_PATH="$cache/clang" swift test --disable-sandbox --cache-path "$cache/cache" --config-path "$cache/config" --security-path "$cache/security" --scratch-path "$cache/build"
