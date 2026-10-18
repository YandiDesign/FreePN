<div align="center">

<img src="LOGO%20FreePN.png" width="160" alt="Logo FreePN">

# FreePN

**Client VPN gratis dan open source untuk macOS.**

Mengumpulkan subscription VPN publik gratis menjadi satu daftar server, menguji node mana yang benar-benar berfungsi, lalu mengarahkan trafik Anda melaluinya dengan core sing-box bawaan — mode TUN, split tunneling per-aplikasi dan per-domain, serta MAC address spoofing. Tanpa akun. Tanpa iklan. Tanpa telemetri.

[English](README.md) &nbsp;·&nbsp; [Bahasa Indonesia](README.id.md)

<img src="https://img.shields.io/badge/Platform-macOS%2013%2B%20Ventura-blue" alt="Platform: macOS 13+">
<img src="https://img.shields.io/badge/Architecture-Universal%20arm64%20%2B%20x86__64-lightgrey" alt="Universal">
<img src="https://img.shields.io/badge/Core-sing--box%201.13.6-orange" alt="sing-box 1.13.6">
<img src="https://img.shields.io/badge/License-MIT-green" alt="MIT">
<a href="https://github.com/YandiDesign/FreePN/releases/latest"><img src="https://img.shields.io/github/v/release/YandiDesign/FreePN?label=download&color=brightgreen" alt="Unduh"></a>

</div>

## Tangkapan Layar

<table>
  <tr>
    <td width="50%" align="center"><img src="SCREENSHOT/CONNECT.png" alt="Layar Connect" width="100%"><br><sub><b>Connect</b> — power ring, koneksi aktif, peta lokasi server, grafik trafik, exit IP</sub></td>
    <td width="50%" align="center"><img src="SCREENSHOT/SERVER.png" alt="Layar Servers" width="100%"><br><sub><b>Servers</b> — pencarian, filter protokol, latensi, kolom yang bisa diurutkan</sub></td>
  </tr>
  <tr>
    <td width="50%" align="center"><img src="SCREENSHOT/SOURCE.png" alt="Layar Sources" width="100%"><br><sub><b>Sources</b> — status subscription, jumlah per-sumber, detail online/offline</sub></td>
    <td width="50%" align="center"><img src="SCREENSHOT/SPLIT%20TUNNEL.png" alt="Layar Split Tunneling" width="100%"><br><sub><b>Split Tunneling</b> — mode inclusive/exclusive, aturan per-aplikasi dan per-domain, change log</sub></td>
  </tr>
  <tr>
    <td width="50%" align="center"><img src="SCREENSHOT/MAC%20ADDRESS.png" alt="Layar MAC Address" width="100%"><br><sub><b>MAC Address</b> — random, custom, restore, riwayat lengkap</sub></td>
    <td width="50%" align="center"><img src="SCREENSHOT/SETTING.png" alt="Layar Settings" width="100%"><br><sub><b>Settings</b> — tampilan, subscription, koneksi, performa</sub></td>
  </tr>
</table>

## Kenapa "Free"?

FreePN gratis dalam dua arti:

