#!/bin/bash
# install-helper.sh — pasang FreePNHelper + sing-box sebagai root LaunchDaemon.
# Untuk pemakaian pribadi TANPA sertifikat Developer ID (SMAppService butuh signature
# berbayar; cara ini memakai sudo + launchctl secara langsung).
#
#   ./scripts/build-core.sh
#   xcodebuild -project FreePN.xcodeproj -target FreePNHelper -configuration Release ...
#   sudo ./scripts/install-helper.sh
#   sudo ./scripts/install-helper.sh --uninstall   # untuk mencopot
set -euo pipefail
cd "$(dirname "$0")/.."

LABEL="com.freepn.helper"
MACH="com.freepn.helper.xpc"
DEST_DIR="/Library/PrivilegedHelperTools"
DAEMON_PLIST="/Library/LaunchDaemons/${LABEL}.plist"

# Bunuh core sing-box milik FreePN saja.
#
# JANGAN pernah pakai `pkill -x sing-box` di sini. `-x` mencocokkan NAMA PROSES
# di seluruh mesin, jadi perintah itu ikut membunuh sing-box milik tool VPN
# lain milik user (ClashX, Surge, mihomo, …).
#
# Core FreePN dijalankan sebagai `sing-box run -c <path>`, jadi
# `pkill -f <path>` menyentuh core yang dimaksud dan tidak yang lain.
#
# Argumen pertama: "vpn" (hanya core TUN) atau "all" (dipakai saat uninstall).
kill_freepn_cores() {
  case "${1:-all}" in
    vpn) pkill -f "freepn/config.json" 2>/dev/null || true ;;
    all) pkill -f "freepn/config.json" 2>/dev/null || true ;;
    *) echo "kill_freepn_cores: argumen tidak dikenal: $1" >&2; return 1 ;;
  esac
}

if [ "${1:-}" = "--uninstall" ]; then
  [ "$(id -u)" = "0" ] || { echo "Harus root: sudo $0 --uninstall" >&2; exit 1; }
  launchctl bootout system/"$LABEL" 2>/dev/null || true
  # Uninstall memang melepas semua core FreePN: helper dicopot, jadi tidak
  # ada yang bisa memakai core itu lagi.
  kill_freepn_cores all
  rm -f "$DAEMON_PLIST" "$DEST_DIR/$LABEL" "$DEST_DIR/sing-box"
  echo "Helper dicopot."
  exit 0
fi

[ "$(id -u)" = "0" ] || { echo "Harus root. Jalankan: sudo $0" >&2; exit 1; }

HELPER_BIN=""
for c in "build/Release/FreePNHelper" "build/Debug/FreePNHelper"; do
  [ -x "$c" ] && HELPER_BIN="$c" && break
done
[ -n "$HELPER_BIN" ] || {
  echo "FreePNHelper belum dibuild. Jalankan dulu:" >&2
  echo "  xcodebuild -project FreePN.xcodeproj -target FreePNHelper -configuration Release -destination 'platform=macOS' ONLY_ACTIVE_ARCH=NO ARCHS='arm64 x86_64' build" >&2
  exit 1
}

SINGBOX=""
for c in "build/Release/FreePN.app/Contents/Resources/sing-box" "FreePN/Resources/sing-box"; do
  [ -x "$c" ] && SINGBOX="$c" && break
done
[ -n "$SINGBOX" ] || {
  echo "sing-box belum ada. Jalankan dulu: ./scripts/build-core.sh" >&2
  exit 1
}

echo "[1/4] Menyalin helper + core ke $DEST_DIR ..."
mkdir -p "$DEST_DIR"
cp -f "$HELPER_BIN" "$DEST_DIR/$LABEL"
cp -f "$SINGBOX" "$DEST_DIR/sing-box"
chmod 755 "$DEST_DIR/$LABEL" "$DEST_DIR/sing-box"
chown root:wheel "$DEST_DIR/$LABEL" "$DEST_DIR/sing-box"
lipo -archs "$DEST_DIR/sing-box"

echo "[2/4] Menulis $DAEMON_PLIST ..."
cat > "$DAEMON_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$LABEL</string>
	<key>ProgramArguments</key>
	<array>
		<string>$DEST_DIR/$LABEL</string>
	</array>
	<key>MachServices</key>
	<dict>
		<key>$MACH</key>
		<true/>
	</dict>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<false/>
	<key>StandardOutPath</key>
	<string>/tmp/freepn-helper.out.log</string>
	<key>StandardErrorPath</key>
	<string>/tmp/freepn-helper.err.log</string>
</dict>
</plist>
EOF
chmod 644 "$DAEMON_PLIST"
chown root:wheel "$DAEMON_PLIST"

echo "[3/4] Bootstrap daemon ..."
# Hanya core TUN yang dibunuh di sini. sing-box milik tool VPN lain milik user
# sedang berjalan tidak boleh ikut mati hanya karena helper di-reinstall.
kill_freepn_cores vpn
launchctl bootout system/"$LABEL" 2>/dev/null || true
launchctl bootstrap system "$DAEMON_PLIST"

echo "[4/4] Verifikasi ..."
sleep 1
launchctl print system/"$LABEL" | grep -E "state|program" | head -n 4
echo
echo "Selesai. Buka FreePN dan tekan Connect — status harus berubah tanpa 'helper unavailable'."
echo "Mencopot: sudo $0 --uninstall"
