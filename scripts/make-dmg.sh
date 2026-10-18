#!/bin/bash
# make-dmg.sh — build Release FreePN lalu bungkus jadi DMG (app + symlink /Applications).
# Tanpa brew, tanpa create-dmg: cukup xcodebuild + hdiutil.
#
# Catatan signing: app ditandatangani "Apple Development". Hasilnya PAS untuk install
# di Mac ini sendiri (dan Mac lain selama sertifikat dev masih trusted). Untuk
# distribusi ke orang lain butuh Developer ID + notarize (lihat scripts/notarize.sh).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$REPO_ROOT/FreePN.xcodeproj"
SCHEME="FreePN"
CONFIG="Release"
VOLNAME="FreePN"
FORMAT="${FORMAT:-UDZO}"   # UDZO = compressed, ULFO = cepat mount (untuk lokal)
DIST_DIR="${DIST_DIR:-$REPO_ROOT/dist}"

# Volume repo bisa ExFAT (tidak ada atomic rename) → Swift module cache gagal
# ("error opening ...swiftmodule for output: File exists"). Karena itu DerivedData
# dipaksa ke disk lokal APFS.
if [ "${DERIVED_DATA:-}" = "" ]; then
  DERIVED_DATA="$(mktemp -d "${TMPDIR:-/tmp}/freepn-dd.XXXXXX")"
  trap 'rm -rf "$DERIVED_DATA"' EXIT
fi

echo "[make-dmg] repo=$REPO_ROOT"
echo "[make-dmg] derivedData=$DERIVED_DATA"

# 1. Build Release.
echo "[make-dmg] building $SCHEME ($CONFIG)..."
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED_DATA" build >/tmp/freepn-dmg-build.log 2>&1 || {
    echo "[make-dmg] BUILD GAGAL — lihat /tmp/freepn-dmg-build.log" >&2
    tail -30 /tmp/freepn-dmg-build.log >&2
    exit 1
  }
APP="$DERIVED_DATA/Build/Products/$CONFIG/FreePN.app"
[ -d "$APP" ] || { echo "[make-dmg] app tidak ditemukan: $APP" >&2; exit 1; }

# 2. Pastikan signature utuh (termasuk binary di dalam Resources).
echo "[make-dmg] verifying code signature..."
codesign --verify --deep --strict --verbose=1 "$APP"

# 3. Versi untuk nama file.
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILD_NR="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
echo "[make-dmg] version=$VERSION build=$BUILD_NR"

# 4. Stage: app + symlink ke /Applications.
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/freepn-dmg.XXXXXX")"
trap 'rm -rf "$DERIVED_DATA" "$STAGE"' EXIT
cp -R "$APP" "$STAGE/FreePN.app"
ln -s /Applications "$STAGE/Applications"
# Bersihkan artefak AppleDouble / __MACOSX yang bisa terbawa dari volume ExFAT.
find "$STAGE" -name '._*' -exec rm -rf {} + 2>/dev/null || true
find "$STAGE" -name '.DS_Store' -exec rm -f {} + 2>/dev/null || true

# 5. Bikin DMG.
#
# `hdiutil create -srcfolder` dipakai lebih dulu karena paling sederhana, tapi
# jalur itu tidak bisa diandalkan di macOS ini: ia gagal dengan
#
#   could not access /Volumes/<vol>/<file> - Tidak ada ruang tersisa pada perangkat
#
# padahal disk sama sekali tidak penuh, dan kegagalannya NON-MONOTONIK —
# file 64 MB lolos, 65 MB dan 70 MB gagal, 80 MB dan 100 MB lolos lagi.
# Reproduksi terisolasi ke file apa pun (dummy 70 MB tanpa hubungannya dengan
# FreePN juga gagal), jadi ini bukan properties app, bukan volume, dan bukan
# `hdiutil` membuat image, me-mount-nya, lalu `diskimages-helper`
# gagal menulis isinya. Kegagalan tidak berkorelasi dengan ukuran total.
#
# Karena itu ada jalur cadangan yang tidak melewati kode bermasalah sama sekali:
# buat image kosong berukuran pasti -> mount -> `cp -R` isinya -> detach ->
# convert ke UDZO. Deterministik, dan hasilnya sudah diverifikasi signature-nya.
#
# Dan karena penyebabnya volume ExFAT tempat repo berada, DMG SELALU dibuat
# di folder lokal APFS lebih dulu, diverifikasi di sana, lalu dipindahkan ke
# `DIST_DIR` sebagai langkah terakhir. Yang tersentuh volume ExFAT cuma
# `cp` satu file jadi tidak ada `hdiutil` yang bekerja di sana sama sekali.
mkdir -p "$DIST_DIR"
DMG_NAME="FreePN-$VERSION-$BUILD_NR.dmg"
DMG="$DIST_DIR/$DMG_NAME"
LOCAL_DIST="$(mktemp -d "${TMPDIR:-/tmp}/freepn-dmg-out.XXXXXX")"
DMG_LOCAL="$LOCAL_DIST/$DMG_NAME"
trap 'rm -rf "$DERIVED_DATA" "$STAGE" "$LOCAL_DIST"' EXIT
rm -f "$DMG_LOCAL"
echo "[make-dmg] creating $DMG_LOCAL ($FORMAT, lokal APFS)..."

