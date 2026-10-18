#!/bin/bash
# run-local.sh — build Debug universal (arm64 + x86_64) dengan Apple Development
# certificate, lalu jalankan. Sejak D42 app tidak punya entitlement apa pun,
# jadi build bertanda tangan ini berhasil di Personal Team gratis — tanpa
# provisioning profile.
set -euo pipefail
cd "$(dirname "$0")/.."

BUILD_SETTINGS=$(xcodebuild -project FreePN.xcodeproj -scheme FreePN \
  -configuration Debug -destination 'platform=macOS' -showBuildSettings 2>/dev/null)
TARGET_BUILD_DIR=$(awk -F' = ' '/ TARGET_BUILD_DIR /{print $2; exit}' <<<"$BUILD_SETTINGS")
APP="$TARGET_BUILD_DIR/FreePN.app"

# Buang produk lama sebelum build. `xcodebuild test` menyuntik XCTest ke dalam
# app (Contents/PlugIns/FreePNTests.xctest + Frameworks/XCTest*); sisa unsigned
# itu membuat codesign build berikutnya gagal dengan
# "code object is not signed at all ... FreePNTests.xctest", dan kalau hanya
# dihapus setelah signing, seal-nya jadi rusak ("a sealed resource is missing").
rm -rf "$APP" 2>/dev/null || true

xcodebuild -project FreePN.xcodeproj -scheme FreePN -configuration Debug \
  -destination 'platform=macOS' ONLY_ACTIVE_ARCH=NO ARCHS='arm64 x86_64' build

echo "APP: $APP"
echo "Verifikasi: codesign -dv --entitlements - \"$APP\" ; lipo -archs \"$APP/Contents/MacOS/FreePN\""
open "$APP" 2>/dev/null || true