- **Tanpa biaya** — tanpa akun, tanpa langganan, tanpa pembayaran, tanpa iklan, tanpa analytics. Berlisensi MIT dan open source.
- **Bebas** — fork, ubah, dan distribusikan ulang (wajib atribusi, lihat [Lisensi](#lisensi)).

FreePN **tidak** menjalankan atau menjual server VPN sendiri. Aplikasi ini mengumpulkan **sumber subscription publik gratis** yang dikelola komunitas, membiarkan Anda memilih mana yang dipercaya, dan menguji node mana yang benar-benar berfungsi sebelum terhubung.

## Fitur

### Koneksi

- Connect / disconnect lewat core **sing-box** bawaan dengan **mode TUN** — menangkap trafik seluruh sistem, tanpa membajak system proxy
- UI power ring dengan animasi pulse dan timer sesi
- **Quick Connect** — satu klik ke node terbaik yang diketahui
- **Auto-reconnect** setelah Mac bangun dari tidur dan saat jaringan berubah
- **Status jujur** — tunnel diverifikasi (proses hidup, Clash API merespons, exit IP dicek lewat core) sebelum aplikasi bilang *Connected*; node mati dilaporkan sebagai error, bukan sukses palsu

### Server

- Mengumpulkan **ribuan node** dari sumber gratis yang dikelola komunitas
- Protokol: **Trojan, VMess, Shadowsocks, VLESS (REALITY/uTLS), Hysteria2**, plus HTTP dan SOCKS5
- Pencarian, filter per protokol dan sumber, kolom yang bisa diurutkan, favorit, aksi per-node
- **Ping** — mode cepat TCP opsional, atau (default) uji end-to-end sungguhan lewat outbound asli; *Ping All* berjalan dengan pengaturan CPU adaptif, batas waktu, progres, dan bisa dibatalkan
- Node mati ditandai setelah kegagalan nyata, bukan tebakan; duplikat antar-sumber di-dedup

### Sumber (Sources)

- Clash YAML, Base64, dan share link mentah **dideteksi otomatis per sumber** — tanpa konfigurasi khusus per sumber
- Instalasi baru mulai dengan **nol sumber**: pilih dari 10 feed komunitas pilihan yang ditawarkan sebagai chip sekali-klik, atau tambahkan URL subscription sendiri
- **Resolver URL bertanggal** untuk feed yang mengganti linknya tiap hari (mencoba hari ini hingga 7 hari ke belakang)
- Status per-sumber: node terbaca / ditambahkan / korup, error HTTP, aktif/nonaktif, refresh satu atau semua; refresh manual (⌘R) dan terjadwal

### Split Tunneling

- Mode **Inclusive** (hanya aplikasi terpilih yang lewat VPN) dan **Exclusive** (semua lewat VPN kecuali aplikasi terpilih)
- Aturan per-aplikasi dicocokkan lewat bundle path (ikut menangkap proses helper) dan aturan **per-domain**
- Pemindai aplikasi, pemilih aplikasi yang sedang berjalan, dan pemilih biner manual
- **Change log** mencatat setiap tulisan aturan: apa yang ditulis, kapan, dan kapan berlaku

### MAC Address

- Lihat daftar antarmuka jaringan, **randomize** ke alamat lokal yang valid, atur MAC **custom**, atau kembalikan ke aslinya
- Opsi randomize-saat-connect / restore-saat-disconnect
- Riwayat dengan pencarian dan filter

### Lainnya

- **Peta lokasi server** — peta dunia titik-titik yang dirender **sepenuhnya offline** dari tabel GeoIP bawaan
- **Traffic** — grafik up/down real-time, total sesi, daftar koneksi aktif (lewat Clash API sing-box)
- **Menu bar extra** — status, connect, quick connect, ping all, quit
- **Panel health check** — versi helper, keberadaan core, port, dan perbaikan sekali-klik
- UI aplikasi tersedia dalam **Bahasa Indonesia dan English** (bisa diganti langsung)
- Aksesibilitas: Reduce Transparency / Reduce Motion dihormati, label VoiceOver

## Cara Kerjanya

```
┌──────────────────────┐      XPC (diverifikasi code-sign)  ┌────────────────────────────┐
│  FreePN.app (SwiftUI)│ ◄────────────────────────────────► │  FreePNHelper (root)       │
│  UI · state          │                                    │  menjalankan core · MAC    │
│  parser · config     │                                    │  pembersihan route/DNS     │
└──────────────────────┘                                    └─────────────┬──────────────┘
                                                                          │ spawn
                                                          ┌───────────────▼──────────────┐
                                                          │  sing-box (universal binary) │
                                                          │  TUN + routing per-proses    │
                                                          └──────────────────────────────┘
```

- **UI** — aplikasi SwiftUI (API macOS 13+), universal binary, state disimpan sebagai JSON di `~/Library/Application Support/FreePN/`
- **Core** — [sing-box](https://github.com/SagerNet/sing-box) 1.13.6 (GPL-3.0), dibundel sebagai universal binary dan dibungkus protokol `VPNCore` agar bisa diganti
- **Helper berhak istimewa** — daemon launchd root kecil (`com.freepn.helper`) yang menjalankan core dan mengubah MAC. Helper hanya menerima **daftar perintah XPC yang di-whitelist** (start/stop core, status, get/set/restore MAC) dari FreePN yang terverifikasi code-sign — tidak pernah shell bebas
- **Keamanan config** — setiap config yang dihasilkan divalidasi dengan `sing-box check` sebelum connect; DNS sadar-split (DoH lewat proxy untuk trafik tunnel, DNS sistem untuk direct) agar tidak bocor
- **Tanpa App Sandbox, tidak di Mac App Store** (helper berhak istimewa tidak kompatibel dengan sandbox) — didistribusikan sebagai DMG

## Baca ini sebelum memakai node gratis

> [!WARNING]
> - FreePN **tidak** menjalankan server VPN apa pun. Aplikasi mengumpulkan feed subscription publik gratis dari pihak ketiga yang tingkat kepercayaannya tidak diketahui dan bervariasi.
> - **Jangan pernah login ke akun sensitif** (bank, email utama) saat terhubung lewat node gratis.
> - FreePN **bukan alat anonimitas**. Tidak ada node gratis yang layak dipercaya untuk pekerjaan yang kritis terhadap privasi.
> - Node gratis bisa melihat trafik yang tidak terenkripsi dan bisa dioperasikan siapa saja. Perlakukan seperti Wi-Fi publik yang tidak Anda kendalikan.
> - Feed gratis sering berotasi dan hilang. Kalau node berhenti berfungsi, refresh sumber Anda — itu normal.
> - Pengecekan IP publik (api.ipify.org) **mati secara default**; tidak ada yang dikirim ke mana pun kecuali Anda memintanya.

## Unduh

Ambil DMG terbaru dari **[Releases](https://github.com/YandiDesign/FreePN/releases/latest)**.

**Kebutuhan:** macOS 13 Ventura atau lebih baru · Apple Silicon atau Intel (universal binary)

> [!IMPORTANT]
> DMG ditandatangani dengan sertifikat Apple Development, **belum di-notarize**, jadi Gatekeeper akan memberi peringatan saat pertama kali dibuka. Klik kanan aplikasi → **Open**, atau hapus flag karantina:
> ```bash
> xattr -dr com.apple.quarantine /Applications/FreePN.app
> ```

### Menjalankan pertama kali

1. Seret **FreePN.app** ke `/Applications` (di dalam DMG sudah ada symlink-nya)
2. Buka aplikasinya — onboarding menjelaskan soal helper berhak istimewa dan kenapa dibutuhkan
3. **Pasang helper** lewat prompt admin sekali-klik (atau `sudo ./scripts/install-helper.sh` kalau build dari source)
4. Masuk ke **Sources** → pilih feed pilihan (atau tambahkan milik Anda) → **Refresh**
5. Masuk ke **Servers** → **Ping All** → connect ke node terbaik

## Build dari source

**Prasyarat:** macOS 13+, Xcode 14.3 atau lebih baru. Tidak butuh Homebrew.

```bash
git clone https://github.com/YandiDesign/FreePN.git
cd FreePN

# 1. Ambil core VPN: mengunduh rilis resmi sing-box untuk kedua arsitektur,
#    lalu lipo ke FreePN/Resources/sing-box
./scripts/build-core.sh          # default v1.13.6, bisa dioverride: SINGBOX_VERSION=vX.Y.Z

# 2a. Build dan jalankan (Debug, universal)
./scripts/run-local.sh

# 2b. Atau build DMG Release ke folder dist/
./scripts/make-dmg.sh
```

**Pasang helper berhak istimewa** (dibutuhkan untuk mode TUN):

- Dari aplikasi: onboarding / Settings menawarkan instalasi sekali-klik dengan satu prompt admin, atau
- Manual:

```bash
xcodebuild -project FreePN.xcodeproj -target FreePNHelper -configuration Release \
  -destination 'platform=macOS' ONLY_ACTIVE_ARCH=NO ARCHS='arm64 x86_64' build

sudo ./scripts/install-helper.sh              # pasang / pasang ulang
sudo ./scripts/install-helper.sh --uninstall   # copot
```

> [!NOTE]
> Pasang ulang helper setelah binary helper berubah. Kalau Connect melaporkan "helper unavailable", pasang lagi atau cek `launchctl print system/com.freepn.helper`.

**Jalankan test** (574 unit test / 35 file: parser, config builder, validasi `sing-box check` sungguhan, keputusan split-tunnel, kejujuran ping, paritas lokalisasi, keamanan helper):

```bash
xcodebuild -project FreePN.xcodeproj -scheme FreePN -destination 'platform=macOS' test
```

**Catatan signing:** project dikonfigurasi untuk team `4DQ23N8GY5`. Karena tanpa entitlement (App Sandbox mati), Personal Team gratis juga bisa — atur team Anda sendiri di *Signing & Capabilities* bila perlu.

**Regenerasi tabel GeoIP offline** (opsional — butuh `GeoLite2-City.mmdb` dari MaxMind dan `pip install maxminddb`):

```bash
python3 scripts/build-geolite2.py path/to/GeoLite2-City.mmdb
```

## Struktur Project

```
FreePN/                   Sumber aplikasi
  App/                    entry point, state pusat, menu bar extra
  Core/
    Models/               ProxyNode, Source, PingResult
    Parsing/              Clash YAML · share link · auto-detect · dedup
    Persistence/          JSON store, settings
    Ping/                 probe TCP + end-to-end, CPU governor
    Subscription/         pengambilan feed, resolver URL bertanggal
    VPN/                  config builder, connection manager, helper install, health
  DesignSystem/           tema, kartu, badge
  Localization/           Localizable.strings en + id
  UI/                     Connect · Servers · Sources · Split Tunneling · MAC · Settings
  Resources/              Info.plist, assets, tabel GeoIP, sing-box (diunduh)
  Vendor/DotMap/          renderer peta titik-titik MIT (vendored)
FreePNHelper/             daemon XPC root (jalankan core, MAC spoofing)
Shared/                   protokol XPC, logika split-tunnel, validator
FreePNTests/              35 file test / 574 test
scripts/                  build-core · run-local · install-helper · make-dmg · notarize · geoip
DECISIONS.md              catatan rekayasa — 98 keputusan terdokumentasi
LICENSES/                 lisensi pihak ketiga dan atribusi
```

## Pemecahan Masalah

| Gejala | Yang perlu dicek |
|---|---|
| "Helper unavailable" / Connect gagal | `launchctl print system/com.freepn.helper`, lalu pasang ulang: `sudo ./scripts/install-helper.sh` |
| Core gagal start | `/var/log/freepn-core-stderr.log` (cuplikannya juga tampil di panel Health aplikasi) |
| Log helper | `/var/log/freepn-helper.log` |
| Keputusan VPN | `log show --predicate 'subsystem == "com.freepn.app"' --last 10m` |
| Semua node jadi "dead" setelah refresh | Feed gratis berotasi tiap hari — refresh sumber; kalau jaringan Anda memblokir host uji default, ganti di Settings → Internet test address |
| Node ping bagus tapi tidak ada internet | Itulah gunanya ping end-to-end default — fast TCP ping hanya membuktikan server merespons |
| Perubahan MAC gagal | MAC spoofing sempat memutus jaringan dan tidak didukung di semua rilis/antarmuka macOS; aplikasi memverifikasi hasil tulis dan melaporkannya secara jujur |

## Lokalisasi

Aplikasi tersedia dalam **Bahasa Indonesia** dan **English** (`FreePN/Localization/{en,id}.lproj`); `scripts/check-localization.sh` memastikan set kunci kedua bahasa identik. Dokumentasi ini juga bilingual:

- [English](README.md)
- [Bahasa Indonesia](README.id.md) (file ini)

## Lisensi

[MIT](LICENSE) © 2026 YandiDesign — bebas dipakai, di-fork, dan didistribusikan ulang, **dengan atribusi**: sertakan notice copyright dan kredit di layar About aplikasi. Persyaratan atribusi lengkap ada di file [LICENSE](LICENSE).

Komponen pihak ketiga:

| Komponen | Lisensi |
|---|---|
| [sing-box](https://github.com/SagerNet/sing-box) (core bawaan) | GPL-3.0 |
| [DotMap](https://github.com/spilneo/DotMap) (renderer peta, vendored) | MIT |
| Data GeoLite2 City (MaxMind) | GeoLite2 EULA |
| Data GeoNames | CC BY 4.0 |

Detail lengkap di [LICENSES/THIRD-PARTY.txt](LICENSES/THIRD-PARTY.txt) dan layar About aplikasi.

---

<div align="center">
<sub>Dibuat oleh <a href="https://github.com/YandiDesign">YandiDesign</a> · Kalau FreePN berguna, bintangnya sangat membantu.</sub>
</div>
