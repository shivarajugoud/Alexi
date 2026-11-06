#!/bin/zsh
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"

cache_root="$project_root/.build/caches"
mkdir -p "$cache_root/clang-module-cache" "$cache_root/swiftpm" "$cache_root/home"

export HOME="$cache_root/home"
export CLANG_MODULE_CACHE_PATH="$cache_root/clang-module-cache"
export SWIFTPM_MODULECACHE_PATH="$cache_root/swiftpm"
export SWIFT_MODULECACHE_PATH="$cache_root/swiftpm"

binary_path="$project_root/.build/arm64-apple-macosx/debug/Alexi"
build_direct() {
  echo "Compiling Alexi directly with swiftc."
  direct_build="$project_root/.build/direct/Alexi"
  mkdir -p "$(dirname "$direct_build")"
  swiftc -module-cache-path "$CLANG_MODULE_CACHE_PATH" Sources/Alexi/*.swift -o "$direct_build" \
    -framework SwiftUI \
    -framework UniformTypeIdentifiers \
    -framework AVFoundation \
    -framework Speech \
    -framework EventKit \
    -framework UserNotifications \
    -framework Security \
    -framework CryptoKit
  binary_path="$direct_build"
}

if [[ "${ALEXI_BUILD_MODE:-auto}" == "direct" || "$(xcode-select -p)" == "/Library/Developer/CommandLineTools" ]]; then
  build_direct
elif ! swift build -Xswiftc -module-cache-path -Xswiftc "$CLANG_MODULE_CACHE_PATH"; then
  build_direct
fi

app_path="$project_root/.build/Alexi.app"
mkdir -p "$app_path/Contents/MacOS"
cp "$binary_path" "$app_path/Contents/MacOS/Alexi"
cp "$project_root/App/Info.plist" "$app_path/Contents/Info.plist"
codesign --force --sign - --entitlements "$project_root/App/Alexi.entitlements" "$app_path"
open -n "$app_path"
