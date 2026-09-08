#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h}"
output_dir="${TMETER_OUTPUT_DIR:-$project_dir/dist}"
app_dir="$output_dir/TMeter.app"
cache_dir="$project_dir/.build/module-cache"

mkdir -p "$app_dir/Contents/MacOS" "$cache_dir"
export CLANG_MODULE_CACHE_PATH="$cache_dir"
export SWIFT_MODULECACHE_PATH="$cache_dir"
swiftc -swift-version 5 -O \
  -framework SwiftUI -framework AppKit -framework ServiceManagement \
  "$project_dir/Sources/TokenMeterCore.swift" \
  "$project_dir/Sources/TokenMeterApp.swift" \
  -o "$app_dir/Contents/MacOS/TMeter"
cp "$project_dir/Info.plist" "$app_dir/Contents/Info.plist"
codesign --force --deep --sign - "$app_dir"
echo "$app_dir"
