# FreePN — Prompt Pengembangan Aplikasi macOS

## 0. Peran & Cara Kerja

Kamu adalah **senior macOS engineer** (Swift, SwiftUI, AppKit, networking, launchd/XPC, desain UI Apple). Tugasmu: membangun aplikasi macOS lengkap bernama **FreePN** sebagai **project Xcode yang benar-benar bisa di-build dan dijalankan**, bukan potongan kode terpisah.

Aturan kerja:

1. Kerjakan per milestone (lihat bagian 12). Setiap milestone harus compile dan berjalan sebelum lanjut ke berikutnya.
2. Jika ada keputusan teknis yang ambigu, pilih **default yang tertulis di dokumen ini**, catat alasannya di `DECISIONS.md`, dan lanjut. Jangan berhenti untuk bertanya kecuali benar-benar buntu.
3. Jangan mengarang API. Jika tidak yakin sebuah API tersedia di macOS 13, gunakan alternatif yang pasti ada atau beri guard `#available`.
4. Semua teks yang tampil ke pengguna **wajib** lewat sistem lokalisasi (bagian 9). Tidak boleh ada string hardcoded di UI.

---

## 1. Ringkasan Produk

**FreePN** adalah client VPN gratis untuk macOS. Aplikasi mengambil daftar server dari subscription VPN gratis publik, menampilkan jenis protokol tiap server (Trojan / VMess / SS), mengukur ping, mendukung split tunneling per-aplikasi (mode inclusive dan exclusive), serta MAC address spoofing. Tampilan native macOS dengan gaya **Liquid Glass** modern, tersedia dalam **Bahasa Indonesia dan English**.

**Di luar cakupan (non-goals):**

- Tidak ada akun, login, pembayaran, iklan, maupun telemetri/analytics.
- Tidak menjalankan atau menjual server VPN sendiri.
- Tidak didistribusikan lewat Mac App Store (sandbox tidak kompatibel dengan helper berhak istimewa). Distribusi: DMG yang di-notarize.

---

## 2. Persyaratan Platform

| Item | Nilai |
|---|---|
| Minimum OS | **macOS 13 Ventura** (`MACOSX_DEPLOYMENT_TARGET = 13.0`) |
| Arsitektur | **Universal Binary: arm64 + x86_64** (`ARCHS = arm64 x86_64`, `ONLY_ACTIVE_ARCH = NO` untuk Release) |
| Bahasa | Swift 5.9+, UI dengan SwiftUI, AppKit hanya bila perlu |
| Toolchain | Xcode 26 (untuk API Liquid Glass asli). Project tetap harus bisa dibuild dengan Xcode 15 lewat guard `#if compiler(>=6.2)` |
| Sandbox | **Nonaktif** (App Sandbox off), Hardened Runtime on |

**Batasan API karena target macOS 13.** Jangan memakai API berikut tanpa guard `#available`, dan sediakan fallback:

- `SwiftData` (butuh macOS 14) → gunakan `Codable` + JSON di `~/Library/Application Support/FreePN/`.
- Macro `@Observable` (butuh macOS 14) → gunakan `ObservableObject` + `@Published`.
- `glassEffect`, `GlassEffectContainer`, `.buttonStyle(.glass)` (butuh macOS 26) → lihat bagian 8.
- `.containerBackground(for: .window)` dan API window baru macOS 15 → beri fallback.

API yang aman dipakai di macOS 13 dan dianjurkan: `NavigationSplitView`, `MenuBarExtra`, `SMAppService`, `Table`, `Network.framework`, `NSXPCConnection.setCodeSigningRequirement(_:)`, String Catalog (`.xcstrings`, dikompilasi ke format lama saat build).

---

## 3. Arsitektur

```
┌────────────────────────────┐        XPC (code-signing check)       ┌───────────────────────────────┐
│  FreePN.app  (SwiftUI)     │ ◄───────────────────────────────────► │  FreePNHelper (daemon, root)  │
│  UI, state, parser, ping,  │                                       │  - menjalankan core (TUN)     │
│  subscription, config gen  │                                       │  - MAC spoof (ifconfig)       │
└────────────────────────────┘                                       │  - cleanup route/DNS          │
                                                                     └──────────────┬────────────────┘
                                                                                    │ spawn
                                                                     ┌──────────────▼────────────────┐
                                                                     │  sing-box (universal binary)  │
                                                                     │  TUN + routing per-proses     │
                                                                     └───────────────────────────────┘
```

