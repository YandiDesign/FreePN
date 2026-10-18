#!/bin/bash
# build-core.sh — tanpa brew, tanpa asumsi Go.
# Mode default --prebuilt: download release resmi sing-box darwin-amd64+arm64 lalu lipo.
# Mode --source: build dari source (butuh Go dari installer resmi go.dev, bukan brew).
set -euo pipefail
VERSION="${SINGBOX_VERSION:-v1.13.6}"
MODE="--prebuilt"
for a in "$@"; do case "$a" in --source) MODE="--source";; --prebuilt) MODE="--prebuilt";; esac; done
OUT_DIR="$(cd "$(dirname "$0")/../FreePN/Resources" && pwd)"
mkdir -p "$OUT_DIR" /tmp/freepn-core
echo "[build-core] mode=$MODE version=$VERSION out=$OUT_DIR"

if [ "$MODE" = "--prebuilt" ]; then
  cd /tmp/freepn-core
  for ARCH in amd64 arm64; do
    F="sing-box-${VERSION#v}-darwin-${ARCH}.tar.gz"
    URL="https://github.com/SagerNet/sing-box/releases/download/${VERSION}/${F}"
    echo "[build-core] downloading $URL"
    curl -fL -o "$F" "$URL"
    tar xzf "$F"
    cp "sing-box-${VERSION#v}-darwin-${ARCH}/sing-box" "sing-box-${ARCH}"
  done
  lipo -create sing-box-amd64 sing-box-arm64 -output "$OUT_DIR/sing-box"
  chmod +x "$OUT_DIR/sing-box"
  echo "[build-core] archs: $(lipo -archs "$OUT_DIR/sing-box")"
  "$OUT_DIR/sing-box" version || true
else
  if ! command -v go >/dev/null 2>&1; then
    echo "Go tidak ditemukan. Install dari https://go.dev/dl/ (pkg macOS), bukan brew." >&2
    exit 1
  fi
  SRC=/tmp/freepn-core/src
  rm -rf "$SRC"; mkdir -p "$SRC"
  git clone --depth 1 --branch "$VERSION" https://github.com/SagerNet/sing-box.git "$SRC" 2>/dev/null || \
    (curl -fL "https://github.com/SagerNet/sing-box/archive/refs/tags/${VERSION}.tar.gz" | tar xz -C /tmp/freepn-core && mv /tmp/freepn-core/sing-box-* "$SRC")
  cd "$SRC"
  GOOS=darwin GOARCH=amd64 go build -o /tmp/freepn-core/sing-box-amd64 ./cmd/sing-box
  GOOS=darwin GOARCH=arm64 go build -o /tmp/freepn-core/sing-box-arm64 ./cmd/sing-box
  lipo -create /tmp/freepn-core/sing-box-amd64 /tmp/freepn-core/sing-box-arm64 -output "$OUT_DIR/sing-box"
  chmod +x "$OUT_DIR/sing-box"
  echo "[build-core] archs: $(lipo -archs "$OUT_DIR/sing-box")"
fi