STAGE_BYTES="$(du -sk "$STAGE" | cut -f1)"
IMAGE_MB=$(( STAGE_BYTES / 1024 + 200 ))   # +200 MB untuk block HFS+ & metadata

RAW="$DERIVED_DATA/freepn-raw.dmg"
if ! hdiutil create -volname "$VOLNAME" -srcfolder "$STAGE" -ov -format "$FORMAT" "$DMG_LOCAL" >/dev/null 2>/tmp/freepn-dmg-hdiutil.log 2>&1; then
  echo "[make-dmg] hdiutil -srcfolder gagal, pakai jalur create+mount+copy."
  sed 's/^/[make-dmg]   hdiutil: /' /tmp/freepn-dmg-hdiutil.log >&2
  rm -f "$DMG_LOCAL"
  hdiutil create -size "${IMAGE_MB}m" -fs HFS+ -volname "$VOLNAME" -ov "$RAW" >/dev/null
  MP="$(mktemp -d "${TMPDIR:-/tmp}/freepn-mount.XXXXXX")"
  hdiutil attach "$RAW" -nobrowse -mountpoint "$MP" >/dev/null
  # `cp -R` isi stage apa adanya; symlink /Applications ikut sebagai symlink.
  cp -R "$STAGE/." "$MP/"
  sync
  hdiutil detach "$MP" -quiet
  rmdir "$MP" 2>/dev/null || true
  hdiutil convert "$RAW" -format "$FORMAT" -imagekey zlib-level=6 -o "$DMG_LOCAL" >/dev/null
  rm -f "$RAW"
fi

# 6. Sanity check: mount sekali lalu pastikan app terbaca & signature valid.
# Dilakukan di file LOKAL — me-mount image dari volume ExFAT bisa gagal dan
# tidak menambah nilai apa pun.
echo "[make-dmg] verifying dmg (lokal)..."
MOUNT="$(mktemp -d "${TMPDIR:-/tmp}/freepn-mount.XXXXXX")"
hdiutil attach "$DMG_LOCAL" -nobrowse -readonly -mountpoint "$MOUNT" >/dev/null
trap 'hdiutil detach "$MOUNT" -quiet 2>/dev/null || true; rm -rf "$DERIVED_DATA" "$STAGE" "$LOCAL_DIST" "$MOUNT"' EXIT

if [ ! -d "$MOUNT/FreePN.app" ]; then
  echo "[make-dmg] FreePN.app tidak ada di dalam dmg" >&2; exit 1
fi
codesign --verify --deep --strict "$MOUNT/FreePN.app"

hdiutil detach "$MOUNT" -quiet
rmdir "$MOUNT" 2>/dev/null || true

# 7. Pindahkan ke volume tujuan, lalu pastikan utuh.
#
# `cp` (bukan `mv`) supaya file lokal tetap ada kalau penulisan ke ExFAT
# gagal di tengah jalan — setelah verifikasi signature, sedikit ruganya
# membangun ulang daripada kehilangan DMG-nya. Ukuran dibandingkan byte per
# byte; kalau tidak sama, tulis ulang dan coba lagi.
echo "[make-dmg] moving to $DIST_DIR ..."
LOCAL_BYTES="$(stat -f%z "$DMG_LOCAL")"
TARGET="$DIST_DIR/$DMG_NAME"
for attempt in 1 2 3; do
  rm -f "$TARGET"
  if cp "$DMG_LOCAL" "$TARGET" 2>/dev/null && [ "$(stat -f%z "$TARGET" 2>/dev/null || echo 0)" = "$LOCAL_BYTES" ]; then
    break
  fi
  echo "[make-dmg]   percobaan $attempt gagal/terpotong, ulang..." >&2
  sync
  sleep 1
  [ "$attempt" -lt 3 ] || { echo "[make-dmg] GAGAL memindahkan dmg ke $DIST_DIR" >&2; exit 1; }
done

SIZE="$(du -h "$DMG" | cut -f1 | tr -d ' ')"
echo "[make-dmg] SELESAI: $DMG ($SIZE)"
echo "[make-dmg] catatan: signed Apple Development (bukan Developer ID) — belum notarize."
