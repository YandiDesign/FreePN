#!/bin/bash
# check-localization.sh — pastikan tidak ada key yang belum diterjemahkan (Xcode 14: .strings).
set -euo pipefail
cd "$(dirname "$0")/.."
EN=FreePN/Localization/en.lproj/Localizable.strings
ID=FreePN/Localization/id.lproj/Localizable.strings
extract() { grep -o '^"[a-z_0-9]*"' "$1" | sort -u; }
diff <(extract "$EN") <(extract "$ID") && echo "Localization OK: key EN==ID" || { echo "MISMATCH di atas"; exit 1; }
# Cek string hardcoded NSLocalizedString vs literal di SwiftUI Text("...") yang bukan key:
echo "--- Text literal yang patut dicurigai (cek manual) ---"
grep -rn 'Text("[a-zA-Z ]' FreePN --include='*.swift' | grep -v 'Text(CountryInfer' | head -n 20 || true