**Core VPN: sing-box** (default). Alasan: mendukung VMess, Trojan, Shadowsocks, inbound TUN, aturan routing berbasis proses (`process_name`, `process_path`, `process_path_regex`) di macOS, aturan DNS, dan Clash API untuk statistik. Bungkus di protokol `VPNCore` agar bisa diganti ke mihomo bila perlu.

- Pin satu versi sing-box (≥ 1.10) dan gunakan skema config yang sesuai versi itu. **Validasi tiap config yang dihasilkan** dengan `sing-box check -c <file>` sebelum dijalankan.
- Build core untuk `darwin/arm64` dan `darwin/amd64`, gabungkan dengan `lipo -create`. Simpan skripnya di `scripts/build-core.sh`.
- **Cek lisensi core** (sing-box dan mihomo berlisensi GPL-3.0, Xray-core MPL-2.0; verifikasi sendiri) dan cantumkan di `LICENSES/` serta layar About.

**Helper berhak istimewa:** daftarkan dengan **`SMAppService.daemon(plistName:)`** (macOS 13+). Plist di `Contents/Library/LaunchDaemons/`, pengguna menyetujui di System Settings → General → Login Items & Extensions. Tampilkan layar onboarding yang menjelaskan hal ini dengan jelas dan tombol untuk membuka pengaturannya.

**Keamanan XPC:** helper hanya menerima koneksi dari FreePN.app. Gunakan `setCodeSigningRequirement` dengan requirement Team ID + bundle ID. Helper hanya mengekspos perintah yang di-whitelist (start/stop core, status, set/restore MAC), **tidak** menerima perintah shell bebas.

*Alternatif (tidak dipilih secara default):* `NEPacketTunnelProvider` (Network Extension). Hanya dipakai bila ada Apple Developer account berbayar dengan entitlement Network Extension; catat di `DECISIONS.md` bila dipertimbangkan.

---

## 4. Sumber Subscription

Sumber bawaan (semua aktif secara default; tanda ★ = prioritas dari pemilik proyek, di-fetch pertama dan ditampilkan paling atas):

| # | Nama | URL | ★ |
|---|---|---|---|
| 1 | OpenProxyList | `https://openproxylist.com/v2ray/rawlist/subscribe` | |
| 2 | Au1rxx | `https://raw.githubusercontent.com/Au1rxx/free-vpn-subscriptions/main/output/clash.yaml` | |
| 3 | EbraSha | `https://raw.githubusercontent.com/ebrasha/free-v2ray-public-list/refs/heads/main/V2Ray-Config-By-EbraSha-All-Type.txt` | |
| 4 | NodeFree | `https://nodefree.org/dy/2024/07/20240725.yaml` | ★ |
| 5 | Mfuu | `https://raw.githubusercontent.com/mfuu/v2ray/master/clash.yaml` | |
| 6 | Anaer | `https://raw.githubusercontent.com/anaer/Sub/main/clash.yaml` | ★ |
| 7 | Ermaozi | `https://raw.githubusercontent.com/ermaozi/get_subscribe/main/subscribe/clash.yml` | ★ |
| 8 | Learnhard-cn | `https://cdn.jsdelivr.net/gh/vxiaov/free_proxies@main/clash/clash.provider.yaml` | |
| 9 | OpenRunner | `https://freenode.openrunner.net/uploads/20240617-clash.yaml` | ★ |
| 10 | Xrayfree | `https://tt.vg/freeclash` | |

Format tiap sumber **dideteksi otomatis oleh parser**, bukan di-hardcode per sumber.

### 4.1 URL bertanggal (penting)

URL #4 (NodeFree) dan #9 (OpenRunner) mengandung **tanggal di path** sehingga hampir pasti sudah kedaluwarsa. Implementasikan **resolver URL template**:

- `https://nodefree.org/dy/{yyyy}/{MM}/{yyyyMMdd}.yaml`
- `https://freenode.openrunner.net/uploads/{yyyyMMdd}-clash.yaml`

Resolver mencoba tanggal hari ini (zona WIB dan UTC), lalu mundur sampai 7 hari. URL pertama yang HTTP 200 **dan** berhasil di-parse (≥ 1 node) dipakai dan di-cache. Jika semua gagal, tandai sumber **"Tidak tersedia / Unavailable"** tanpa crash, dan biarkan pengguna mengedit URL-nya. Pola tanggal di atas adalah asumsi dari URL contoh; jika tidak cocok, status error harus jelas.

### 4.2 Perilaku subscription service

- Fetch paralel antar sumber (`TaskGroup`), timeout 15 detik per sumber, batas ukuran respons 10 MB, ikuti redirect (URL #10 adalah shortlink).
- Set header `User-Agent` yang umum diterima server subscription (mis. `clash.meta`), sebagian server mengembalikan konten berbeda per UA.
- Cache hasil per sumber di disk dengan TTL (default 6 jam). Saat offline atau sumber gagal, tampilkan cache terakhir dengan label "diperbarui X lalu".
- Refresh manual (tombol + ⌘R) dan refresh otomatis berkala (opsi: mati / 1 / 3 / 6 / 12 jam).
- Per sumber: toggle aktif/nonaktif, jumlah node, waktu update terakhir, status (OK / Gagal / Kedaluwarsa), dan alasan gagal yang terlokalisasi.
- Pengguna bisa **menambah, mengedit, menghapus sumber kustom** (URL) dan mengimpor satu link `vmess://`, `trojan://`, `ss://` dari clipboard.
- **Deduplikasi** node lintas sumber berdasarkan hash `(protocol, host, port, credential, transport, path, sni)`.
- Parsing dan dedup berjalan di background (`actor`), UI tidak boleh freeze meski total node ribuan.

---

## 5. Parsing & Model Data

### 5.1 Protokol

Wajib didukung dan **ditampilkan sebagai badge** di UI: **Trojan**, **VMess**, **SS** (Shadowsocks). Protokol lain (vless, hysteria, tuic, dst.) **dilewati**, dengan jumlahnya dicatat di log sumber ("N node tidak didukung"). Susun parser agar mudah ditambah protokol baru.

### 5.2 Format masukan

Deteksi otomatis, urutan: (1) YAML Clash dengan key `proxies:` (termasuk format *provider*), (2) teks base64 (standar dan URL-safe, toleran padding hilang) yang berisi share-link, (3) teks polos dengan satu share-link per baris.

- **YAML:** gunakan library [Yams](https://github.com/jpsim/Yams) via Swift Package Manager. Petakan `type: vmess | trojan | ss` beserta `uuid`, `alterId`, `cipher`, `password`, `tls`, `sni`/`servername`, `skip-cert-verify`, `network` (tcp/ws/grpc/h2), `ws-opts`, `grpc-opts`, `plugin`, `plugin-opts`.
- **`vmess://`**: base64 JSON (`ps, add, port, id, aid, scy, net, type, host, path, tls, sni`).
- **`trojan://`**: `password@host:port?sni=&type=&path=&host=&allowInsecure=#nama`.
- **`ss://`**: format SIP002 (`base64(method:password)@host:port#nama`) **dan** format lama (`base64(method:password@host:port)`).
- Entri rusak: lewati, jangan menghentikan parsing sumber. Validasi host tidak kosong dan port 1–65535.

### 5.3 Model (acuan)

```swift
enum NodeProtocol: String, Codable, CaseIterable {
    case trojan, vmess, shadowsocks
    var badgeTitle: String {
        switch self {
        case .trojan: return "Trojan"
        case .vmess: return "VMess"
        case .shadowsocks: return "SS"
        }
    }
}

struct ProxyNode: Identifiable, Codable, Hashable {
    let id: String            // hash dedup (lihat 4.2)
    var name: String
    var proto: NodeProtocol
    var host: String
    var port: Int
    var credential: String    // uuid (vmess) / password (trojan, ss)
    var cipher: String?       // vmess security / ss method
    var alterId: Int?
    var transport: Transport  // tcp | ws | grpc | http
    var transportPath: String?
    var transportHost: String?
    var tls: TLSOptions?      // enabled, sni, allowInsecure
    var sourceID: String
    var countryCode: String?  // dari emoji bendera/kode negara di nama, jika ada
}
```

Status runtime (hasil ping, favorit, node terakhir dipakai) disimpan **terpisah** dari `ProxyNode`.

---

## 6. Fitur Inti

### 6.1 Koneksi VPN

- Alur: pilih server → `ConfigBuilder` menghasilkan config sing-box → validasi → kirim ke helper via XPC → helper menjalankan core (TUN, `auto_route`) → UI menampilkan status.
- Status: Disconnected, Connecting, Connected, Disconnecting, Error (dengan pesan terlokalisasi).
- Tampilkan di layar utama: server aktif, badge protokol, durasi koneksi, kecepatan up/down (Clash API sing-box), dan opsional IP publik (toggle di Settings, default mati demi privasi).
- Tombol **Quick Connect**: pilih node dengan ping terendah dari hasil ping terakhir.
- **Cleanup wajib:** saat app di-quit, crash, atau helper menerima disconnect, route dan DNS harus pulih seperti semula. Helper memantau koneksi XPC dan membersihkan sendiri jika app mati.
- Reconnect otomatis setelah wake dari sleep dan saat jaringan berubah (`NWPathMonitor`), dengan opsi di Settings.
- *Opsional:* auto-failover ke node terbaik berikutnya bila node aktif mati.

### 6.2 Daftar server & tipe VPN

- Tabel/daftar server yang **virtualized** (`Table` atau `LazyVStack`), mulus untuk ≥ 5.000 baris.
- Kolom: favorit ★, bendera/negara, nama, **badge protokol (Trojan / VMess / SS)**, sumber, ping (ms), aksi.
- Warna badge: Trojan = merah, VMess = biru, SS = ungu. Jangan mengandalkan warna saja (badge selalu berteks).
- Pencarian, filter protokol, filter sumber, sorting (ping, nama, protokol), dan context menu (Connect, Ping, Copy Link, Favorit).

### 6.3 Ping

Dua cara, keduanya wajib:

- **Ping All Server:** tombol toolbar + ⌘⇧P. Jalankan paralel dengan batas konkurensi (default 64, bisa diatur), progress bar (`123/850`), hasil muncul live, bisa **dibatalkan**, dan otomatis mengurutkan setelah selesai (opsi).
- **Ping satu server:** tombol di tiap baris dan lewat context menu.

Metode pengukuran:

- **Default: TCP handshake latency** ke `host:port` memakai `NWConnection` (waktu sampai state `.ready`), timeout 3 detik. Resolusi DNS tidak dihitung dalam latensi. ICMP **tidak** dipakai (butuh raw socket dan sering diblokir server).
- **Real delay (opsional, untuk server terpilih/terhubung):** URL test lewat core ke `http://www.gstatic.com/generate_204` memakai endpoint delay Clash API. Ini menunjukkan apakah node benar-benar bisa dipakai, bukan sekadar port terbuka.
- **Proses FreePN sendiri harus selalu di-bypass dari tunnel** (aturan `direct`), supaya ping dan fetch subscription mengukur jalur langsung dan tidak ikut terowong.
- Skala warna: < 150 ms hijau, 150–400 ms kuning/oranye, > 400 ms merah, timeout = "Timeout" abu-abu dan node ditandai mati (bisa disembunyikan lewat filter).

### 6.4 Split Tunneling (Inclusive & Exclusive)

Pengguna memilih aplikasi mana yang lewat VPN atau tidak.

| Mode | Perilaku |
|---|---|
| **Inclusive** | Hanya aplikasi terpilih yang lewat VPN. Semua lainnya langsung (direct). |
| **Exclusive** | Aplikasi terpilih **tidak** lewat VPN (bypass). Semua lainnya lewat VPN. |

Implementasi:

- Routing berbasis proses di core: Inclusive → `rules: [app terpilih → proxy]`, `final: direct`. Exclusive → `rules: [app terpilih → direct]`, `final: proxy`.
- Cocokkan **seluruh isi bundle**, bukan hanya executable utama, dengan `process_path_regex` pada path `.app` (di-escape dengan benar). Ini penting agar helper process (Chrome Helper, aplikasi Electron, dll.) ikut terdeteksi.
- Selalu direct apa pun modenya: jaringan lokal/private (RFC1918, link-local, multicast), IP server proxy itu sendiri (cegah routing loop), proses FreePN, dan proses core. Gunakan `auto_detect_interface`.
- **Pemilih aplikasi:** pindai `/Applications`, `~/Applications`, `/System/Applications` (baca `Info.plist`: nama, bundle ID, ikon via `NSWorkspace`). Tambahan: "Pilih dari aplikasi yang sedang berjalan" dan "Tambah executable manual" (file picker untuk binary CLI seperti `curl` atau `ssh`). Ada pencarian dan toggle per aplikasi.
- **Daftar app disimpan terpisah per mode** (`inclusiveApps`, `exclusiveApps`), sehingga berpindah mode tidak menghapus pilihan.
- Perubahan saat sedang terhubung: terapkan lewat reload/restart core singkat dengan debounce, tanpa memutus UI.
- Peringatan UI: mode Inclusive dengan daftar kosong = tidak ada trafik yang lewat VPN; tampilkan banner. Beri catatan bahwa layanan sistem macOS tertentu tidak selalu bisa dicocokkan berdasarkan proses.
- DNS: pastikan kebocoran DNS dicegah (aturan DNS mengikuti keputusan routing proses yang sama) dan tidak ada DNS leak untuk aplikasi yang lewat VPN.

### 6.5 MAC Spoofing

Fitur di panel "MAC Address":

- Daftar interface dari `networksetup -listallhardwareports` (Wi-Fi, Ethernet, dll.), tampilkan MAC saat ini dan **MAC hardware asli**.
- Aksi: **Randomize**, **Set Custom** (input dengan validasi), **Restore ke asli**.
- Opsi: random MAC otomatis tiap kali connect, dan auto-restore saat app keluar atau disconnect.
- MAC acak harus valid: **unicast** (bit 0 byte pertama = 0) dan **locally administered** (bit 1 = 1). Format `xx:xx:xx:xx:xx:xx`, validasi dengan regex ketat.
- Eksekusi **hanya di helper**, memakai `Process` dengan **array argumen** (tidak pernah string shell). Nama interface divalidasi `^en[0-9]+$`. Perintah dasar: `ifconfig <iface> ether <mac>`.
- Untuk Wi-Fi: matikan radio sebentar (`networksetup -setairportpower <device> off`), ubah MAC, lalu nyalakan lagi. Setelah ubah, **baca ulang MAC dan bandingkan**; jika gagal, tampilkan error terlokalisasi, jangan diam-diam dianggap berhasil.
- Catatan jujur di UI: pada macOS/Apple Silicon terbaru perubahan MAC Wi-Fi bisa dibatasi atau tidak konsisten, perubahan hilang setelah reboot, jaringan akan terputus sesaat, dan macOS 15+ punya fitur "Private Wi-Fi Address" per jaringan yang bisa berinteraksi dengan ini.

### 6.6 Menu Bar

`MenuBarExtra` (macOS 13): status koneksi, tombol Connect/Disconnect, server aktif, Quick Connect, Ping All, pilih mode split tunnel, buka jendela utama, Quit.

### 6.7 Settings

Bahasa (System / Indonesia / English), launch at login (`SMAppService.mainApp`), auto-refresh subscription, konkurensi ping, auto-reconnect, tampilkan IP publik, reset data. Layar About berisi versi, lisensi pihak ketiga, dan tautan sumber.

---

## 7. Keamanan, Privasi & Etika Produk

- **Node gratis publik bersifat tidak tepercaya.** Operator node dapat melihat atau memanipulasi trafik yang tidak terenkripsi. Tampilkan peringatan jelas di onboarding dan Settings (terlokalisasi): jangan login ke akun sensitif (bank, email utama) lewat node gratis, dan FreePN **bukan** alat anonimitas.
- Jangan pernah mengklaim "aman 100%" atau "anonim" di UI maupun README.
- Tanpa telemetri. Satu-satunya trafik jaringan app: fetch subscription, ping, dan (opsional, default mati) cek IP publik.
- **Redaksi log:** UUID, password, dan link lengkap tidak boleh muncul di log. Tampilkan hanya `host:port` yang disamarkan atau nama node.
- Helper: whitelist perintah, validasi semua input, verifikasi code signature klien XPC, tidak menerima path/argumen sembarang.
- Pengguna bertanggung jawab atas kepatuhan hukum di negaranya. Cantumkan ini singkat di Terms/About.

---

## 8. Desain UI/UX: macOS + Liquid Glass

**Prinsip:** terasa seperti aplikasi bawaan Apple. Native, bersih, hierarkis, mendukung Light/Dark, dan memakai SF Pro serta SF Symbols.

**Struktur jendela:** `NavigationSplitView` dengan sidebar translucent berisi: *Connect*, *Servers*, *Sources*, *Split Tunneling*, *MAC Address*, *Settings*. Ukuran minimum jendela ±900×600. Dukung penuh navigasi keyboard, VoiceOver, dan Dynamic Type bila relevan.

**Liquid Glass (strategi bertingkat):**

- **macOS 26+:** pakai API asli (`glassEffect(_:in:)`, `GlassEffectContainer`, `.buttonStyle(.glass)`), dibungkus guard `#if compiler(>=6.2)` **dan** `if #available(macOS 26, *)`.
- **macOS 13–25 (fallback):** `Material` (`.ultraThinMaterial` / `.regularMaterial`) atau `NSVisualEffectView` (`.sidebar`, `.hudWindow`), ditambah stroke tipis gradien dan highlight halus agar terasa "kaca".
- Buat **satu abstraksi** (mis. `GlassBackground` / `.freepnGlass()` view modifier) sehingga seluruh app memakai satu jalur; tidak ada percabangan `#available` yang tersebar di banyak view.
- Terapkan glass pada **lapisan kontrol dan navigasi** (sidebar, toolbar, kartu status, tombol), bukan pada lapisan konten padat seperti baris tabel yang panjang.
- Hormati **Reduce Transparency** dan **Reduce Motion** (`accessibilityReduceTransparency`, `accessibilityReduceMotion`): ganti ke latar solid dan matikan animasi besar.

**Layar Connect:** tombol Connect besar dan melingkar (kaca) dengan animasi halus antar status, ring status (hijau = tersambung, kuning = menyambung, abu = putus), nama server + badge protokol + ping, durasi, kecepatan up/down.

**Gaya:** grid 8 pt, radius kartu 20–26 pt, badge berbentuk kapsul, aksen mengikuti `accentColor` sistem, animasi memakai spring bawaan SwiftUI. Ikon aplikasi bergaya kaca (gunakan Icon Composer `.icon` untuk macOS 26 dan set `AppIcon` PNG sebagai fallback).

---

## 9. Multibahasa (Indonesia & English)

- Gunakan **String Catalog** `Localizable.xcstrings` dengan dua bahasa: `en` (development language/fallback) dan `id`.
- Default mengikuti bahasa sistem; di Settings pengguna dapat memilih **System / Bahasa Indonesia / English** dan perubahan harus **langsung berlaku tanpa restart** (injeksi `Locale` lewat environment SwiftUI; sediakan helper `L10n` untuk string non-SwiftUI seperti notifikasi, menu bar, dan pesan error dari helper).
- Semua teks wajib terlokalisasi, termasuk pesan error, peringatan keamanan, onboarding, dan menu bar. Gunakan pluralization (`%lld server`) dan format tanggal/angka sesuai locale.
- Sertakan skrip/test yang memastikan **tidak ada key yang belum diterjemahkan** di salah satu bahasa.
- Uji dengan argumen `-AppleLanguages "(id)"` dan `"(en)"`.

---

## 10. Struktur Proyek

```
FreePN/
├── FreePN.xcodeproj
├── FreePN/                      # target app
│   ├── App/                     # FreePNApp, AppState, MenuBar
│   ├── UI/                      # Connect, Servers, Sources, SplitTunnel, MacSpoof, Settings, Onboarding
│   ├── DesignSystem/            # GlassBackground, Badge, Theme
│   ├── Core/
│   │   ├── Models/              # ProxyNode, Source, PingResult, SplitTunnelConfig
│   │   ├── Parsing/             # ClashYAMLParser, ShareLinkParser, Base64Detector
│   │   ├── Subscription/        # SubscriptionService, SourceResolver, Cache
│   │   ├── Ping/                # TCPPinger, RealDelayTester, PingCoordinator
│   │   ├── VPN/                 # VPNCore, SingBoxConfigBuilder, ConnectionManager
│   │   └── Persistence/         # JSON store
│   ├── Localization/            # Localizable.xcstrings, L10n.swift
│   └── Resources/               # core/sing-box (universal), Assets.xcassets
├── FreePNHelper/                # target daemon (XPC, CoreRunner, MacSpoofer)
├── Shared/                      # protokol XPC, konstanta, validator
├── FreePNTests/
├── scripts/                     # build-core.sh, make-dmg.sh, notarize.sh
├── LICENSES/
├── DECISIONS.md
└── README.md                    # dua bahasa (ID + EN)
```

---

## 11. Build, Signing & Distribusi

- Release harus menghasilkan **universal binary**; verifikasi dengan `lipo -archs` (harus `x86_64 arm64`) untuk app, helper, **dan** binary core.
- Tanda tangan: Developer ID Application, Hardened Runtime, helper dan core ditandatangani dengan Team ID yang sama. Notarize dengan `notarytool` lalu staple.
- Skrip `make-dmg.sh` menghasilkan DMG, dan `README` menjelaskan langkah menyetujui helper di System Settings.
- Bila tidak ada sertifikat, sediakan mode Debug (ad-hoc signing) untuk pengembangan lokal beserta petunjuk mematikan pemeriksaan yang relevan.

---

## 12. Milestone

1. **Fondasi:** project universal macOS 13, tema Glass (dengan fallback), `NavigationSplitView`, lokalisasi ID/EN, onboarding.
2. **Subscription & parser:** 10 sumber, resolver URL bertanggal, parser YAML/base64/share-link, dedup, cache, UI Sources + Servers dengan badge protokol.
3. **Ping:** TCP ping satu per satu + Ping All (konkurensi, progress, cancel, sort).
4. **Helper & core:** `SMAppService` daemon, XPC aman, jalankan sing-box TUN, connect/disconnect, cleanup, status + statistik.
5. **Split tunneling:** pemilih aplikasi, mode Inclusive/Exclusive, hot reload.
6. **MAC spoof:** list interface, randomize/custom/restore, verifikasi hasil.
7. **Poles:** menu bar, auto-reconnect, Reduce Transparency/Motion, aksesibilitas, tes, signing + DMG, README.

---

## 13. Kriteria Selesai (Definition of Done)

- [ ] Build Release sukses, `lipo -archs` menunjukkan `x86_64 arm64` untuk app, helper, dan core; berjalan di macOS 13 sampai versi terbaru.
- [ ] 10 sumber terdaftar; sumber bertanggal mengalami fallback tanggal atau berstatus "tidak tersedia" tanpa crash.
- [ ] Node Trojan, VMess, SS terparse dari format YAML, base64, dan teks polos; badge protokol tampil benar.
- [ ] Ping All dan ping per server berfungsi, bisa dibatalkan, UI tetap responsif dengan ribuan node.
- [ ] Koneksi VPN berjalan, dan setelah disconnect/quit/crash route + DNS pulih.
- [ ] Split tunneling Inclusive dan Exclusive terbukti bekerja (uji: satu app lewat VPN, satu app tidak; cek IP keluar masing-masing).
- [ ] MAC spoof: randomize, custom, restore berfungsi dan dibaca ulang untuk verifikasi.
- [ ] UI penuh dalam Indonesia dan English, tanpa string hardcoded dan tanpa key yang hilang.
- [ ] Liquid Glass asli di macOS 26+, fallback material di macOS 13–25, hormati Reduce Transparency/Motion.
- [ ] Tidak ada credential di log; helper hanya menerima perintah whitelist dari klien yang tertandatangani benar.
- [ ] Unit test: parser (fixture tiap format, termasuk SS SIP002 dan format lama), `ConfigBuilder` (snapshot untuk kedua mode split tunnel), validator MAC, `PingCoordinator` (mock).

---

## 14. Format Keluaran yang Diminta

1. Pohon file proyek lengkap.
2. Kode lengkap tiap file (bukan pseudocode), dikerjakan per milestone.
3. `scripts/` (build core universal, DMG, notarize) dan `DECISIONS.md`.
4. `README.md` dwibahasa: cara build, cara menyetujui helper, batasan yang diketahui (MAC spoof di Apple Silicon, kualitas node gratis, sumber bertanggal).
5. Daftar singkat asumsi dan hal yang perlu diverifikasi manual di akhir.
