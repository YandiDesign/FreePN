# DECISIONS.md

Catatan keputusan teknis (default dari spec, dilanjut tanpa bertanya kecuali buntu).

## Lingkungan aktual
- Xcode 14.3.1 (Swift 5.8.1), macOS 13.3 Intel, tanpa brew (brew bermasalah di mesin ini).
- Pemakaian pribadi, tanpa App Store / DMG / notarize.

## D1 — Core: sing-box prebuilt, bukan build Go
- Alasan: tanpa brew + tanpa Go di mesin ini. `scripts/build-core.sh --prebuilt` download release resmi darwin-amd64+arm64 lalu `lipo -create`.
- Pin awal: `v1.12.1` (>=1.10). Skema config mengikuti versi itu; validasi `sing-box check -c`.
- Alternatif `--source` tersedia bila kelak install Go dari pkg resmi go.dev.

## D2 — Liquid Glass hanya fallback
- Xcode 14 tidak punya `glassEffect`. Abstraksi `.freepnGlass()` berisi fallback Material + stroke gradien; guard `#if compiler(>=6.2)` disiapkan agar aktif otomatis di Xcode 26.

## D3 — Lokalisasi .strings, bukan .xcstrings
- `.xcstrings` butuh Xcode 15. Dipakai `en/id.lproj/Localizable.strings` + `scripts/check-localization.sh`. Migrasi ke catalog 1-perintah saat upgrade Xcode.

## D4 — Signing ad-hoc, Sandbox off
- Tanpa Developer ID. Helper `SMAppService.daemon` tetap ditulis sesuai spec; untuk uji lokal disediakan pesan error jelas bila registrasi daemon ditolak (mode user biasa: TUN penuh + ifconfig butuh root).

## D5 — XPC longgar untuk ad-hoc
- `setCodeSigningRequirement` ketat (Team ID) hanya bila Team ID tersedia; untuk ad-hoc cek bundle ID + path. Helper hanya whitelist start/stop/status/setMAC (tanpa shell bebas), validasi iface `^en[0-9]+$`.

## D6 — NEPacketTunnelProvider tidak dipakai
- Butuh entitlement berbayar; jalur daemon root + DMG notarize (kelak) sesuai default spec.

## D7 — Helper tidak auto-kill core saat UI putus
- `handleDisconnect()` no-op agar restart UI tidak memutus tunnel; cleanup eksplisit via stopCore/quit. Route/DNS mengandalkan TUN `auto_route` sing-box.

## D8 — Yams ditunda, parser fallback aktif
- Alasan: generator `project.pbxproj` awal salah menaruh `XCSwiftPackageProductDependency` di Frameworks phase hingga `xcodebuild` crash; dependensi dihapus agar build lokal deterministik tanpa fetch.
- `ClashYAMLParser` memakai `#if canImport(Yams)` + `parseFallback` (mendukung block-style dan flow-style `- {…}`), jadi YAML tetap terparse tanpa Yams.
- Cara menambah Yams kelak: Xcode → File → Add Package Dependencies → `https://github.com/jpsim/Yams` (upToNextMajor 5.0.0) → target FreePN. Tanpa perubahan kode.

## D9 — Bug "aplikasi tidak bekerja" (layar Connect kosong), 09-Okt-2026
- Penyebab: tidak ada fetch otomatis. `refreshAll()` hanya dipicu manual (toolbar Sources / ⌘R), jadi pengguna baru melihat daftar kosong + tombol nonaktif.
- Perbaikan: `AppState.startAutoRefreshIfNeeded()` (fetch bila `nodes.isEmpty` + timer sesuai `autoRefreshHours`), dipanggil dari `onAppear` dan setelah onboarding; guard anti-refresh ganda; empty-state di Connect dengan tombol Refresh + petunjuk buka Sources; status per sumber menampilkan detail error/unsupported; `NSAllowsArbitraryLoads` di Info.plist (redirect aneh + URL http test).

## D10 — Perbaikan "hanya 1 server + macet Menyambung", 09-Okt-2026
- Parser BUKAN penyebab: harness dengan feed asli → anaer 348 node, ermaozi 188, openproxy 79, tt 3.
- Refresh dibuat inkremental (hasil tiap sumber langsung tampil, bukan di akhir) + tombol retry per sumber.
- Connect: timeout 12 dtk anti-macet + fallback core lokal bila XPC gagal (dengan pesan jujur: TUN butuh root).
  Penyebab macet: helper ad-hoc tidak terdaftar di mach (SMAppService butuh signature berbayar).
- Solusi utama: `scripts/install-helper.sh` (sudo, tanpa sertifikat) → LaunchDaemon root + `uninstall` tersedia.
  README + onboarding diperbarui; `CoreRunner` helper juga mencari sing-box di sebelah executable.

## D11 — Sidebar macet di Connect + warning duplikat, 09-Okt-2026
- Penyebab macet: kolom detail di-hardcode `ConnectView()`; `navigationDestination(for:)` di sidebar
  tidak berpengaruh tanpa NavigationStack, jadi klik menu tidak ke mana-mana.
- Perbaikan: seleksi diangkat ke `ContentView` (`@State selection`), sidebar hanya `Label+tag`,
  detail `switch selection`. Pola ini yang benar untuk NavigationSplitView macOS 13.
- Warning duplikat `app.zen-browser.zen`: id pemindai app memakai bundleID (bisa kembar).
  Sekarang id = path unik + dedup path. Warning onChange multi-update ikut hilang
  (konflik selection vs navigation value sebelumnya).

## D12 — "Config gagal validasi" saat Connect, 09-Okt-2026
- Penyebab: config mengikuti skema sing-box lama. sing-box 1.12 mematikan
  outbound khusus lawas (`block`, `dns`) → `check -c` FATAL; format DNS server
  lawas deprecated; field `server` tidak ada di route rule; `auto_detect_interface`
  bukan field inbound TUN.
- Perbaikan di `SingBoxConfigBuilder`: hapus outbound block/dns-out; DNS format baru
  (`type https` + `type local`); loop-prevention pakai `ip_cidr` (literal IP) atau
  `domain` (hostname); TUN tanpa `auto_detect_interface`.
- Bukti: `SingBoxValidationTests` menjalankan `sing-box check -c` asli untuk
  SS/Trojan/VMess — 16/16 tests passed.

## D13 — Migrasi DNS 1.12 + TUN butuh root, 09-Okt-2026
- `check -c` masih WARN: matcher `outbound` di DNS rule deprecated → diganti
  `domain_resolver` di tiap outbound + `route.default_domain_resolver` + DNS rule
  berbasis proses (tanpa `outbound`); `final` mengikuti mode split.
- `SingBoxValidationTests` sekarang juga menggagalkan bila ada baris WARN —
  deprecation adalah bug yang tertunda.
- FATAL `configure tun interface: operation not permitted` = perilaku benar tanpa
  root; satu-satunya jalan adalah `sudo ./scripts/install-helper.sh`.

## D14 — Helper terinstal tapi tetap gagal Connect, 09-Okt-2026
- Kemungkinan kuat: helper MENOLAK path config. App menulis ke `.../T/freepn/`
  (user temp), tapi helper (sebagai root) memvalidasi terhadap temp MILIK ROOT
  yang berbeda → selalu "invalid path" → jatuh ke fallback lokal → FATAL TUN.
- Perbaikan: whitelist path diperluas (/tmp, /private/tmp, /var/folders, App Support).
- Helper 1.1 mencatat semua koneksi/perintah ke /tmp/freepn-helper.log + stdout plist.
- App tidak lagi menutupi pesan helper; cleanup core lama tiap Connect baru.

## D15 — Helper menolak path config user-temp, 09-Okt-2026
- Bukti log: `startCore(/var/folders/gj/.../T/freepn/config.json)` → `invalid path`.
  Validasi memakai `temporaryDirectory` milik proses HELPER (root, beda folder).
- Perbaikan: `Validators.isAllowedConfigPath` (prefix /tmp, /private/tmp,
  /var/folders + App Support, wajib .json, tolak `;`/newline/`..`) + unit test.

## D16 — "Tersambung" tapi IP tidak berubah, 09-Okt-2026
- Status hanya mencerminkan proses ter-spawn; core yang mati diam-diam tak ketahuan.
- Perbaikan: watchdog 5 dtk (`coreStatus` helper / `isRunning` lokal) → error jujur;
  baris "IP keluar (via VPN)" di Connect memakai SOCKS core (bukan IP langsung,
  karena proses app di-bypass dari tunnel) untuk membedakan node-mati vs TUN-bocor.

## D17 — Core mati diam-diam, alasan tak terlihat, 09-Okt-2026
- `Pipe()` tanpa pembaca bisa deadlock + alasan exit hilang.
- Perbaikan: STDOUT/STDERR core → /tmp/freepn-core-stderr.log; `coreStatus`
  menyertakan tail log; app menampilkan penyebab asli; `pkill -x sing-box`
  tiap start untuk membersihkan sisa proses (port nyangkut).

## D18 — Port 9090 bentrok, core mati saat start, 09-Okt-2026
- Bukti: `external controller listen error: bind: address already in use`.
- Perbaikan: `FreePort` probe port bebas; clash 9090+ dan mixed 1080+ dinamis
  per koneksi; stats & cek-IP mengikuti port aktif.

## D19 — Masih "core berhenti" tanpa detail + verifikasi runtime, 09-Okt-2026
- HelperLog dilindungi NSLock (XPC multi-thread); watchdog bedakan helper-mati
  vs core-mati (pesan `error_helper_gone`).
- Verifikasi langsung dengan builder ASLI: `check` lolos; `run` non-root hanya
  gagal di TUN (sesuai desain); varian tanpa TUN hidup + clash API menjawab.
  Artinya config runtime-good; sisa titik gagal di mesin user = bring-up TUN root.
- Helper 1.2 (penanda versi di log) untuk memastikan binary terinstal yang baru.

## Hasil verifikasi 09-Okt-2026 (Xcode 14.3.1, macOS 13.3 Intel)
- `xcodebuild -target FreePN -configuration Release ONLY_ACTIVE_ARCH=NO ARCHS='arm64 x86_64'`: SUCCEEDED; `lipo -archs FreePN.app/Contents/MacOS/FreePN` = `x86_64 arm64`.
- Helper Release: SUCCEEDED; `lipo -archs FreePNHelper` = `x86_64 arm64`.
- Core: `scripts/build-core.sh` → sing-box 1.12.1; `lipo -archs` = `x86_64 arm64`; terbundel di `Contents/Resources/sing-box`.
- Tests: 13/13 passed (`ParserTests` 6, `ConfigBuilderTests` 3, `ValidatorTests` 3, `PingCoordinatorTests` 1).
- `scripts/check-localization.sh`: key EN==ID.

## D20 — "Tersambung" tapi koneksi tidak jalan + IP tak berubah, 09-Okt-2026
- Bukti di mesin user:
  1. `~/Library/Application Support/FreePN/split.json` = `{"mode":"inclusive",...kosong}`.
     Mode inklusif-kosong menghasilkan `route.final=direct` + `dns.final=direct-dns`
     = TIDAK ADA trafik lewat VPN. UI tetap menulis "Tersambung" karena
     `setConnected` dipanggil saat proses ter-spawn, bukan saat trafik hidup.
  2. Port 9090 LISTEN oleh ClashFX (app lain). Config terakhir masih 9090
     (build lama sebelum probe dinamis D18, atau race) → core exit 1
     `bind: address already in use`, TUN tak pernah naik, rute default tetap via en0.
  3. `strict_route=false` + `interface_name=utun9` hardcoded: kalaupun core hidup,
     TUN tak mengambil alih default route (bocor via en0) dan rawan bentrok nama.
  4. `/traffic` clash API adalah websocket — `URLSession.data` untuk statistik
     gantung selamanya; health check harus pakai `/version`.
- Perbaikan:
  - Builder: `strict_route=true`, hapus `interface_name` (auto-assign), `mtu=9000`;
    default port 28909/28108 (di luar ekosistem Clash 9090/1080) + probe;
    `isBypassAll()` menandai inklusif-kosong.
  - ConnectionManager: TOLAK connect inklusif-kosong dengan pesan + hint
    (alih ke Eksklusif / isi daftar); verifikasi pasca-spawn sebelum connected
    (proses hidup + clash `/version` + interface 172.19.0.1 + exit-IP via SOCKS
    otomatis — node mati langsung jadi error jujur, bukan "tersambung");
    watchdog juga cek API (2x gagal = error port); statistik via websocket 3 dtk.
  - AppState: migrasi split inklusif-kosong tersimpan → eksklusif saat launch.
  - Tests: `isBypassAll`, `strict_route/auto/mtu/port` + `sing-box check -c` tetap 0 WARN.
- Cara pakai setelah update: rebuild app, launch (migrasi otomatis), pastikan
  Split Tunneling = Eksklusif (VPN penuh), Connect, tunggu verifikasi ±10 dtk.

## D21 — Tidak terbaca sebagai VPN / Filter di Settings > Network, 09-Okt-2026
- Penyebab: daemon root + sing-box `auto_route` membuat utun TANPA mendaftar
  sebagai layanan SystemConfiguration. Hanya NetworkExtension Packet Tunnel
  yang muncul di Settings > Network > VPN (dan Filters di macOS baru).
  Ini tradeoff sadar D6 (hindari entitlement berbayar), bukan bug routing.
- Perbaikan fase 1 (visibility bridge, aman, gagal-lembut di ad-hoc):
  - Target baru `FreePNTunnel` (appex Packet Tunnel, ter-embed di PlugIns) +
    `TunnelManager` (NETunnelProviderManager "FreePN") + section di Settings.
  - Provider pasang NetworkSettings TANPA routes (tidak mengintersep) agar tak
    blackhole; trafik tetap via daemon TUN. Toggle Settings memengaruhi indikator.
  - Butuh signing Personal Team (Apple ID gratis, bukan berbayar) + capability
    NetworkExtension agar entri tersimpan; ad-hoc (`-`) tetap daemon-only
    (pesan jujur di Settings, bukan crash).
- Fase 2 TODO: forwarding paket di dalam provider (Go libbox / lwIP tun2socks)
  agar toggle Settings mengendalikan trafik tanpa daemon. JANGAN set
  `includedRoutes=default` sebelum fase 2 — memutus internet.

## D22 — Race stop-lama membunuh core baru + panel izin, 09-Okt-2026
- Bukti log helper: `startCore → core spawned → (1 dtk) coreStatus: stopped tail=`
  + `core exited code=0`. Exit 0 + log kosong = SIGTERM graceful (bukan FATAL).
  Pelakunya `stopHelperCoreBestEffort()` yang fire-and-forget di awal `connect`:
  stop lama bisa tiba SETELAH spawn baru → membunuh core yang baru jalan →
  `verify-timeout` → fallback lokal (tanpa root) gagal `operation not permitted`.
  Helper padahal terpasang + running.
- Perbaikan: `stopHelperCore()` async — TUNGGU stop lama selesai (maks 3 dtk)
  sebelum tulis config + spawn. Spawn-vs-stop kini berurutan, bukan balapan.
- Permintaan user "app tidak terbaca sebagai vpn app" + info izin saat buka:
  `HealthChecker` (6 cek: helper XPC version, core bundle, mode split, port,
  entri VPN, prompt firewall) + banner merah di Connect bila ada fail +
  section Settings → Permissions & Health (dot hijau/kuning/merah/abu,
  detail + cara betulkan + tombol 1-klik "Use Exclusive" + Recheck).
  Dijalankan otomatis tiap app dibuka (`onAppear`).
- Tests: `HealthCheckTests` 2 (inklusif-kosong=fail, eksklusif=ok) — 21/21 passed.

## D23 — Paritas Urban VPN (VPN di Settings) + Windscribe (split inklusif/eksklusif), 09-Okt-2026
- Bedah bundle referensi di mesin user:
  - Urban VPN Desktop.app: `Contents/PlugIns/Urban VPN Tunnel.appex`
    (`packet-tunnel`, principal `Modul.Kelas`), entitlements
    `networkextension[app-proxy,content-filter,packet-tunnel]` +
    `vpn.api[allow-vpn]` + sandbox + App Group. Protokol di-compile di dalam
    extension (tanpa spawn binary — sandbox melarang).
  - Windscribe.app: `Contents/Library/SystemExtensions/
    ...splittunnelextension.systemextension` bertipe `app-proxy`
    (`NEProviderClasses = {app-proxy: TransparentProxyProvider}`) +
    mesin protokol sebagai helper root (`Helpers/windscribe{openvpn,wstunnel,...}`).
- Temuan bug dari perbandingan: `NSExtensionPrincipalClass` kita tanpa prefix
  modul (Urban memakai `Modul.Kelas`) → diperbaiki menjadi
  `FreePNTunnel.PacketTunnelProvider`.
- Implementasi mengikuti pola yang terbukti (bukan reinvent):
  - `FreePNTunnel.appex` (packet-tunnel, PlugIns) = entri VPN Settings ala Urban
    (fase 1: bridge indikator; fase 2 TODO: forwarding paket butuh libbox Go).
  - `FreePNSplit.systemextension` (app-proxy transparan, SystemExtensions) =
    split inklusif/eksklusif TEPAT per-app ala Windscribe: flow TCP/UDP +
    `sourceAppSigningIdentifier` → `Shared/SplitDecision` (exact/suffix match,
    dipakai app + sysext) → relay SOCKS5 ke sing-box SOCKS-only lokal
    (tanpa TUN/root) atau direct. Termasuk UDP ASSOCIATE agar DNS/QUIC ikut.
  - Builder varian `tunEnabled:false` (SOCKS-only); `SplitMode/Config` pindah ke
    Shared/ agar dikompilasi ke app + sysext; `SplitAppResolver` (path→bundleID,
    karena sysext tak bisa baca /Applications); `SplitExtensionManager`
    (aktivasi OSSystemExtension sekali + install/start via NETransparentProxyManager);
    `ConnectionManager.connect(viaExtension:)` (core lokal + install + tunggu
    proxy connected + watchdog ganda); picker mesin di Split view;
    `AppSettings.useSystemExtension` (decodeIfPresent agar settings lama aman).
- Kemasan: sysext di-embed via Run Script `ditto` → `Contents/Library/SystemExtensions`
  (CopyFiles dstSpec produk-sysext diam-diam di-skip build system; didiagnosis via
  build.db: task Copy appex ada, sysext tak pernah dibuat).
- Syarat: Personal Team signing (gratis) + 1x approve di
  Settings → General → Login Items & Extensions. Ad-hoc = daemon TUN seperti semula.
- Tests: `SplitDecisionTests` 5 + `testSocksOnlyHasNoTun` — 27/27 passed;
  `sing-box check -c` varian SOCKS-only lolos via builder yang sama.

## D24 — Helper lapor "stopped" padahal core hidup (verify-timeout), 09-Okt-2026
- Bukti: `ps` menunjukkan `sing-box run -c ...` (root, pid 24669) MASIH JALAN,
  tapi `coreStatus` selalu `stopped tail=` + `core exited code=0`.
  Penyebab: `main.swift` membuat `HelperService()` BARU per koneksi XPC —
  spawn tersimpan di runner A, status ditanya ke runner B yang kosong
  (proc=nil) → selalu stopped; stopCore ke runner C = no-op → core yatim
  menumpuk, tak terhentikan. Inilah verify-timeout yang sebenarnya
  (bukan helper belum pasang).
- Perbaikan: `HelperService.shared` singleton untuk semua koneksi;
  `CoreRunner` + NSLock (XPC multi-conn); versi naik 1.2 → **1.3**;
  `install-helper.sh` pkill sisa sing-box saat install/uninstall;
  HealthChecker menandai helper < 1.3 sebagai FAIL usang (bukan OK).
- WAJIB: `sudo ./scripts/install-helper.sh` ulang sekali (binary helper berubah).

## D26 — Log koneksi lengkap di menu Sambung, 09-Okt-2026
- Minta user: diagnosis tanpa buka Terminal.
- `ConnectionLog` (pure + path injeksi, testable): header sesi dari app
  (waktu, status, node, mesin/mode, port, exit IP) + tail 300 baris
  /tmp/freepn-helper.log + /tmp/freepn-core-stderr.log (keduanya 0644,
  readable user; ANSI dibersihkan).
- UI Connect: DisclosureGroup "Log koneksi" + Refresh/Salin/Simpan
  (NSSavePanel) + auto-refresh 2 dtk selama dibuka (stop saat tutup).
  Bungkus Group agar lolos batas 10-view ViewBuilder.
- Tests: `ConnectionLogTests` 3 — 32/32 passed.

## D25 — Helper satu-klik via dialog password macOS, 09-Okt-2026
- Keluhan: pasang helper harus via Terminal (`sudo ./scripts/install-helper.sh`).
- Solusi tanpa sertifikat berbayar: `osascript do shell script ... with
  administrator privileges` → dialog password bawaan macOS, user tinggal isi.
  (SMAppService butuh Developer ID — gagal di ad-hoc; pola osascript adalah
  praktik umum app open-source tanpa sertifikat.)
- `HelperInstaller` (Swift): skrip root lengkap dibangun murni (sh-quote aman
  untuk path ber-spasi) → tulis ke /tmp → SATU prompt password → cp binary,
  tulis plist, pkill yatim, bootstrap, verifikasi. Cancel = pesan jelas.
- Agar mandiri dari folder build: binary `FreePNHelper` di-embed ke
  `Contents/Resources` (Run Script `ditto`; dependensi target menjamin ada) +
  dependensi app→helper. Sumber = bundle sendiri.
- UI: Onboarding (ganti register SMAppService yang mati di ad-hoc) +
  tombol di baris helper Settings + banner Connect bila helper fail/stale.
- Tests: `HelperInstallerTests` (quote + isi skrip) — 29/29 passed.

## D27 — Ping harus membuktikan "bisa akses internet", bukan cuma port hidup, 10-Okt-2026
- Keluhan: banyak server yang hidup (ping TCP hijau) tapi saat disambungkan
  tidak ada internet — status "Tersambung", trafik mati.
- Bukti nyata (diuji manual dengan binary sing-box 1.12.1): dari 6 node vmess,
  `nc` menunjukkan 5 port TCP TERBUKA, tapi `/proxies/<tag>/delay` hanya 4
  yang benar-benar bisa menjangkau `generate_204`. Dua sisanya persis kasus yang
  dikeluhkan user: handshake sukses, proxy mati.
- Akar masalah: `TCPPinger` hanya mengukur handshake TCP (sampai `.ready`).
  Itu membuktikan port terbuka, bukan jalur proxy + egress-nya hidup.
- Solusi: `InternetProbe` — satu proses sing-box SEMENTARA (tanpa TUN, jadi
  tanpa root dan tak mengganggu sesi VPN yang sedang jalan) memuat semua node
  kandidat sebagai outbound ber-tag `probe-N` (`SingBoxConfigBuilder.probeConfigJSON`),
  lalu tiap outbound diuji lewat Clash API `/proxies/probe-N/delay` yang
  menembak `generate_204` sungguhan lewat node tersebut. Delay yang balik =
  latensi end-to-end yang jujur, bukan ping server.
- `PingResult` jadi dua tahap: `latencyMs` (TCP) + `webLatencyMs`/`internetOK`
  (end-to-end). `isDeadEnd` = port hidup DAN terbukti tanpa internet.
  `bestMs` sengaja nil untuk dead-end supaya tidak pernah diurutkan/ditampilkan
  seolah-olah angka itu valid.
- `ProbeVerdict.skipped` DIBEDAKAN dari `noInternet`: probe yang tidak sempat
  jalan (core hilang, probe sedang dipakai) tidak boleh menandai node mati —
  kalau iya, connect ke node bagus akan ditolak.
- Dampak UX: kolom Ping menampilkan ms end-to-end (hijau) / "Tanpa inet"
  (merah) / ms TCP + tanda tanya (belum diuji). `quickConnectNode` memilih
  node yang terbukti online lebih dulu. `AppState.connect(node:)` menolak
  node yang sudah terbukti dead-end dengan pesan jelas. "Sembunyikan yang mati"
  ikut memakai definisi itu. Tahap-2 otomatis jalan setelah Ping All untuk 24
  node tercepat, dan tombol Ping per baris menjalankan keduanya.
- Batas yang disepakati: probe memakai satu core pada satu waktu (maks 60 node
  per batch, konkurensi 8) — ribuan outbound dalam satu config terlalu berat.
- Tests: `PingResultTests` 6 + 3 test config probe + `testCheckProbeConfig`
  (`sing-box check -c` nyata) — 46/46 passed.

## D28 — Log koneksi: panel selalu terlihat, ringan, auto-scroll, 10-Okt-2026
- Keluhan 1: saat log dibuka, "bar kanan" (waktu + notice) hilang / terpotong;
  saat ditutup normal lagi.
  Penyebab: header memakai `Date.description(with: .current)` yang sangat panjang
  ("2026-10-10 15:06:20.123 +0700") di dalam HStack yang sempit — teks kanan
  terdorong keluar panel. Diganti `DateFormatter` (`timeStyle = .medium`),
  `lineLimit(1)` + truncation, dan `layoutPriority(-1)` supaya yang gepes
  selalu bagian kanan, bukan tombol.
- Keluhan 2: log harusnya selalu terlihat → `DisclosureGroup` DIHAPUS, log jadi
  panel permanen di bawah; auto-refresh 2 detik jalan selama menu Sambung aktif
  (bukan hanya saat log "dibuka").
- Ringan: `.textSelection(.enabled)` dipindah dari tiap baris ke satu container
  (200 selection area adalah sumber berat utama), font naik ke `.callout`
  monospaced (lebih besar, sesuai permintaan), `ForEach(logLines.indices)` tanpa
  membuat array tuple tiap render, dan tail 300 → 200 baris.
- Auto-scroll: `ScrollViewReader` + `onChange(of: logLines.count)` →
  `scrollTo(last, anchor: .bottom)`, jadi baris baru langsung terlihat.
- Layout: isi atas (status/health/node/tombol) dibungkus `ScrollView` sendiri.
  Sebelumnya satu VStack panjang: begitu panel log minta ruang, isi atas
  terdorong keluar pane dan tak bisa dijangkau.

## D29 — Menu Server: kolom & filter Sumber, 10-Okt-2026
- Node yang sama sering muncul di beberapa feed, tapi tabel tidak pernah
  menunjukkan asalnya — user tak bisa tahu node itu dari mana.
- Ditambah `TableColumn("col_source")` (nama feed + tooltip URL) yang diletakkan
  TEPAT SEBELAH kolom Bendera — negara + asal feed adalah dua hal yang paling
  sering dicari duluan — plus Picker filter Sumber di toolbar. `sourceFilter`
  sudah ada di AppState tapi belum pernah dipakai di UI.
- `AppState.sourceNames` di-cache (rebuild saat resort/persist) — pencarian
  linear per sel di 7000+ baris akan berat.
- Lebar kolom disesuaikan supaya tidak ada yang terpotong: bendera 46→58
  (header "Bendera" sempat jadi "Bend…"), sumber 110, ping 100, aksi 120,
  proto 80; field cari 240→170 dan picker tipe 140→110 agar baris filter muat
  di lebar window minimum.

## D30 — Status koneksi tidak realtime di menu Sambung, 10-Okt-2026
- Gejala: klik Sambung/Putus tidak mengubah apa-apa; baru setelah ganti tab
  lalu kembali status berubah.
- Penyebab: semua view memakai `@EnvironmentObject var state: AppState`, tapi
  `status`/`errorMessage`/byte counter milik `ConnectionManager` yang adalah
  ObservableObject TERPISAH. SwiftUI hanya menginvalidasi view dari objek yang
  diamati — perubahan di `connection` tidak pernah sampai ke AppState, sehingga
  tidak ada render ulang sama sekali sampai view dibangun ulang karena pindah tab.
- Perbaikan: `AppState.relayChildChanges()` meneruskan `objectWillChange` dari
  `connection`, `health`, `tunnel`, `splitExt`, `probe` ke dirinya sendiri.
  (Perhatikan: `for child in [...] as [ObservableObject]` TIDAK bisa dipakai —
  `objectWillChange` associated type existential tak cocok; harus generic.)

## D31 — `LocalCoreRunner.start` membekukan UI, 10-Okt-2026
- `start()` memanggil `Thread.sleep(2.0)`. Dipanggil dari @MainActor (jalur
  System Extension) itu membekukan seluruh UI selama 2 detik — dan
  `InternetProbe` justru wajib start dari MainActor.
- Dipecah jadi `spawn()` (luncurkan proses saja) + `finish()` (cek masih hidup
  / jadikan core aktif), lalu dua pintu masuk: `start()` (sinkron, `Thread.sleep`,
  dipakai jalur lama) dan `startAsync()` (`Task.sleep`, untuk pemanggil di
  MainActor). Perilaku jalur lama tidak berubah.

## D32 — Skala UI (per 10%) + teks kolom Sumber kontras, 10-Okt-2026
- Minta user: (a) teks kolom Sumber dibuat putih, (b) fitur memperbesar UI di
  menu Pengaturan.
- (a) `Theme.strongText` = `Color(nsColor: .controlTextColor)` — kontras penuh
  (putih di mode gelap) tapi otomatis jadi hitam di mode terang; `.white` keras
  akan hilang begitu user pindah light mode. Dipakai di kolom Sumber.

### ⛔ Temuan penting: `\.dynamicTypeSize` TIDAK BERFUNGSI di macOS
- Versi pertama memakai `.environment(\.dynamicTypeSize, ...)`. Ternyata
  sama sekali tidak mengubah teks — dibuktikan dengan A/B: start app dengan
  `medium` vs `xlarge` menghasilkan **piksel identik** (ink sidebar 191 = 191),
  dan perubahan saat runtime juga tidak ada efek (nilai tersimpan di
  settings.json, teks tetap sama). `\.controlSize` hanya menyentuh sebagian
  kontrol, juga tidak cukup.
- Solusi: hitung ukuran teks sendiri. `Theme.uiScale` (statis, 1.0…1.5) dibaca
  `Theme.font(.caption/.callout/...)` yang mengembalikan
  `.system(size: NSFont.preferredFont(forTextStyle:).pointSize * uiScale)`.
  SELURUH 74 pemanggilan `.font(...)` di folder UI/DesignSystem diarahkan ke
  fungsi itu (penggantian mekanis), jadi satu angka menskalakan seluruh app —
  termasuk isi log koneksi. Tidak ada font hardcode yang tertinggal.
- `uiScalePercent: Int` (100…150, langkah 10) di AppSettings, `clamp()` +
  `factor()` di `AppUIScale`. Nilai aneh / versi lain tidak boleh merombak
  settings (`try?` + default), dan selalu dibulatkan ke langkah 10.
- Perubahan runtime: `.id(state.settings.uiScalePercent)` pada root WindowGroup
  memaksa seluruh pohon view dibangun ulang (Theme.uiScale dibaca saat body
  dihitung). Ini juga menutupi `SidebarView` yang tidak mengamati AppState
  sendiri. Diverifikasi on-screen: 100% → 150% saat app terbuka langsung
  mengubah sidebar, tombol, dan baris log.
- Tests: `AppSettingsTests` 5 (legacy decode, round-trip, clamp, faktor skala,
  `Theme.pointSize` ikut skala) — 51/51 passed.

## D33 — Ping All per batch (TCP + cek internet), 10-Okt-2026
- Minta user: "ping semua server pakai batch, per 10 akun di-ping lalu di-tes
  internetnya, hasilnya muncul, lalu lanjut batch selanjutnya".
- Alur baru `AppState.pingAll()`: daftar node (hasil filter aktif) dibagi jadi
  batch (`AppState.batches`, default 10, bisa 5…50 di Settings). Tiap batch:
  (1) ping TCP paralel seukuran batch, (2) node yang portnya hidup langsung diuji
  akses internet sungguhan, (3) hasil langsung ditulis ke `ping` sehingga baris
  di tabel berubah seketika, (4) lanjut batch berikut.
- BENTROKAN TEKNIS: outbound hanya bisa diuji Clash API kalau sudah ada di config
  core yang sedang hidup, sedangkan menyalakan core per batch memakan ~4 dtk.
  Solusi: `InternetProbe` sekarang punya SESI — `beginSession(nodes:)` menyalakan
  satu core berisi JENDELA 300 node (batch ini + node-node berikutnya), lalu
  `verifyInSession(...)` menguji batch demi batch di dalamnya; core baru dinyalakan
  saat jendela habis (±30 batch). `verifyOne`/`verify` tetap jadi pembungkus sekali
  jalan untuk tombol per baris.
- Jebakan yang sempat salah: session diisi dari "node hidup ke depan" — padahal node
  yang belum diping belum tahu hidup atau mati, jendelanya selalu kosong dan core
  tidak pernah start). Sekarang jendela diisi apa adanya; yang tetap diuji hanya
  node yang TCP-nya hidup.
- `probeUnavailable`: bila core sama sekali tidak bisa jalan (binary hilang), node
  dapat verdict `.skipped` (bukan `.noInternet`) dan sisa batch tetap diping TCP
  saja — tidak ada node baik yang ikut diblokir.
- Cancel: `cancelPingAll()` menghentikan batch berjalan + mematikan sesi core;
  hasil yang sudah terverifikasi tetap tersimpan, jadi Ping All bisa diULANG dan
  hanya node yang belum punya verdict yang dikerjakan lagi (`applyTCPResult`
  memakai `withTCP` agar verdict lama tidak ditimpa).
- Timeout uji internet untuk sapuan massal diturunkan ke 5 dtk
  (`AppConstants.internetCheckTimeout`): node working biasanya jawab < 2 dtk,
  sedangkan node mati membakar timeout penuh di tiap batch.
- UI: progress bar "Batch 3/758 · 20/7576" + baris "cek internet 18/20 ·
  siap pakai 1" + tombol Batal.
- Tests: `PingBatchTests` 4 (batas 10, sisa tidak kosong, ukuran salah/0, clamp
  `pingBatchSize`) + `AppSettingsTests` tetap 5 — 55/55 passed.

## D34 — Konkurensi paralel mengikuti kekuatan CPU (adaptive), 10-Okt-2026
- Minta user: kerja ping dipercepat paralel, memakai ±50% CPU, **dibatasi** agar
  tidak bikin hang, dan "semakin kuat semakin cepat".
- MASALAH: konkurensi tetap (128 koneksi TCP + 10 uji delay) memaksa semua mesin
  kerja sama keras — Mac lama 4 core bisa 100% CPU + UI nge-lag, Mac baru
  diam-diam nganggur. Konkurensi tidak bisa tetap maupun seenak mungkin: harus
  diukur.
- `CPUGovernor.swift` (baru): `CPUMeter` membaca beban CPU nyata lewat
  `host_statistics(HOST_CPU_LOAD_INFO)` (beda tick vs sampel sebelumnya),
  `performanceCores` memakai `hw.perflevel0.physicalcpu` (hanya P-core di Apple
  Silicon; Intel fallback ke semua core). Jatah dihitung dari core × porsi CPU:
  socket 24/inti (network lebih murah), slot uji 2/inti (TLS + enkripsi jauh
  lebih berat) — jadi engine 6 inti @50% = 32→144 koneksi & 8→24 slot uji.
- Kontrol konkurensi = AIMD sederhana: beban ≤ ½ jatah → naik 25%; dalam jatah →
  tahan; sedikit lewat → turun ⅛; jenuh → turun separuh. Selalu dijepit
  [1, batas keras] supaya tidak mungkin meledak (latar: ribuan koneksi bikin
  kernel/network stack macet).
- `CPUGovernorMonitor` (@MainActor, ObservableObject) menyimpan jatah terbaru;
  `refreshIfNeeded()` dipanggil tiap refill slot tapi di-throttle 400 ms supaya
  tidak membanjiri `host_statistics`, plus timer 1 detik saat sweep jalan.
- `PingCoordinator.pingAll` dapat parameter `limitProvider: (() -> Int)?`:
  jendela geser kini dibatasi jumlah koneksi **INFLIGHT** (bukan jumlah total
  yang disubmit — versi pertama salah dan membuat sweep berhenti di 5 node,
  ditangkap `testConcurrencyStaysBounded`). Konkurensi bisa naik/turun saat
  jalan; koneksi yang sedang jalan tidak dibatalkan.
- Wiring: `pingAll()` memakai `min(cpu.socketLimit, ukuranBatch)` untuk TCP dan
  `min(cpu.computeLimit, alive)` untuk uji internet. Governor start/stop
  mengikuti siklus Ping All.
- Settings → section baru "Kinerja": toggle adaptif, Picker 25/50/75/100%, dan
  baris "Kondisi" yang menampilkan angka nyata (inti, %, koneksi, slot uji).
- CATATAN yang perlu diwaspadai: `Form` hanya boleh berisi **10 anak ViewBuilder**.
  Section ke-11 tidak menambah error yang jelas — compiler melaporkan
  "trailing closure passed to parameter of type 'FormStyleConfiguration'"
  di baris `Form {`. Solusi: tiap Section diekstrak jadi computed property.
- Catatan jujur: dengan ukuran batch kecil (default 10) jumlah kerja paralel
  dibatasi batch, jadi governor baru terasa kalau batch dinaikkan (mis. 50).
- Tests: `CPUGovernorTests` 8 + `AdaptiveSweepTests` 2 — 65/65 passed.

## D35 — Ukuran batch bebas di Settings (1–500), 10-Okt-2026
- Minta user: "batch default 10 — ini tambahkan saja di setting, jadi user bisa
  bebas pakai berapa batch".
- Dua pekerjaan:
  1. **UI**: `ping_batch_size` selama ini TIDAK ada di Settings (hilang saat
     section dipecah jadi sub-view — ketahuan saat grepenya tidak menemukan
     referensi). Sekarang tampil sebagai TextField yang bisa DIKETIK + Stepper
     spinner, rentang 1…500 (`AppConstants.pingBatchRange`), dikunci lagi saat
     disimpan supaya file settings tidak pernah berisi angka aneh.
  2. **Perbaikan konsekuensi ukuran besar**: satu sesi probe hanya memuat 300
     outbound (`InternetProbe.sessionSize`). Kalau batch > 300, node sisanya
     tidak ada di config aktif dan akan berstatus "belum teruji" selamanya
     (karena `verifyInSession` melaporkannya `.skipped`). Ditambah
     `InternetProbe.verifyAlive(nodes:...)`: memecah daftar jadi potongan
     ≤ ukuran sesi dan membuka sesi tambahan otomatis untuk sisanya.
- Artinya user bebas: 1 (satu per satu, paling hemat & paling informatif) sampai
  500 (ratusan sekaligus, banyak paralel sesuai kuota CPU).
- Tests: `FreeBatchSizeTests` 3 + `testBatchSizeIsFreeButClampedOnDecode` —
  68/68 passed.

## D36 — Hapus sumber di menu Sumber, 10-Okt-2026
- Minta user: "di sumber tambahkan fitur untuk hapus sumber".
- Kenapa belum ada meski kodenya kelihatan ada: `SourcesView` memakai
  `.swipeActions { Button(role: .destructive) { deleteSource(s) } }` —
  itu API **iOS/macOS-catalyst-only** (gesture geser di List). Di List macOS
  `.swipeActions` diam-diam diabaikan, jadi tidak ada cara menghapus apa pun.
- Perbaikan: tombol tong sampah nyata di tiap baris (`.borderless`, ada help),
  PLUS `.contextMenu` dengan "Hapus sumber" (klik kanan = cara native macOS),
  dan `Button("action_refresh")` di menu yang sama.
- Dialog konfirmasi dulu: menyebut nama sumber dan jumlah server yang ikut hilang
  ("X akan dihapus, termasuk 69 server dari feed ini. Tindakan ini tidak bisa
  dibatalkan."), karena menghapus feed berarti menghapus hundreds server.
- `AppState.removeSource(id:)` menghapus sumber **beserta node-nodenya**, hasil
  ping, dan favorit yang relevan. Tanpa itu, server yatim tetap tampil sampai
  refresh berikutnya, dan kolom Sumber akan menampilkan id yang sudah tak dikenal
  (`sourceNames` sudah dibuang). Logikanya dipisah sebagai fungsi murni
  (`nodesAfterRemovingSource`) supaya bisa diuji tanpa menyentuh file settings.
- Jebakan .strings: escape `\u201C` (huruf k kecil) TIDAK dikenali parser
  Apple — teks tampil literal "u201C". Yang benar `\U201C`.
- Tests: `RemoveSourceTests` 3 — 71/71 passed.

## D37 — Ping All hanya menguji yang tampil (filter tipe/sumber/cari), 10-Okt-2026
- Minta user: kalau filter Tipe dan/atau Sumber aktif, Ping All harus memakai
  hanya server yang tampil — bukan seluruh daftar.
- Bugs yang sebenarnya ada: `pingAll()` memakai
  `filteredNodes.isEmpty ? nodes : filteredNodes`. Fallback ke `nodes` itu
  SENGAJA Salah: filter yang tidak kecocokannya (mis. cari "zzz", atau sumber
  yang sedang kosong) akan memicu ping ke 7.978 server — persis yang
  dikeluhkan user. Sekarang `targets = filteredNodes` tanpa fallback; kalau
  kosong, Ping All tidak dijalankan dan muncul pesan.
- Filter dipisah jadi fungsi murni `AppState.applyFilters(nodes:search:proto:source:)`
  (dibuat `nonisolated` supaya bisa diuji tanpa I/O) yang dipakai `filteredNodes`
  dan `pingTargets`. Tipe + sumber = AND.
- Supaya tidak diam-diam: saat pemindaian berjalan dengan filter aktif, baris
  progress menampilkan "hanya hasil filter: 2.068/7.978" (biru); tombol Ping All
  punya help "Menguji 2.068 dari 7.978 server — hanya yang tampil karena filter
  aktif". Cakupan ini sengaja ditampilkan user harus bisa tahu cakupannya.
- Verified on-screen: filter Tipe=Trojan → "Batch 3/207 · 30/2.068" (bukan
  7.978), dengan hasil hidup: `365 ms` (hijau, terbukti jalan), `Tanpa inet`
  (merah, terbukti gagal), `Timeout`.
- Tests: `PingScopeFilterTests` 5 (tiap filter, kombinasi, dan kasus "filter
  tanpa hasil harus kosong") — 76/76 passed.

## D38 — Bar selang-seling di List + System Extension yang macet + hapus sebutan Windscribe, 10-Okt-2026
- Minta user: (a) list di menu Sumber dan list app di Split Tunnel perlu bar
  selang-seling seperti tabel Server; (b) System Extension macet di "Meminta…";
  (c) hapus tulisan "ala Windscribe" di Split Tunnel.

### (a) Bar selang-seling
- Tabel Server memang otomatis belang-belang (NSTableView), tapi `List` tidak.
  `.alternatingRowBackgrounds()` TIDAK bisa dipakai: API itu baru macOS 14,
  sedangkan app ini target macOS 13. Karena itu dibungkus `enumerated()` +
  `.listRowBackground(...)` manual dengan warna `Theme.stripedRow`
  (`Color.primary.opacity(0.075)`) — cukup jelas di dark mode, tetap halus di
  light mode. `ForEach(Array($state.sources.enumerated()), id: \.element.id)`
  dipakai agar indeks baris tersedia tanpa mengubah modelnya.

### (b) "Meminta…" yang tidak pernah selesai — akar masalah sebenarnya
- `requestActivation()` membuat delegate secara inline:
  `req.delegate = SplitActivationDelegate(owner: self)`.
  `OSSystemExtensionRequest.delegate` adalah referensi **LEMAH**, jadi objek
  delegate langsung ter-dealloc tak satu pun callback sistem yang datang —
  status macet selamanya di "Meminta…". Delegate kini disimpan kuat
  (`activationDelegate`), itu inti perbaikannya.
- Ditambah penjaga (watchdog): setiap 2 detik selama aktivasi, dicek status di
  UserDefaults; kalau sistem tetap diam setelah 45 detik
  (`SplitExtensionManager.activationTimeout`), ditandai `requestTimedOut` dan
  muncul pesan jujur + tombol "Buka System Settings…" yang membuka
  `x-apple.systempreferences:com.apple.LoginItems-Settings.extension`.
- `activationDone` sekarang juga menulis UserDefaults (sebelumnya hanya 2 dari
  3 jalur menulis), dan `requestActivation()` short-circuit kalau sudah aktif.
- Verified on-screen: aktivasi di build ad-hoc kini selesai dalam hitungan detik
  dengan "Gagal — Operasi tidak dapat diselesaikan (OSSystemExtensionErrorDomain
  8)", yaitu hasil yang jujur untuk sysext tanpa Personal Team signing.

### (c) Sebutan Windscribe dihapus
- Teks yang terlihat user (`engine_note`, `health_sysext_info_fix` di id + en)
  diganti "System Extension (VPN per-app)" / "per-app VPN"; komentar kode juga
  dibersihkan. `grep -ri windscribe FreePN/` sekarang kosong.

## D39 — "OSSystemExtensionErrorDomain 8" dijelaskan, bukan dibiarkan, 10-Okt-2026
- Keluhan: klik Aktifkan di Split Tunnel → "Operasi tidak dapat diselesaikan.
  (kesalahan OSSystemExtensionErrorDomain 8.)".
- Penyebab (terverifikasi, bukan dugaan): `codesign -dv` pada build yang berjalan
  menjawab **"code object is not signed at all"**, dan semua target di pbxproj
  memakai `CODE_SIGN_IDENTITY = "-"` (ad-hoc) + `CODE_SIGN_STYLE = Manual`.
  Entitlements sudah benar (`com.apple.developer.system-extension.install` ada),
  tapi Apple HANYA mengizinkan System Extension dari app bertanda tangan
  developer. Build unsigned/ad-hoc → selalu ditolak, dan pesan error-nya tidak
  menyebut penyebab sama sekali.
- Perbaikan (bukan hanya penjelasan): `AppSigning.detect()` membaca status
  tanda tangan build yang sedang berjalan lewat
  `SecStaticCodeCreateWithPath` + `SecCodeCopySigningInformation`
  (bit `kSecCodeSignatureAdhoc` = 0x2). Hasilnya:
  - `requestActivation()` tidak lagi mengirim permintaan yang pasti ditolak;
    langsung tampil penyebab + langkah memperbaiki.
  - Tombol "Aktifkan" nonaktif saat build memang tidak bisa; statusnya
    "Tidak bisa diaktifkan".
  - `ConnectionManager` otomatis BERALIH ke mesin Daemon TUN (mendukung split
    inklusif/eksclusive yang sama) dan menampilkan catatan di menu Sambung —
    jadi memilih System Extension di build unsigned tidak lagi jalan ke buntu.
- `AppSigningTests` 2.

### Pelajaran: `.fixedSize(vertical:)` pada teks panjang di dalam VStack
- Saat menambah blok penjelasan di `sysextRow`, SEMUA kontrol di atas daftar app
  (Mode/Mesin/status/pencarian) HILANG total — tertimpa daftar.
- Penyebabnya `.fixedSize(horizontal: false, vertical: true)` pada teks panjang:
  teks memakai lebar ideal sehingga tinggi VStack meledak, dan karena view tidak
  bisa digulir, kontrol atasnya terdorong keluar pane. Gejalanya sangat menyesatkan:
  daftar app tetap tampil dengan benar, jadi terlihat seperti "List merusak layout",
  padahal List-nya baik-baik saja.
- Perbaikan: teks dibiarkan membungkus normal + `lineLimit(6)`. Pola ini jangan
  dipakai di view yang punya `List` panjang di bawahnya.

### Catatan List + bar selang-seling (macOS 13)
- `.alternatingRowBackgrounds()` hanya ada macOS 14 → tidak bisa dipakai.
- `Array(enumerated())` + `.listRowBackground()` membuat `List` kehilangan
  sifat lazy-nya. Yang aman: `List(filtered)` seperti aslinya + warna dipasang
  DI DALAM baris lewat `.background()`, dengan himpunan ID baris genap
  (`stripedIDs`) yang dihitung terpisah.

## D40 — Akun gratis Apple: Network Extensions mustahil, projekt dibersihkan, 10-Okt-2026
- Minta user: pilih certificate signing di Xcode (Apple ID sudah login, team
  "YandiDesign (Personal Team)").
- Jawabannya sudah terverifikasi di mesin ini: keychain punya
  "Apple Development: yandisaja86@gmail.com (2X88NLU344)". Tapi Xcode menolak
  dengan pesan yang mengunci masalah:
  **"Personal development teams do not support the Network Extensions capability"**
  (untuk `com.freepn.app.FreePNTunnel` maupun `com.freepn.app.FreePNSplit`).
  Ini batas Apple, bukan salah konfigurasi — capability itu hanya ada di
  **Apple Developer Program berbayar ($99/tahun)**.
- DAMBAK TERBUKA: `FreePNTunnel.appex` (paket tunnel) di-*embed* ke dalam app
  (`Contents/PlugIns`) dan meminta 5 Network Extension sekaligus. Karena kode
  yang tertanam harus bertanda tangan sama, **app-nya sendiri ikut gagal
  ditandatangani** — bukan cuma extension-nya. App tidak bisa di-sign sama
  sekali di akun gratis.
- SISI BAIK: mesin **Daemon TUN** tidak butuh Network Extensions sama sekali
  (helper root + sing-box TUN). Yang hilang cuma: entri toggle di System
  Settings dan VPN per-app.
- User memilih: "gratis saja" → transition ke jalur Daemon TUN.

### Perubahan
1. **`FreePNTunnel.appex` dilepas dari app**: dihapus dari build phase
   "Embed App Extensions" beserta `PBXTargetDependency` + `PBXContainerItemProxy`
   yang menariknya. Target-nya tetap ada di project (tidak hilang, masih bisa
   dipakai nanti setelah Developer Program dibeli), tapi tidak lagi dibuild bersama
   app. `Contents/PlugIns` di app sekarang kosong → tidak ada lagi blokir
   signing.
2. **`TunnelManager.install()` menolak lebih awal** dengan pesan jujur
   (`vpn_needs_paid_program`) alih-alih memicu error sistem yang samar
   ("operation couldn't be completed"). Tombol "Pasang entri VPN" juga
   dinonaktifkan + catatan oranye saat entitlement memang tidak ada.
3. **Semua pesan yang salah diperbaiki**. Sebelumnya app menulis *"build ulang
   dengan Team: Personal Team (gratis)"* — kalimat yang terbukti salah karena
   Apple justru menolak capability itu di Personal Team. Diganti menjadi
   penjelasan yang benar di 9 string (id + en): `vpn_settings_desc`,
   `vpn_adhoc_note`, `vpn_need_paid_note`, `vpn_needs_paid_program`,
   `health_vpn_fix`, `health_sysext_fail_fix`, `health_sysext_info_fix`,
   `engine_note`, `sysext_signing_steps`, `sysext_adhoc_build`.
4. Peringatan Swift 6 di `TunnelManager.init` ikut dirapikan (mutasi @MainActor
   dari closure NotificationCenter lewat Task eksplisit).

### Kalau suatu saat mau upgrade
Beli Apple Developer Program ($99/tahun), lalu: kembalikan embed `FreePNTunnel.appex`
+ dependency-nya, set Team di ketiga target, dan capability NetworkExtension
otomatis tersedia. Tidak ada perubahan kode yang perlu ditulis ulang — hanya
proyek dan sertifikat.

---

## D41 — VLESS + Hysteria2 masuk sebagai protokol kelas satu (2026-10-10)

**Masalah.** Parser hanya mengenal Trojan/VMess/SS. Feed gratis yang paling
besar justru hampir seluruhnya VLESS + REALITY, dan sebagian Hysteria2 —
jadi sekitar 8.000 dari 8.600 node di feed EbraSha sebelumnya berstatus
"tidak didukung" dan dibuang tanpa pernah disentuh.

**Keputusan.**

1. **`NodeProtocol` gaining `.vless` dan `.hysteria2`**, dengan
   `badgeTitle` ("VLESS", "HY2") dan pemetaan Clash `type:` (`vless`,
   `hysteria2`, `hy2`). Filter Tipe di UI sekarang iterasi `allCases`, jadi
   tidak ada lagi daftar protokol yang harus(dirivat) manual saat menambah
   protokol baru.
2. **`TLSOptions` diperluas** (opsional semua, backward-compatible dengan
   `nodes.json` lama): `realityPublicKey`, `realityShortId`, `fingerprint`,
   plus `isReality` untuk membedakan REALITY dari TLS biasa.
   `ProxyNode` gaining `flow` (xtls-rprx-vision), `obfsPassword`, `upMbps`,
   `downMbps` — semuanya opsional.
3. **Share link**: `vless://uuid@host:port?…` (persen-encode & varian
   base64-padded diterima) dan `hysteria2://`/`hy2://` (password dengan
   `@` di dalamnya tetap aman karena pemisahan memakai `lastIndex(of:)`).
   VLESS REALITY **tanpa `pbk` dibuang saat parse** — node seperti itu tidak
   akan pernah bisa connect, jadi lebih baik tidak disimpan daripada
  megantri menggantung di Ping All.
4. **Clash YAML**: `reality-opts`, `ws-opts`, `grpc-opts`, `obfs`,
   `client-fingerprint`, `flow`, `skip-cert-verify`, `up`/`down` — baik
   bentuk blok maupun flow-map satu baris. Dua gaya penulisan `obfs`
   (`obfs: salamander` + `obfs-password`, dan map bersarang) keduanya
   diterima.
5. **Config sing-box 1.12** diverifikasi dengan binary yang dibundel
   (`sing-box check -c`): VLESS + REALITY memakai `tls.reality` +
   `tls.utls.fingerprint`, Hysteria2 memakai `up_mbps`/`down_mbps` +
   `obfs.salamander` (bukan `up`/`down` yang sudah dihapus di 1.11+).
   Nilai bandwidth diisi default bila feed tidak menyebutkannya.
6. **Hysteria2 dilewati dari tahap TCP.** Node ini berjalan di QUIC/UDP dan
  Umumnya tidak punya listener TCP sama sekali, jadi `TCPPinger` akan selalu
   timeout dan menandai node hidup sebagai mati. Di `pingAll` node
   `.hysteria2` dipisah dari batch TCP dan langsung ikut tahap-2; `pingOne`
   memakai jalur yang sama.
7. **Fallback parser (tanpa Yams) ditulis ulang** dengan dukungan map
   bersarang + boolean, sebelumnya hanya skalar datar dengan daftar kunci
   tetap. Test bundle memang dikompilasi tanpa Yams, jadi jalur inilah yang
   diuji — sekarang ia setara dengan jalur Yams untuk field VLESS/HY2.

**Verifikasi.** 87/87 test lulus, termasuk `testCheckVlessReality`,
`testCheckHysteria2`, dan `testShareLinkToCoreRoundTrip` (link → parser →
config → `sing-box check` diterima core asli).

---

## D42 — System Extension dihapus total; Daemon TUN jadi satu-satunya mesin (2026-10-10)

**Latar belakang.** D40 sudah melepas `FreePNTunnel` dari embed, tapi
`FreePNSplit` (`.systemextension`) masih tertinggal: masih jadi dependency
target app, masih punya fase "Embed System Extensions", dan entitlemennya
`com.apple.developer.networking.networkextension`. Akibatnya **build
bertanda tangan mustahil** di Personal Team gratis — `scripts/run-local.sh`
gagal dengan *"Personal development teams do not support the Network
Extensions capability"*. Jadi user dipaksa memakai build unsigned/ad-hoc.

**Keputusan: tidak ada lagi Network Extension sama sekali.**

1. **Target `FreePNSplit` dan `FreePNTunnel` dihapus** dari proyek (native
   target, build phase, config, group, dependency, container proxy, produk
   `.appex`/`.systemextension`, dan file `TransparentProxyProvider.swift` /
   `PacketTunnelProvider.swift`). Proyek sekarang hanya punya tiga target:
   `FreePN`, `FreePNHelper`, `FreePNTests`.
2. **Fase build "Embed App Extensions" dan "Embed System Extensions"
   dihapus**, begitu juga file `FreePN/Resources/FreePN.entitlements` dan
   semua setting `CODE_SIGN_ENTITLEMENTS`. App tidak lagi meminta satu pun
   capability khusus.
3. **Kode**: `TunnelManager.swift` (entri VPN sistem via `NETunnelProviderManager`)
   dan `SplitExtensionManager.swift` (aktivasi `OSSystemExtensionManager` +
   `AppSigning`) dihapus. `ConnectionManager` kehilangan jalur
   `connectViaExtension`, status `usingExtension`, `engineNote`, dan parameter
   `viaExtension`; `AppState` kehilangan `tunnel`/`splitExt` beserta relay-nya;
   `AppSettings.useSystemExtension` dihapus (key lama di `settings.json`
   diabaikan diam-diam, tidak merusak data user).
4. **Split Tunnel tetap ada dan tetap jalan** — tanpa extension. Daemon TUN
   sudah menjalankan aturan `process_name` sing-box plus aturan DNS yang
   mengikuti keputusan split yang sama, jadi Inklusif/Eksklusif per aplikasi
   tetap bekerja persis seperti sebelumnya. Yang hilang hanya gaya
   "System Extension" pada Picker dan panel aktivasi di Settings.
5. **UI**: bagian "Entri VPN Sistem" (Pasang/Perbarui/Hapus) dan item health
   `vpn` + `sysext` dihapus. Health sekarang melaporkan 5 item
   (helper, core, split, ports, firewall). Header log Sambung selalu menulis
   `DaemonTUN`.
6. **Localization**: 34 key `sysext_*`/`vpn_*`/`engine_*`/`health_sysext*`
   beserta key yang sudah tak terpakai dihapus dari id + en, digantikan satu
   key `split_note_daemon` yang menjelaskan split berjalan di dalam Daemon TUN.

**Konsekuensi yang menguntungkan.**

- `scripts/run-local.sh` **berhasil** lagi dan menghasilkan app bertanda
  tangan `TeamIdentifier=4DQ23N8GY5`, universal `arm64 + x86_64`, dengan
  entitlements kosong (selain `get-task-allow` saat Debug).
- Tidak ada lagi permintaan izin yang ditolak Apple di akun gratis, tidak ada
  dialog persetujuan Login Items, dan tidak ada provisioning profile yang bisa hilang.
- Yang hilang murni kosmetik: FreePN tidak lagi tampil sebagai entri VPN di
  System Settings > Network > VPN (entri itu hanya ada kalau ada extension).

**Verifikasi.** 85/85 test lulus (2 test `AppSigningTests` dihapus bersama
API-nya), localization EN==ID, `run-local.sh` sukses, `PlugIns` kosong,
`Contents/Library/SystemExtensions` tidak ada.

---

## D43 — Parser Clash yang benar-benar jalan (bukan "fallback" yang tak pernah dipakai)

**Latar belakang.** User melaporkan feed
`vxiaov/free_proxies/clash/clash.provider.yaml` "tidak support". Isinya 28
proxy dan **semua** menghasilkan 0 node.

**Penyebabnya dua, bertumpuk.**

1. **Kunci JSON berkutip.** Tiap baris adalah objek JSON di dalam YAML:
   `- {"name":"…","type":"ss",…}`. Parser memecah `key: value` dan menyimpan
   kuncinya apa adanya — termasuk tanda kutipnya — sehingga `current["type"]`
   tidak pernah ada, dan `type` kosong → entri dibuang.
2. **`#if canImport(Yams)` ternyata PALING.** Proyek ini **tidak punya
   dependency SPM sama sekali** (nol `XCRemoteSwiftPackageReference`), jadi
   cabang "pakai Yams" tidak pernah dikompilasi. Yang berjalan di app adalah
   "fallback" yang sejak awal hanya bisa scalar datar + daftar kunci tetap.
   Artinya VLESS/HY2 hasil D41 pun bisa jadi tidak terbaca di jalur yang
   benar-benar dipakai —bug yang tidak terlihat karena test juga memakai
   fallback yang sama.

**Keputusan.**

1. **`ClashYAMLParser` jadi satu parser tunggal** (cabang Yams dihapus —
   tidak pernah aktif dan menyesatkan). Parser ini menangani tiga gaya yang
   muncul di feed liar:
   - flow-map JSON satu baris dengan kunci berkutip, escape `\uXXXX`
     (termasuk pasangan surrogate), `true/false`, angka;
   - flow-map YAML tanpa kutip;
   - blok berindeks dengan map anak (`reality-opts:`, `ws-opts:`, `obfs:`).
2. **Nilai kosong berarti "anak menyusul"** (indented block), `{}` berarti map
   kosong — sebelumnya keduanya tidak bisa dibedakan.
3. **Header WS dibaca case-insensitive**: feed satu menulis `Host`, yang lain
   `HOST`. Header `HOST` yang dulu hilang berarti SNI/Host jadi kosong pada
   banyak node.
4. **Hanya isi `proxies:` yang diparse.** `proxy-groups:` punya `type: select`
   / `reject`; kalau ikut diparse, tiap group terhitung protokol tak didukung
   dan mengotori angka "tidak didukung" di UI. Ini juga menutup parsing file
   Clash penuh (proxy-providers/rules).
5. **Transport `h2-opts`** ikut dibaca (path + header host), sebelumnya
   diabaikan.

**Hasil setelah perbaikan** (feed nyata, diukur lewat test):

| Feed | Format | Sebelum | Sesudah |
|---|---|---|---|
| vxiaov `clash.provider.yaml` | JSON-in-YAML | **0** | 26 (15 VMess + 11 SS), 2 SSR ditolak |
| Pawdroid `sub` | base64 share-link | — | 6 (5 VLESS + 1 Trojan) |
| mahdibland `Eternity.txt` | base64 share-link | — | 200 (SS 123, Trojan 67, VMess 10) |
| Epodonios `All_Configs_Sub.txt` (1,7 MB) | base64 share-link | — | 7.526 (VLESS 5.850, SS 789, Trojan 558, VMess 280, HY2 49) |

**Verifikasi.** 120 node dari feed 1,7 MB dan semua 26 node dari vzxiaov
dikonfigurasi lalu dicek dengan `sing-box check` — 0 gagal. 89/89 test lulus
(termasuk 4 test baru: format provider, header case-insensitive,
`proxy-groups` diabaikan, dan baris provider → config → `sing-box check`).

---

## D44 — Status sumber jadi jujur: "dipakai" ≠ "terbaca" (2026-10-10)

**Latar belakang.** Setelah parser Clash diperbaiki (D43), user masih melihat
baris sumber berwarna oranye bertuliskan *"234 node tak didukung dilewati"* —
terbaca seperti kegagalan, padahal fetch-nya sukses. Dan sumber lain yang
sebenarnya berhasil bisa terlihat "0".

**Dua masalah yang berakar sama: angka yang ditampilkan bukan angka yang
dipakai user.**

1. `lastError` dipakai untuk dua hal sekaligus: error sungguhan **dan**
   catatan "N tidak didukung". Akibatnya sumber yang sehat tampil oranye.
2. `nodeCount` = jumlah entri yang **terbaca**, sedangkan yang benar-benar
   masuk ke app = jumlah setelah dedup. Untuk sumber aggregator, selisihnya
   bisa 100%: `blog.ermao.net` membaca 380 node tapi 0 yang dipakai karena
   semuanya sudah ada di EbraSha/morpheusadam.

**Perubahan.**

1. Field baru `VPNSubscriptionSource.keptCount` (node yang benar-benar tersisa
   setelah dedup) dan `unsupportedCount` (entri berformat dikenal tapi
   protokolnya tidak didukung). Keduanya **opsional saat decode** — `sources.json`
   lama harus tetap bisa dibaca, kalau tidak seluruh daftar sumber user hilang
   hanya karena app diperbarui.
2. `lastError` sekarang HANYA untuk kegagalan. "Cache" pindah ke atribut
   terpisah, "N tidak didukung" pindah ke `unsupportedCount`.
3. `AppState.resort()` menghitung `keptCount` per sumber setiap selesai dedup.
4. `SourcesView` menampilkan status hijau "OK" + keterangan netral:
   `16 dipakai · 2 tidak didukung`, atau `380 terbaca, semuanya duplikat · 234
   tidak didukung` — jujur tanpa dramatisasi.

**Angka nyata di mesin user's (14 sumber):** 16.518 node terpakai — EbraSha
12.001, morpheusadam 1.729, Anaer 1.596, Au1rxx 681, Learnhard-cn 16, dan
sumber aggregator sisanya 0 karena 100% duplikat. Dua sumber mati (NodeFree,
Mfuu) dananya memang hilang di sisi upstream (DNS/404), bukan bug app.

**Verifikasi.** 91/91 test lulus, termasuk `testLegacySourcesJSONWithoutNewCountersDecodes`
(sources.json lama) dan `testKeptCountReflectsDedup`.

---

## D45 — Satu kontrol saja: Performance. "Ping concurrency" dihapus (2026-10-10)

**Latar belakang.** User menemukan stepper **"Konkurensi ping"** di
Settings → Subscription dan bertanya fungsinya. Setelah ditelusuri: **nilai itu
tidak pernah dibaca siapa pun** di luar UI dan penyimpanan — sisa dari versi
sebelum CPU governor adaptif ada.Naik-turunnya tidak mengubah apa pun.

**Keputusan: hapus knob itu, jangan tambah Meaningless-nya.**

1. **`pingConcurrency` dihapus** dari `AppSettings` (properti, init, coding
   key, decode) dan stepper di Settings. `settings.json` lama yang masih punya
   key itu **tetap bisa dibaca** — Codable mengabaikan key asing, dan ada test
   yang menjaganya.
2. **Plafon keras dihapus dari governor.** Dulu `maxSockets = 256` dan
   `maxCompute = 48` muncul sebagai "pengaman", tapi justru membuat angka di
   Settings tidak sesuai kenyataan di mesin besar. Sekarang jatah murni dari
   `jumlah core × jatah per core × porsi CPU`, dan **pembatasnya adalah AIMD
   yang membaca `host_statistics` sungguhan**: mesin adem naik sendiri, mesin
   sibuk turun sendiri. Tidak ada angka tebasan.
   - 6 P-core (iMacPro) + porsi 100% → 288 koneksi, 24 slot uji.
   - Porsi 25% → 72 koneksi, 6 slot uji.
3. **Slot uji sekarang benar-benar dipakai.** `probe.verifyAlive` dan
   `probe.verify` sebelumnya jalan dengan `concurrency: 8` konstan, mengabaikan
   governor — itulah alasan "slot uji" cuma angka pajangan, dan tahap-2 lamban
   di feed besar. Sekarang keduanya memakai `cpu.computeLimit` (quick connect
   dibatasi 12 karena kandidatnya paling 24).
4. **Baris "Kondisi" menampilkan beban CPU** (`… · 41% load · adaptif`) supaya
   user bisa melihat kenapa jumlah koneksi bergerak sendiri.

**Konsekuensi yang dianggap bagus:** satu knob untuk semua (Performance),
tidak ada lagi settings yang promises something it doesn't do, dan angka yang
ditampilkan selalu sama dengan yang benar-benar dipakai — di governed oleh
mesin user sendiri.

**Verifikasi.** 93/93 test lulus, termasuk `testNoHardCeilingOnBigMachine`
(64 core @100% → >1000 koneksi, tanpa plafon) dan
`testAdaptiveLimitStaysInsideCoreDerivedCeiling` (AIMD tidak pernah keluar dari
jatah yang dihitung). Localization EN==ID, signed build sukses.

---

## D46 — Tahap-2 dipercepat: jatah slot uji ×2, timeout 6/5 → 4 dtk (2026-10-10)

**Latar belakang.** User complaint: *"sudah setting rata kanan, batch 500, tapi
CPU cuma 20%."* Pengukuran nyata (500 node asli dari `nodes.json`, sweep TCP app
sendiri) menunjukkan CPU rendah itu memang wajar — sweep TCP itu I/O-bound,
bukan compute-bound:

| Konkurensi | Waktu 500 node | Beban CPU puncak |
|---|---|---|
| 32 | 31,1 s | 59% (run pertama) |
| 96 | 12,2 s | 32% |
| 288 | 6,1 s | 37% |

Konkurensi tinggi justru **5,1× lebih cepat** tanpa menaikkan CPU — yang
menghambat adalah menunggu timeout, bukan tenaga. Beban CPU rendah bukan tanda
pengaturan gagal; yang penting adalah wall-clock.

Dari sana baru jelas: **tahap-2 (cek internet) adalah bottleneck**, bukan tahap-1
— di feed 16.540 node, hanya ±5% yang lolos TCP, tapi tiap yang lolos masih
menunggu probe yang berat.

**Pengukuran tahap-2 (228 node TCP-hidup, core sing-box sungguhan):**

| Konfigurasi | Waktu | Node benar-benar online |
|---|---|---|
| conc 8, timeout 6 dtk (sebelumnya) | 33,27 s | 6 |
| conc 48, timeout 4 dtk (sekarang) | **17,53 s** | 6 |

**1,90× lebih cepat dengan jumlah node online yang sama persis** — timeout 4
detik tidak memotong satu pun node yang memang bisa dipakai.

**Perubahan.**

1. **`CPUGovernor.computeLimit`: 2 → 4 per core.** Di iMacPro (6 P-core) porsi
   100% jadi 48 slot uji (sebelumnya 24). Beban per slot jauh lebih ringan
   daripada socket TCP (1 koneksi per slot, tidak mengganda port), jadi AIMD
   tidak akan turunkan sendiri.
2. **`AppConstants.internetCheckTimeout`: 5/6 → 4 dtk, dan kini SATU konstanta**
   untuk semua jalur. Sebelumnya ada dua angka berbeda untuk tes yang sama:
   `5` dtk di sweep per batch dan literal `6` dtk di tombol Ping/quick connect.
3. Semua default di `InternetProbe` (`verifyInSession`, `verify`, `verifyAlive`,
   `verifyOne`, `test`) sekarang menunjuk konstanta itu — tidak ada lagi angka
   timeout yang tertulis langsung di kode.

**Verifikasi.** 94/94 test lulus, termasuk `testProbeTimeoutIsSingleConstant`
dan `testComputeLimitIsSmallerThanSocketLimit` (8 core @50% = 32 slot uji).
Localization EN==ID.

---

## D47 — Socket ping tidak pernah ditutup (bocor file descriptor) (2026-10-10)

**Latar belakang.** User: *"sudah setting rata kanan, batch 500, tapi FreePN cuma
8% CPU."* CPU rendah memang wajar (D46: kerja itu I/O-bound), tapi sambil
memeriksa proses yang sedang hidup, ditemukan hal lain: FreePN memegang
**129 socket ESTABLISHED + 321 CLOSE_WAIT** padahal tidak ada yang perlu
setelah sweep selesai.

**Penyebabnya.** `TCPPinger.ping()` membuat `NWConnection`, menjalankan
`stateUpdateHandler`, lalu **tidak pernah memanggil `cancel()`**. Akibatnya:

- handshake yang sukses → socket tetap ESTABLISHED selamanya;
- handshake yang gagal/timeout → socket menggantung di CLOSE_WAIT.

Keduanya adalah file descriptor yang tidak pernah dibebaskan.

**Bukti (diuji, bukan dikira-kira):**

| Versi | 250 ping | FD setelah 6 detik |
|---|---|---|
|Sebelum | 250 ping | **+250, tidak pernah turun** (16 → 266) |
| Sesudah | 250 ping | 16 → 206 (torn down) → **16** setelah 1 detik |

**Dampaknya nyata di feed 16.540 node:** satu Ping All menumpuk ~16.500 FD.
Batas Lunak per proses di macOS cuma **256** (`launchctl limit maxfiles`), dan
begitu terlampaui `NWConnection.start()` gagal → state `.failed` → `ping`
mengembalikan `nil` → **node yang masih hidup ikut ditandai mati** di sisa
sweep. Jadi bukan cuma pemborosan sumber daya, tapi hasil yang salah.

**Perbaikan.** Satu kelas baru `PingRun` memegang koneksi + timer, dan
`finish()` melakukan: resume continuation → `stateUpdateHandler = nil` (memutus
siklus retensi handler → objek → koneksi) → `connection.cancel()` → batalkan
timer. Jalur timeout pun menutup socket, bukan hanya jalur `.ready`.

**Verifikasi.** 95/95 test lulus, termasuk `testPingerReleasesSocketsAfterEachProbe`
(120 ping ke TEST-NET-1, FD wajib kembali ke baseline dalam 3 detik) — test ini
akan gagal di kode versi lama.

---

## D48 — "Batch 500" diam-diam behave seperti 50 (2026-10-10)

**Latar belakang.** User: *"sudah rata kanan — 500 nodes per batch, 100% CPU
limit, ping all server — FreePN cuma 8% CPU."* Laporan ketiga dengan gejala
yang sama seperti D46/D47, tapi penyebabnya berbeda lagi.

### Akar masalah 1 — clamp keras `min(50, …)` (bug nyata)

`AppState.pingAll()` menulis:

```swift
let batchSize = max(1, min(50, settings.pingBatchSize))
```

sementara `SettingsView` dan `AppConstants.pingBatchRange` **menjanjikan
1…500**. Jadi angka **500 berperilaku persis seperti 50** — tanpa warning,
tanpa error. Efeknya berantai ke `tcpConcurrency` (`min(socketLimit, batchSize)`)
dan `limitProvider`, keduanya ikut terpotong 50.

Di i5-10400 (6 P-core, share 100%) `CPUGovernor.socketLimit` = 6 × 24 × 2 =
**288 koneksi**, sedangkan pipeline tidak pernah melewati **50** — 83% jatah
dibuang. Yang membuat ini sulit dideteksi: baris status di Settings
menampilkan `cpu.socketLimit` (angka mentah governor, "288"), bukan angka
yang benar-benar dipakai. Settings-nya "benar", hanya tidak pernah berlaku.

**Perbaikan.** Aturan dijepit diekstrak jadi dua fungsi murni yang bisa diuji
(`effectiveBatchSize`, `effectiveSockets`) dan memakai `AppConstants.pingBatchRange`.
Status di Settings kini menampilkan limit **efektif**, plus catatan
"dibatasi batch" kalau batch yang mengikat.

### Akar masalah 2 — parsing feed ter-serialize di satu core

Ini bagian yang menjawab *"CPU harus terpakai semua seperti saat rendering"*.

`SubscriptionService` adalah **`actor`**, jadi `fetchOne` — dan di dalamnya
`AutoParser.parse`, yaitu pekerjaan CPU paling berat di seluruh app — SELALU
berjalan di satu eksekutor cooperatif tunggal. `withTaskGroup` di
`AppState.refreshAll` tetap jalan, tapi **nol paralelisme untuk parsing**: semua
sumber diantre satu per satu. Enam core, satu yang bekerja.

**Perbaikan.** `SubscriptionService` diubah dari `actor` ke
`final class: @unchecked Sendable` (state semuanya `let`; `URLSession`
thread-safe, `SubscriptionCache` sudah actor sendiri). Parsing beberapa feed
besar sekarang benar-benar paralel di semua core.

### Akar masalah 3 — hotspot di parser

`ClashYAMLParser` memanggil `trimmingCharacters(in: .whitespaces)` puluhan kali
per baris (lewat `NSCharacterSet`, lambat) dan memecah baris dengan
`components(separatedBy: .newlines)` yang mem-*materialize* seluruh isi berkas
10 MB. Diganti `fastTrim` (sisir `String.Index` untuk space/tab/CR/LF) dan
`lines(of:)` (pecah per baris, hanya normalisasi CRLF bila ada).

**Diukur (feed 937 KB, 8.000 node, median 5×):**

| Versi | Waktu parse |
|---|---|
| Sebelum | 795 ms |
| Sesudah | **497 ms** (1.6×) |

Output kedua versi identik (8.000 node, count sama).

**Jebakan yang nearly lolos.** `split(separator: "\n")` terlihat lebih cepat dari
`components(separatedBy:)`, tapi `\r\n` adalah **satu grapheme cluster** di
Swift — jadi `split(separator: "\n")` **tidak memotong** akhir baris Windows dan
seluruh berkas jadi satu baris. Feed CRLF gagal parse total, senyap.
Tertangkap oleh `testWindowsLineEndingsStillParse`, yang sengaja ditambahkan.

### Akar masalah 4 — tahap-1 dan tahap-2 saling menunggu

Loop lama `await` tahap-2 **di dalam** loop batch, jadi sweep TCP batch
berikutnya baru jalan setelah uji internet batch ini selesai (s.d. 4 detik).
Padahal keduanya tidak berebut sumber daya: tahap-1 nunggu timeout socket,
tahap-2 nunggu proses `sing-box`.

**Perbaikan.** Tahap-2 dijalankan sebagai `Task` dan hanya ditunggu di awal
iterasi berikutnya, jadi keduanya tumpang tindih. Tetap **satu** sesi probe
yang hidup pada satu waktu (`InternetProbe` menyimpan satu core), jadi tahap-2
tetap diserialkan; yang tumpang tindih adalah tahap-2 vs tahap-1.

### Akar masalah 5 — Setting Performance tidak berpengaruh ke tahap-2

- `verifyInSession` memakai jendela **gelombangan** dengan `concurrency` beku di
  awal. Diganti sliding window + `limitProvider` (pola yang sama dengan
  `PingCoordinator`), jadi governor benar-benar mengatur slot uji yang hidup.
- `verifyInternetForBestCandidates` memakai plafon keras `min(computeLimit, 12)`
  yang mengabaikan governor sepenuhnya. Dihapus.
- `probeConfigJSON` + tulis berkas + `sing-box check` (`waitUntilExit()`)
  berjalan di MainActor → **UI beku tiap restart sesi**. Dipindah ke
  `Task.detached`.

### Knob "Node per batch" dihapus (keputusan lanjutan)

Clamp 50 bisa saja diperbaiki dengan sendirian, tapi hasil review menunjukkan
akar masalahnya lebih dalam: knob itu **redundan**.

"Node per batch" sebenarnya mengendalikan dua hal sekaligus:

| Tugas | Status |
|---|---|
| (a) Membatasi konkurensi TCP | **Redundan** — itu sudah diurus CPU governor di Settings "Performance" |
| (b) Menentukan kapan sesi probe di-restart | **Nyata**, tidak boleh hilang |

Tugas (a) redundan persis karena itulah sumber bug-nya: dua knob mengatur
hal yang sama, jadi yang salah diam-diam menang. D45 sudah pernah menghapus
knob konkurensi yang tidak dibaca siapa pun dengan alasan yang sama — ini
kelanjutan yang sama.

Yang-tetap perlu diperhatikan: tugas (b) tidak bisa hilang begitu saja.
Setiap sesi probe punya biaya tetap yang nyata — tulis config 300 outbound,
spawn `sing-box check` sebagai subprocess, jalankan core, poll API sampai
siap. Menghapus tugas (b) tanpa pengganti berarti sesi di-restart **tiap
batch**.

Perbaikannya: knob dihapus dari UI, tugas (a) jadi `cpu.socketLimit` murni
(satu-satunya penentu kecepatan), tugas (b) pindah ke konstanta internal
`AppConstants.pingStageChunk = 100`.

**Kenapa 100 tidak penting secara performa.** Sesi baru mulai pada posisi
`k × sessionSize` dan jendela sesinya mencakup `[p, p + sessionSize)`.
Selama `chunk <= sessionSize`, jumlah restart = `total / sessionSize` —
**tidak bergantung pada besar chunk sama sekali**. Rumus ini diuji di
`ProbeSessionRestartTests`: chunk 1 sampai 300 semuanya menghasilkan 20 sesi
untuk 6.000 node. Jadi angka 100 dipilih murni demi progres yang halus dan
Cancel yang responsif, bukan demi kecepatan.

Knob `pingBatchSize` juga dihapus dari `AppSettings`. `settings.json` lama
yang masih menyimpannya tetap terbaca — `JSONDecoder` mengabaikan key yang
tidak dikenal, dan tidak ada efek samping (dicek di
`testLegacySettingsJSONWithBatchSizeStillDecodes`).

Di UI, teks "Batch x/y" di progress bar ikut dihapus karena jadi jargon
internal; yang ditampilkan sekarang hanya jumlah diproses dan jumlah node
yang terbukti online.

### Yang TIDAK berubah, dan alasannya

Ping All tetap **tidak akan pernah sampai 100% CPU**, dan itu memang benar.
Kerja tahap-1 adalah I/O-bound: `connect()` dikerjakan kernel, CPU user per
ping cuma mikrodetik. D46 sudah mengukurnya: 500 node → 31.1 s @ conc 32
(peak 59%) vs **6.1 s @ conc 288 (peak 37%)** — lebih cepat justru dengan CPU
lebih rendah. Add drop yang mahal (TLS + enkripsi proxy) jalan di proses
`sing-box`, jadi tidak pernah muncul di baris FreePN di Activity Monitor.

Yang diperbaiki adalah hal yang **seharusnya** membuat CPU naik: workload
sebenarnya tidak lagi dibuang oleh clamp, parsing tidak lagi ter-serialize di
satu core, dan pipeline tidak lagi idle menunggu. Memaksa 100% CPU hanya
meminta app melakukan kerja sia-sia.

**Verifikasi.** 104/104 test lulus (dari 95). Test baru:
`PingConcurrencyOwnershipTests` (4) mengunci bahwa konkurensi TCP kini hanya
milik governor dan tidak lagi dipotong apa pun; `ProbeSessionRestartTests` (3)
mengunci rumus `sessionRestarts` dan fakta bahwa jumlah restart independen
dari besar chunk; `testWindowsLineEndingsStillParse`,
`testBlankAndCommentLinesAreIgnored`, `testNonASCIINamesStillParse` mengunci
parser; `testLegacySettingsJSONWithBatchSizeStillDecodes` mengunci kompatibilitas
settings lama.

---

## D49 — Batas FD macOS membuat Ping All berbohong (2026-10-10)

**Latar belakang.** Permintaan: *" optimasi dan buat agar ping banyak server
jadi cepat."* Dua langkah terakhir (D48) sudah membuat sweep berjalan pada
jatah penuh, tapi hasil pingnya tetap terasa sedikit. Jadi langkah berikutnya
bukan menambah optimasi lagi, tapi **mengukur** — dan pengukuran itu
menunjukkan masalahnya bukan kecepatan.

### Temuan: bukan lambat, tapi SALAH

Feed lokal 16.464 node → 14.600 endpoint unik (75% di antaranya host berupa IP
literal, jadi DNS hanya menyumbang 25% dan **bukan** bottleneck — hipotesis
awal yang salah sudah dibuang).

Sweep TCP diukur dengan `TCPPinger` yang asli, di bawah `ulimit -n 256`:

| concurrency | batas FD 256 (kondisi app) | setelah batas FD dinaikkan |
|---|---|---|
| 288 | **7,3%** node hidup — 15,7 s | **45,1%** — 10,7 s |
| 512 | **0,2%** node hidup — 9,3 s | 41,8% — 6,9 s |

**~92% server yang benar-benar bisa dipakai hilang dari hasil.** Dan ini bukan
hipotesis: `NWConnection.start()` gagal saat descriptor habis → state
`.failed` → `ping` mengembalikan `nil` → node hidup **ditandai mati**.

### Penyebabnya

App yang dijalankan dari Dock/Finder mewarisi
`launchctl limit maxfiles` dengan soft = **256**. Satu sweep dengan 288 koneksi
hidup membakar **~480 FD** (`NWConnection` memakai beberapa FD per koneksi).
Batas keras di macOS `unlimited`, jadi proses **boleh** menaikkan soft limit
sendiri — tapi tidak ada yang melakukannya.

Ini adalah saudara dari D47: D47 memperbaiki FD yang **tidak pernah dilepas**,
D49 memperbaiki FD yang **tidak pernah cukup**.

**Perbaikan.** `AppConstants.raiseFileDescriptorLimit()` — satu panggilan
`setrlimit` di `FreePNApp.init()`, sebelum sweep pertama. Plus jaring
pengaman: `CPUGovernor.socketLimit` memotong jumlah socket agar tetap di
batas FD yang benar-benar tersedia, untuk environment yang mengunci hard limit.

### Konstanta socket per inti dinaikkan 24 → 40

Angka `24 per inti` dibuat waktu sweep TCP masih dianggap mahal CPU.
Pengukuran menunjukkan sebaliknya: `connect()` dikerjakan kernel, biaya CPU
per koneksi mikrodetik, jadi sweep ini **I/O-bound murni** — yang membatasi
bukan jumlah core, tapi FD. Setelah FD diperbaiki, jumlah ini boleh naik.
Hasilnya (4.000 endpoint, timeout 1,5 s, batas FD sudah dinaikkan):

| concurrency | waktu | node hidup |
|---|---|---|
| 288 | 13,8 s | 45,6% |
| 384 | — | — |
| 512 | 8,8 s | 42,3% |

6 core @ 100% sekarang = **480** (bukan 288).

### Hasil akhir (1.500 endpoint, timeout 1,5 s, `ulimit -n 256`)

| | sebelum | sesudah |
|---|---|---|
| concurrency 288 | 6,35 s · 36,9% hidup | 6,25 s · 39,7% hidup |
| concurrency 480 | 4,56 s · **24,5%** hidup | 4,43 s · **39,0%** hidup |

Perhatikan baris terakhir: **menaikkan concurrency dulu lebih cepat tapi
mahal — 12,4 poin hilang: lebih banyak node hidup salah ditandai mati.**
Setelah FD diperbaiki, kenaikan itu jadi gratis: 30% lebih cepat **dan** 2,1 poin
lebih akurat.

### Yang SENGAJA tidak diubah

`pingSweepTimeout` tetap 1,5 s. Data menunjukkan timeout 2,0–2,5 s memang
mengembalikan beberapa node yang hilang pada concurrency tinggi (46,5% vs
42,3% pada 512), tapi perbandingan itu tercemar ukuran sampel dan bertabrakan
dengan pengukuran D46 yang sudah menyimpulkan 1,5 s cukup. Tidak diubah tanpa
data yang bersih.

### Verifikasi

106/106 test lulus (dari 104). Test baru:
`testRaiseFileDescriptorLimitIsSafeAndIdempotent` (aman dipanggil berulang,
tidak pernah melewati hard limit), `testSocketLimitNeverExceedsFileDescriptorBudget`
(jaring pengaman FD), dan `testSocketBudgetComesOnlyFromGovernor` diperbarui
ke angka 480.

## D50 — Ping All dua tahap jadi satu (2026-10-11)

**Latar belakang.** User: *"cara kerja apps ini utk ping all itu pertama ping
semua server jika hidup kedua ping dan cek akses internet, ini menjadikan proses
batch ping 2x dan tidak perlu, buat sekali saja ping akses ke internet, soalnya
ping pertama useless, cek hidup tapi tidak ada internet."*

### Akar masalah — tahap-1 tidak pernah dipakai untuk memutuskan apa pun

D33 (dan seterusnya) membuat Ping All dua tahap:

1. sweep TCP `NWConnection` ke `host:port` setiap node → `latencyMs`;
2. hanya node yang portnya hidup diuji akses internet lewat core sing-box →
   `webLatencyMs` + `internetOK`.

Tahap-1 **tidak pernah jadi dasar keputusan apa pun**. Tidak ada satu baris
kode yang memakai `latencyMs` untuk memilih, mengurut, atau menyaring node —
ia hanya mempersempit siapa yang perlu diuji tahap-2. Peng-PR modern
D46/D47/D48/D49 (raise FD, clamp governor, window geser, pipeline) seluruhnya
adalah untuk tahap-1 itu.

Jadi struktur itu hanya membeli satu hal: setiap node diproses **dua kali**. Untuk feed
16k node itu berarti ribuan socket TCP yang hasilnya langsung dibuang.

### Yang dihapus

| Dihapus | Alasan |
|---|---|
| `TCPPinger.swift` | satu-satunya consumer-nya tahap-1 |
| `PingCoordinator.swift` (`PingerProtocol`, dedup endpoint, sliding window TCP) | orkestrator tahap-1 |
| `AppState.pingCoordinator`, `pingAll`/`verifyStageTwo`/`applyTCPResult`/`sessionWindow`/`batches` | pipeline tahap-1 |
| `CPUGovernor.socketLimit` + `minSockets` + AIMD socket | tidak ada lagi kerja socket di app |
| `AppConstants.pingTimeout`, `pingSweepTimeout`, `pingStageChunk` | konstanta tahap-1 |
| `PingResult.latencyMs` / `isAlive` / `withTCP` | tidak pernah ditampilkan sebagai latency |
| L10n `ping_tcp_help`, `ping_net_progress`, `cpu_conn` | teks tentang keadaan TCP |

### Yang berubah bentuk (bukan hilang)

- **`CPUGovernor.computeLimit` jadi satu-satunya jatah.** `fdSafeLimit` yang
  tadinya Protecting `socketLimit` sekarang Protecting `computeLimit` —
  jaring pengaman FD D49 tetap ada, hanya pindah ke tempat yang masih punya
  koneksi. `raiseFileDescriptorLimit()` tetap dipanggil.
- **`InternetProbe.verify(nodes:…)` jadi satu-satunya jalur uji.** `verifyAlive`
  (potongan per sesi) dan `verify` (satu sesi) digabung. `sessionRestarts(total:)`
  kehilangan parameter `chunk` karena tidak ada lagi pemotong batch.
- **`AppState.apply(_:for:)` membuat entry kalau belum ada.** Ini wajib: sejak
  tahap-1 dihapus, tidak ada lagi yang membuat `PingResult` lebih dulu, jadi
  tanpa ini hasil probe untuk node yang belum pernah diuji akan hilang.
- **`AppState.isUsable(_:)` dan `quickConnectChoice(among:ping:)` diekstrak jadi
  fungsi murni** supaya aturan "mana yang layak" bisa diuji tanpa menjalankan
  core (pola yang sama dengan `applyFilters`).

### Konsekuensi yang disengaja

- Tidak ada lagi keadaan "port hidup tapi tanpa internet" di UI. Node yang gagal
  diuji → `internetOK == false` → merah "Tanpa inet", apa pun penyebabnya
  (port tertutup, kredensial salah, egress diblokir, upstream mati).
- **Waktu total bisa lebih panjang pada feed yang banyak node mati.** Sebelumnya
  tahap-2 hanya kena ~40% node; sekarang 100%. Tapi itu bukan regressions —
  tahap-1 yang dihapus tetap harus membakar 1,5 dtk × semua node, jadi yang
  hilang adalah kerja yang hasilnya dibuang, bukan kerja yang dipakai.
- `ProbeVerdict.skipped` jadi lebih penting dari sebelumnya, karena sekarang
  satu-satunya jalan menuju verdict. Probe yang tidak sempat jalan **tidak boleh**
  menandai node mati — kalau tidak, sebagian besar server gratis user akan
  ditandai salah dan connect ke sana ditolak.

### Verifikasi

91/91 test lulus. Test `PingCoordinatorTests` (7) dan `AdaptiveSweepTests` (2)
dihapus bersama kode yang mereka uji; `PingVerdictRoutingTests` (4) +
`LegacySettingsPingTests` (1) menggantikannya — penjaga langsung untuk
konsekuensi di atas.

## D51 — Satu node korup mematikan verifikasi internet untuk hundreds node (2026-10-11)

**Latar belakang.** User (setelah D50): *"malah eror probe config failed
validation internet check skipped."* Ini BUKAN bug D50 — ini bug lama yang
baru ketahuan karena D50 membuat semua node benar-benar lewat probe.

### Akar masalah

`sing-box check` bersifat **all-or-nothing**: satu outbound tidak valid →
SELURUH config probe ditolak → `InternetProbe` gagal menyalakan core →
seluruh 16k node dilaporkan `.skipped`. Tidak ada yang diprobe sama sekali.

Feed `morpheusadam` (1.743 node) memuat link seperti ini:

```
ss://ax51Ok45f351XA@104.18.218.118:443#@DeltaKroneckerGithub
```

`ax51Ok45f351XA` itu base64 dari `k\x1eu:N9\x7f~u\` — **byte mentah**, bukan
`method:password`. `ShareLinkParser.parseSS` menerimanya karena isinya
kebetulan punya tanda `:` dan UTF-8 valid. Hasilnya:

```
$ sing-box check -c probe.json
FATAL initialize outbound[15]: unknown method: k
```

Di `nodes.json` user ada **29** node seperti ini (semua dari satu feed), dan
karena jendela sesi = 300 node, hampir pasti ada satu sesi yang kena.

### Perbaikan — dua lapis, karena satu lapis tidak cukup

**Lapis-1 — jangan biarkan node korup masuk daftar.**
`NodeDeduper.keepingUsable` (+ `Validators.isPlausibleSecret`,
`Validators.shadowsocksMethods`) membuang node yang:
- punya karakter kontrol (U+0000–U+001F, U+007F) di kredensial — tanda tangan
  payload biner, mustahil ada di kredensial asli;
- Shadowsocks dengan method di luar yang didukung sing-box (di luar daftar itu
  dijamin ditolak core, jadi tidak mungkin pernah lulus).

Dipasang di `AutoParser.parse`, satu titik untuk SEMUA jalur parse
(share-link dan Clash YAML), dan masuk hitungan `unsupported` per sumber.

**Lapis-2 — jangan percaya begitu saja hasil penyaringan.**
`nodes.json` milik user bisa sudah berisi node rusak dari versi app sebelumnya,
dan feed berubah tanpa bisa diprediksi. Jadi `InternetProbe.prepareProbeConfig`
sekarang, kalau `sing-box check` menolak config, **membelah daftar dan
menyingkirkan yang ditolak** (biner search) alih-alih menyerah:

```
config ditolak → pecah dua → saring tiap separuh → gabung
```

Dengan `k` node rusak di antara `n` node: `O(k log n)` kali `sing-box check`.
`O(1)` kalau config-nya sehat. Satu `check` untuk 69 outbound cuma ~50 ms,
dan proses ini **hanya** jalan saat config memang ditolak.

Yang tersisa tapi tidak bisa dipakai dilaporkan sebagai
`probe_all_nodes_invalid` ("tidak ada server yang menghasilkan config
sing-box yang valid") — bukan "internet check skipped" yang menyesatkan.

### Kenapa dua lapis, bukan satu

Penyaringan parser saja tidak cukup: data user yang sudah rusak ada di disk.
Penyaringan probe saja juga tidak cukup: membiarkan 29 node sampah di daftar
berarti user melihat baris yang tidak akan pernah bisa connect.

### Verifikasi

- Di feed asli user: 16.464 node → 16.435 (**29 dibuang**), dan **0 dari 55
  jendela sesi** masih mengandung node korup.
- 96/96 test lulus. Test baru (5) memakai byte persis dari feed tersebut:
  `testCorruptSSLinkIsDroppedByAutoParser`,
  `testUnknownShadowsocksMethodIsDropped`,
  `testCorruptFeedNodeIsRejectedBeforeItCanPoisonTheProbe`,
  `testProbeConfigSurvivesCorruptNodeFromOldNodesFile`,
  `testAllCorruptNodesReportNoUsableNode`.

## D52 — Kolom IP di menu Server, 11-Okt-2026
- Minta user: "di menu server di samping tabel source tambahkan tabel ip, kalau
  pakai ip + port tambahkan ip + port, tergantung akun". Yang dimaksud akun =
  satu entri dari feed subscription; tiap entri punya alamatnya sendiri.
- Ditambah `TableColumn("col_ip")` **tepat di sebelah kanan kolom Sumber**
  (`ServersView`), bukan di ujung tabel: "node ini dari feed mana" dan "node ini
  nyasar ke mana" adalah dua pertanyaan yang biasanya muncul berurutan.
  Pertanyaan "dari feed mana" sudah dijawab kolom di sebelah kirinya, jadi
  mata langsung berpindah ke kanan.
- **Toggle, bukan dua kolom terpisah.** Kandidat kolom IP dan kolom Port
  ditolak: mayoritas host cuma punya satu port aktif, jadi kolom Port akan
  kosong di sebagian besar baris dan hanya menambah lebar tabel yang sudah
  mentok. Satu kolom dengan satu toggle (`AppSettings.showNodePort`) memberi user
  dua tampilan tanpa mengorbankan ruang. Default **ON** (`ip:port`) karena
  beberapa host dipakai lebih dari satu port — dengan IP saja dua node itu
  terlihat identik.
- Toggle ditaruh di **Settings → Subscription**, bukan di toolbar Server.
  Toolbar sudah padat (D29 pernah harus menyempitkan field cari 240→170 demi
  ruang toolbar), dan ini preferensi tampilan, bukan filter tampilan.
- `ProxyNode.endpoint(includePort:)` jadi satu-satunya tempat merakit
  `host`/`host:port`, dipakai bersama oleh kolom IP di Server **dan** kartu node
  di menu Sambung (`ConnectView`) — sebelumnya kartu itu menulis
  `"\(n.host):\(n.port)"` inline, jadi tanpa perubahan tambahan ia akan
  menampilkan bentuk berbeda dari tabel.
- `decodeIfPresent` untuk `showNodePort`: settings.json user tidak punya key
  ini, dan `decode` biasa akan membuat SELURUH pengaturan gagal load — termasuk
  toggle privasi yang sudah dikonfigurasi.

### Lebar window minimum ikut naik: 900 → 1040
D29 sudah mencatat bahwa lebar kolom di tabel Server **mentok di lebar window
minimum**, dan `Theme.minWindowWidth` disetel persis agar tidak ada yang
terpotong. Menambah kolom IP tanpa menaikkan batas itu akan mengulang bug yang
sudah pernah terjadi (header "Bendera" pernah jadi "Bend…").

Lebar kolom tetap setelah perubahan ini: bintang 30 + bendera 58 + sumber 110 +
**IP 150** + tipe 80 + ping 100 + aksi 120 = **648**. Dengan sidebar tersempit
(200) dan sisanya untuk kolom Nama yang fleksibel, minimum jendela 1040
menyisakan ±190 untuk Nama — cukup untuk nama feed yang panjang, dan tabel
menjadi bisa digeser (scroll) kalau memang sempit.

Sel IP memakai `truncationMode(.middle)` + tooltip `host:port` penuh: alamat
IPv6 (`2001:db8::1:443`) dipotong dari tengah jauh lebih terbaca daripada dari
ujung.

### Verifikasi
- 102/102 test lulus (dari 96). Test baru (6): `NodeEndpointTests` (4) —
  `ip` tanpa port, `ip:port`, domain ditampilkan apa adanya (feed gratis banyak
  yang pakai domain, bukan IP literal), dan IPv6 tidak ditulis ulang jadi
  bentuk lain; `AppSettingsTests` (2) — settings lama tanpa `showNodePort`
  tetap decode dengan setting lain utuh, dan toggle bertahan setelah
  encode→decode.
- `scripts/check-localization.sh` → OK, kunci EN == ID (`col_ip`,
  `show_node_port` di dua `.lproj`).

## D53 — Redesain UI enam layar mengikuti panduan visual (11-Okt-2026)

Enam layar (Sambung, Servers, Sumber, Split Tunnel, MAC Address, Setelan)
diganti total mengikuti mockup di `REDESAIN/`. Yang berubah adalah
*tampilan dan komponen*; tidak ada perubahan perilaku VPN.

### Palet gelap jadi keputusan, bukan pilihan sistem
Semua warna diturunkan dari satu palet navy + aksen mint (`DesignSystem/Palette`).
`preferredColorScheme(.dark)` dipasang di level window.

Alasannya: warna kustom (kartu, garis, chip, badge) hanya dirancang untuk latar
navy. Mode terang tidak dibuatkan varian kedua — memaksa gelap jauh lebih
jujur daripada menampilkan teks terang di atas isian gelap yang kontrasnya
salah. Kalau nanti tema terang benar-benar dibutuhkan, itu pekerjaan tersendiri
(palet kedua + audit tiap komponen), bukan sekadar membalik satu warna.

### Sidebar digambar sendiri, bukan `NavigationSplitView`
Mockup meminta kepala bermerek (logo + nama + tagline), butir nav berbentuk pil
mint, dan kartu open-source di kaki. `List` sidebar bawaan tidak bisa
membuatnya. `NavigationSplitView` diganti `HStack` dengan sidebar lebar tetap
236pt; `.windowStyle(.hiddenTitleBar)` supaya tidak ada dua bar judul.

Konsekuensi yang disadari: tombol split/sidebar bawaan (⌘⌃S dsb.) tidak ada.
Tidak ada pintasan yang hilang — semua aksi penting sudah punya tombol.

### Lebar minimum jendela naik: 1040 → 1160
Dua hal yang mengikat, keduanya naik:
- **Tabel Server** (D29/D52): lebar kolom tetap kini 602 (bintang 34 +
  negara 136 + sumber 104 + tipe 80 + latensi 92 + beban 98 + aksi 58).
- **Dashboard Sambung**: tiga kolom perlu 272 + 264 + ≥290 + spasi = 854,
  sedangkan lebar isi di jendela 1160 hanya 879.

Hanya batas bawah yang naik — tidak ada kolom tabel yang menyempit, jadi
batas D29 tetap terpenuhi.

`ViewThatFits` sempat dicoba untuk lowering otomatis ke tata letak bertumpuk,
DIBUANG: ViewThatFits mengukur lebar *ideal*, dan `recommendedCard` yang
fleksibel punya ideal jauh lebih lebar dari ruangnya, jadi hampir selalu
jatuh ke fallback meski tiga kolom sebenarnya muat. Karena `minWindowWidth`
sudah menjamin ruang, `HStack` biasa + kolom tengah fleksibel lebih jujur.

### Kolom Load: beban RELATIF, dan itu tertulis di tooltip
Feed gratis tidak melaporkan beban server asli. Yang ditampilkan adalah
seberapa jauh latensi satu server dari server tercepat **di daftar yang sedang
tampil**. Tooltip menyatakan itu eksplisit supaya tidak dibaca sebagai
"server sedang sibuk" (D-desain memakai label "Load", jadi tanpa catatan
sama sekali ini akan jadi kebohongan).

Belum ada pengukuran sama sekali → tampil "—", bukan "0%". "0%" terbaca
sebagai hasil ukur; padahal artinya "tidak diketahui".

### `countryCode` dapat nama yang terbaca
`CountryInfer.displayName(for:)` memetakan kode ISO ke nama negara
(sekitar 60 negara yang benar-benar muncul di feed gratis). Bendera tetap
ditampilkan berdampingan — bendera enak dilihat, nama bisa dicari dan disalin.
Kode yang tidak ada di daftar dikembalikan apa adanya ("JP"), bukan `nil`:
kolom kosong lebih membingungkan daripada kode yang bisa dibaca.

### Sakelar utama Split Tunneling + transaksi "Save"
Mockup menampilkan sakelar aktif/nonaktif dan tombol Save. Dua-duanya
memang belum ada.

- `SplitTunnelConfig.isEnabled` (default `true`). **`decodeIfPresent`** —
  `split.json` milik user yang sudah ada tidak punya key ini, dan `decode`
  biasa akan menghapus seluruh daftar aplikasi hanya karena app diperbarui.
- `effectiveMode`: sakelar mati ⇒ mode efektif selalu `.exclusive`. Ini bukan
  detail kecil. `configJSON` membaca mode untuk memilih `route.final`;
  kalau sakelar mati tapi mode tersimpan masih inklusif, `final` jadi
  `direct` — semua trafik keluar tanpa VPN, tepat hal yang user minta untuk
  dicegah dengan mematikan split. `isBypassAll` juga ikut memakai
  `effectiveMode`, jadi sakelar mati tidak salah dibaca sebagai "bypass semua".
- **Perubahan tidak langsung ditulis.** Daftar aplikasi, mode, dan sakelar
  ditahan di buffer lokal sampai `Save`. Alasannya bukan sekadar mengikuti
  mockup: aturan split baru baru benar-benar berlaku setelah reconnect, jadi
  menyimpan di tengah jalan hanya memberi kesan "sudah berlaku" padahal
  belum. `isDirty` (= buffer ≠ tersimpan) mengaktifkan tombol Save dan
  menampilkan peringatan "perubahan belum disimpan".
- `replaceActive(with:)` memindahkan daftar ke mode aktif dan mengosongkan
  mode lama, supaya tidak ada daftar yatim yang diam-diam masih ikut dibaca.

### Riwayat MAC disimpan sungguhan
Mockup MAC Address punya tabel "Riwayat". Tidak ada data seperti itu di app —
satu-satunya cara mengisinya tanpa storage adalah memakai `Date()` saat
dirender, yang akan terlihat benar padahal setiap baris selalu bilang
"baru saja".

Jadi `mac_history.json` ditambahkan: `MACHistoryEntry` dicatat **hanya** saat
`setMAC` benar-benar berhasil (kegagalan tidak dicatat — riwayat harus berisi
perubahan nyata, bukan niat). Dipotong 100 entri terbaru.
`AppState.insertingMACChange(_:into:limit:)` murni & nonisolated supaya
pemotongan bisa diuji tanpa actor dan tanpa menyentuh berkas user.

### Laju trafik diturunkan dari total
Clash API `/traffic` hanya melaporkan total byte, bukan laju.
`ConnectionManager.applySample(up:down:now:)` menurunkan byte/detik dari
selisih dua sampel berurutan (interval 2 detik), menambahkannya ke riwayat
ringkas 40 titik (~80 detik) untuk sparkline.

Tiga hal yang ditangani eksplisit:
- Sampel pertama **tidak** menghasilkan laju — hanya establishing titik awal.
- Total yang turun (reset saat core restart) **tidak** menghasilkan laju
  negatif; sparkline akan menggambar ke bawah sumbu.
- `startStats()` mengosongkan riwayat, jadi sisa sesi sebelumnya tidak
  terbaca sebagai trafik sesi ini.

### "Good evening" jadi sapaan sesuai jam
Mockup menampilkan "Good evening" sebagai judul. Menampilkannya buta bisa
salah enam jam dalam sehari, jadi `greeting_morning/afternoon/evening`
dipilih dari `Calendar.current.component(.hour:)`.

### Urutan server: tiga tingkat, bukan satu angka
`ConnectView.byLatency` upgraded ke tiga tingkat:
1. terukur dan punya latensi (paling cepat),
2. **belum pernah diuji** (masih mungkin bagus),
3. **terbukti tidak punya internet** (selalu terakhir).

Tingkat 2 dan 3 sama-sama punya `bestMs == nil`, jadi kalau hanya dibandingkan
per angka keduanya seri dan urutannya jatuh ke nama — server mati bisa muncul
mendahului server yang belum diuji. Itu persis kebalikan dari cara app
memilih node ("node yang terbukti TIDAK bisa internet tidak pernah dipilih
selama masih ada alternatif"). Bug ini ditemukan oleh test yang ditulis untuk
redesain ini.

### `Picker` diganti `DropdownMenu`
`Picker` + `.pickerStyle(.menu)` di macOS 13 masih menggambar isian terang
sistem — kotak abu-abu terang di tengah kartu gelap, satu-satunya kontrol yang
tidak menyatu dengan palat. `DropdownMenu` memakai `Menu` (perilaku native:
satu klik, keyboard, VoiceOver) tapi seluruh penampilannya digambar sendiri.
Dipakai di Setelan: skala UI, bahasa, segarkan otomatis.

### Jebakan `Text(String)` = verbatim
`Text` dengan nilai `String` runtime dirender **verbatim** — tidak pernah
mencari ke tabel terjemahan. Tiga tag kualitas di bawah peta sempat tampil
apa adanya (`card_tag_fast`, "VMe ss", "Tr oj an"). Aturan yang dipakai
selama redesign: nilai dinamis dari `L10n`/menurut tipe → `Text(verbatim:)`;
nama protokol (`p.badgeTitle`) → varian `FilterChip(title:)` yang eksplisit
`verbatim`, karena "VMess" bukan kalimat dan tidak boleh dicari di tabel.

`FilterChip` juga `.lineLimit(1)` + `.fixedSize()`: tanpa itu HStack
mampatkan label protokol jadi dua baris.

### Verifikasi
- **125/125 test lulus** (dari 102). Test baru (23) di `RedesignLogicTests`:
  split lawas tanpa `isEnabled` (daftar + mode utuh), sakelar mati ⇒
  `final=proxy` dan tanpa aturan proses, `effectiveMode`, `replaceActive`,
  round-trip JSON split, batas & urutan riwayat MAC, tiap `kind` punya judul
  terlokalisasi, sampel trafik pertama/tunggal/lima, batas riwayat,
  `displayName` + fallback, Load relatif & batas 0…1, `byLatency` tiga tingkat,
  `nearestShare` kelipatan 25.
- `scripts/check-localization.sh` → OK, kunci EN == ID (312 kunci, +139 baru).
- Enam layar dijalankan & diperiksa satu per satu pada jendela 1160×728.
- Smoke test visual menangkap tiga bug yang sudah diperbaiki di atas:
  tag kualitas verbatim, judul kartu dua baris, chip protokol terpotong.

## D54 — Peta DotMap di layar Sambung (11-Okt-2026)

Peta dekoratif (`Canvas` + elips, hasil D53) diganti **DotMap** — port Swift
dari https://github.com/spilneo/DotMap. Peta dunia asli dari GeoJSON, dirender
ribuan titik lewat `Canvas`.

### Dipakai SPM? Tidak mungkin — jadi vendored
`Package.swift` upstream memakai `swift-tools-version: 5.9`, dan SwiftPM di
Xcode 14.3.1 (Swift 5.8.1) menolaknya outright:

    error: package 'dotmap' is using Swift tools version 5.9.0
           but the installed version is 5.8.1

Naikkan Xcode ke 15+ berarti bentrok dengan toolchain yang dipin di README dan
seluruh pipeline build (`build-core.sh` prebuilt + `lipo`, tanpa brew), jadi
sumbernya **divendor** ke `FreePN/Vendor/DotMap/` (MIT, lisensi ikut).

Sebelum commit: kode upstream di-`swiftc -typecheck` terhadap SDK macOS 13
menghasilkan **0 error** — yang blocking hanya manifest-nya. Jadi salinannya
hampir utuh:

- `Bundle.module` → `Bundle.main` (sumber GeoJSON ada di bundle app, bukan SPM)
- `countries.geo.json` (257 KB) masuk Resources build phase
- `IPLocationService.swift` **DIBUANG** — lihat butir privacy di bawah
- Banner 6 baris di tiap file menyatakan asal & alasan modifikasinya, supaya
  siapa pun yang `grep` DotMap tahu itu salinan, bukan modul

**Konsekuensi yang disadari:** app sekarang punya salinan kode pihak ketiga
yang harus di-*sync* manual saat upstream berubah (tidak ada `swift package
update`). Ditulis di banner setiap file supaya tidak dilupakan. Kalau toolchain
naik ke Xcode 15+, bagian ini sebaiknya dikembalikan ke SPM lalu vendor ini
dihapus.

### Tidak ada geolokasi berbasis IP
DotMap menyediakan `IPLocationService` yang memanggil **ipwho.is / ipinfo.io**.
Dipakai berarti IP publik user dikirim ke pihak ketiga setiap kali peta dirender
— tidak pantas untuk app yang slogannya "Your privacy matters". Berkasnya
tidak ikut divendor sama sekali (bukan "dipakai tapi dimatikan": kode yang tak
dipakai lebih baik tidak ada).

Sebagai gantinya, pin diambil dari **tabel centroid lokal** di
`CountryInfer.centroids` (60 negara, ±1–2 derajat dari pusat geografis).
Untuk satu pin di peta selebar ~300pt, presisi itu tak terlihat — yang penting
pinnya ada dan tidak keliru. Node yang negaranya tidak diketahui **tidak dapat
pin sama sekali**; peta tanpa pin jauh lebih jujur daripada pin di Samudra
Tengah.

### Inferensi nama negara diperbaiki — 3,6% → 7,3%
Pin hanya berguna kalau negara diketahui, jadi `CountryInfer.infer` diperluas:
nama negara Mandarin (美国/新加坡/日本/德国…) dan kode ISO telanjang di batas
kata (`US`, `CA`, `RU`), keduanya divalidasi ke tabel negara yang sudah ada.

Alasannya diukur, bukan asal menambah pola: feed terbesar menamai server dalam bahasa
Mandarin, dan `infer` lama hanya mengenali `[XX]`, `(XX)`, dan emoji bendera.
Diukur pada `nodes.json` asli (16.315 node):

| | inferable | |
|---|---|---|
| sebelum | 586 | 3,6% |
| sesudah | 1.186 | 7,3% |

**Regresi: nol.** Sisa 92,7% memang tidak punya informasi lokasi — 12.579 node
(77%) bernama persis `By EbraSha ⌨️`, yaitu nama penulis feed dengan emoji
keyboard. Tidak ada yang bisa ditebak dari sana, dan mengarang lokasi untuk
node seperti itu lebih buruk daripada tidak menampilkannya.

### Proyeksi Robinson, kisi diagonal, cache statis
Robinson dipilih: enak dibaca untuk peta dunia yang lebar pendek (kartu ~300pt)
dan tidak menyebabkan utter-utter Mercator yang membesar di kutub.
`DottedMap` dihitung sekali di `DotMapCache` — membangun ulang tiap render
membakar CPU di layar yang paling sering digulir.

### Verifikasi
- **133/133 test lulus** (dari 131). Test baru (2) untuk pin peta: koordinat
  benar untuk negara yang dikenal; **tanpa pin** untuk nama tanpa negara,
  `countryCode` tak dikenal, dan `nil`. Plus test centroid: setiap negara
  yang punya nama wajib punya centroid.
- Build Debug + Release + Helper sukses; `check-localization.sh` OK (313 kunci).
- Diketag MIT di `LICENSES/THIRD-PARTY.txt` dan di layar Settings → About.

---

## D55 — GeoIP lokal MaxMind GeoLite2 City (11-Okt-2026)

### Masalah
Kolom Country/Diagram gave up pada 92,7% node. Feed gratis hampir tidak pernah
menandai lokasi: 77% node bernama persis `By EbraSha ⌨️`. D54 menutup peta dengan
centroid, tapi itu tebakan kasar — hanya benar di level negara.

### Keputusan
Database **MaxMind GeoLite2 City** (bukan Country), dibundel sebagai binary
flat sendiri, dibaca entirely offline. Tidak ada API pihak ketiga sama sekali.

Dua tahap, karena keduanya punya biaya berbeda:

| Tahap | Biaya | Cakupan |
|---|---|---|
| Nama node (emoji / `[XX]` / Mandarin) | nihil | ~4% |
| GeoIP atas IP literal, saat parse | ~0 (binary search) | ~69% |
| DNS lalu GeoIP, setelah refresh | 1 query per domain unik | ~31% tersisa |

Tahap ketiga sengaja **tidak** ada di parser: parser itu sinkron dan berjalan
di background, dan resolusi blocking di sana akan menahan seluruh refresh
atas nama beberapa ratus domain. Jadi ia dipindah ke `enrichCountries()` —
satu pass setelah semua sumber selesai, 16 query sekaligus, dibatasi 600 host
unik per refresh.

### Kenapa City, bukan Country
Karena tersedia koordinat kota, pin peta bisa menunjuk lokasi server, bukan
centroid negara. Selisihnya antara beberapa ratus kilometer untuk kota yang
sama — jauh lebih berarti di peta selebar 300pt.

### Format: `FPNGEO02`, record 11 byte
MaxMind Reader Swift bisa dipakai, tapi butuh `Data` 48,4 MB utuh di memori
plus objek node untuk tiap record. Flat binary yang kita bangun sendiri:

```
header  8 byte  "FPNGEO02"
records N × 11 byte, urut naik menurut startIP
        [4 byte startIP][2 byte negara][2 byte lat][2 byte lon][1 byte span]
```

Total **25,28 MB**, 2.409.577 record. Dibaca lewat `mmap`, lalu binary search 22
kali untuk satu lookup. Nol alokasi.

`span` byte itu wajib, bukan sisa ruang: MaxMind/**/*.24** untuk IP agotado dan
blok khusus, dan tanpa span IP tersebut akan mewarisi negara record sebelumnya
— mis. 10.0.0.0/8 dikira Hong Kong.

### Yang TIDAK dilakukan
- Tidak menulis ke `~/.config/geoip/` milik MaxMind (root-owned, butuh sudo).
- Tidak memakai `DB-IP` CSV — uplink-nya ~40 MB dan berbau commercial untuk
  lisensi gratis.
- Tidak melakukan lookup via Homebrew `sing-box` — menjalankan subprocess
  2.4 juta kali bukan opsi.

### Kewajiban lisensi (EULA GeoLite2)
- Atribusi MaxMind + GeoNames wajib tampil: sudah ada di Settings → About →
  Third-Party Licenses, dan di `LICENSES/THIRD-PARTY.txt`.
- **Database harus diperbarui ≤30 hari.** Build 11-Okt-2026 memakai edisi
  `GeoLite2-City_20261009` — tenggatnya **9 November 2026**.
  Aturan ini memang ada dalam EULA; kita tidak meng-automate unduhannya karena
  MaxMind butuh login + persetujuan Terms of Use, jadi tanggalnya wajib dicatat.

### Angka hasil pengukuran (nodes.json asli, 16.315 node)
Dijalankan headless dengan **kode produksi yang sama persis** (`GeoIP.swift`
+ `GeoIPResolver.swift` dikompilasi ke harness terpisah), bukan perkiraan:

| Tahap | Tertambah | Kumulatif |
|---|---|---|
| Sudah ada (nama/emoji, 4 manual) | 590 | 3,6% |
| GeoIP atas IP literal — tanpa jaringan | 8.213 | **54,0%** |
| DNS + GeoIP, sampel 40 domain unik | 9 dari 40 (22,5%) | **~58,3%** |

Dari 10.824 literal, 2.611 tidak kena — itu memang IP privat/reservat atau
ruang yang tidak punya data GeoLite2. Dari domain, sebagian besar nama host-nya
sudah mati (polluter `.cfd`, domain gratis yang dibuang); 9 dari 40 yang hidup
memberi **koordinat kota** tepat, bukan cuma negara.

Sisa **41,7% benar-benar tidak punya informasi lokasi** di sumbernya. Kalau
kita menebak, kita menampilkan lokasi yang salah — lebih buruk dari kosong.

Biaya: 40 domain habis **3,5 detik** (~87 ms/domain, 24 paralel). 3.140
domain unik ≈ 11 detik, jauh di bawah tenggat 45 detik. Tahap 1 jauh lebih
murah: seluruh 8.803 node terisi dalam **52 milidetik**.

### Regresi yang sempat ada di tahap 1 (pelajarannya)
Versi pertama memberi `limit` per putaran untuk host IP literal, dengan
alasan "kerja ini gratis". Itu **salah**, dan tidak ketahuan dari UI:
host yang memang tidak punya lokasi (IP privat, ruang tanpa data) tidak
pernah keluar dari daftar target, jadi mereka memenuhi kuota **setiap
putaran**, sementara host yang benar-benar punya negara di urutan berikutnya
tidak pernah ikut diperiksa.

Terukur: hanya **6.438 dari 8.213** node yang terisi — dan kolom Country
tetap terlihat "berjalan normal". Diperbaiki jadi satu kali jalan tanpa
batas (**52 ms**, lengkap 8.803).

Pelajarannya: batas waktu itu untuk pekerjaan yang **mahal**. Untuk
pekerjaan gratis, batas justru menciptakan work queue yang tidak pernah
kosong. Tes `testLiteralPassFillsEverythingInOneSweep` khusus menjaga ini —
400 host tanpa lokasi disisipkan di depan, lalu tetap harus terisi 50/50.

### Verifikasi
- **149/149 test lulus** (dari 142). Test baru (7): pemisahan literal vs
  domain; `limit` dihormati; jalur gratis menutup SELURUH daftar dalam
  sekali jalan (regresi kuota di atas); pass kedua idempoten; IP literal
  tidak pernah menyentuh DNS; cache koordinat bisa dibersih; domain tanpa
  koordinat jatuh ke pin centroid (bukan pin ngawur).
- `NSLock` di dalam konteks async diganti `withLock` — `lock()`/`unlock()`
  di async adalah **error di Swift 6**, bukan sekadar peringatan.
- `getaddrinfo` dipindah ke `DispatchQueue` terpisah: ia blocking, dan
  cooperative pool Swift hanya punya thread sebanyak jumlah core.
- `check-localization.sh` OK (314 kunci).
- Build Debug + Release + Helper sukses.

---

## D56 — Bendera di kolom Country + urutan kolom yang bisa diklik (11-Okt-2026)

### Permintaan user
1. Kolom Country di menu Server pakai **ikon bendera**, bukan tulisan.
2. Fitur **urut berdasarkan sumber** yang hilang.

### 1. Bendera, bukan nama
D55 sengaja mengganti bendera dengan nama negara, dengan alasan "nama bisa
dicari dan disalin". Itu memang benar untuk **tooltip** — tapi salah untuk
**kolom**. Di tabel 16.000 baris, kolom bernama "United Kingdom"/"South Korea"
memakan ruang yang jauh lebih mahal daripada dua glyph, dan yang dicari user
saat memindai tabel adalah bentuknya, bukan mengeja namanya.

Jadi: kolom = bendera, tooltip = nama. Tidak ada informasi yang hilang.

Sampingan yang ikut dibereskan: `flagEmoji` dulunya mengubah kode apa pun
yang panjangnya dua huruf menjadi regional indicator. `🇿🇿` untuk "ZZ"
dirender sebagai huruf "ZZ" — terlihat seperti bendera sungguhan padahal tidak
ada negara seperti itu. Sekarang kode yang tidak dikenal menghasilkan 🌐.

### 2. Urutan kolom
Sebelumnya tidak ada model urutan sama sekali: `resort` hanya mengurutkan
"sumber berbintang dulu, lalu nama". Di data asli ada **7 sumber dengan
ukuran sangat tidak seimbang** (EbraSha 12.721 dari 16.521 node), jadi
membandingkan dua feed tanpa pengelompokan sumber hampir mustahil.

Sekarang setiap kolom bisa diklik (country, source, name, proto, latency,
load). Default = **sumber**, menaik — persis yang hilang.

Tiga keputusan yang tidak otomatis:
- **Sumber berbintang tetap di atas, apa pun kolomnya.** Mencentang sumber di
  menu Sumber berarti "ini yang saya pakai"; menguburnya di bawah yang lain
  melawan niat user. Ini juga mempertahankan perilaku `resort` lama.
- **`nil` selalu tenggelam, apa pun arah.** Server yang belum di-ping bukan
  "paling lambat", dia *belum punya nilai*.
- **Klik pertama pada kolom latency/load = lambat ke cepat.** User yang
  mengurutkan latency hampir selalu sedang mencari yang tercepat, jadi itu
  yang harus muncul lebih dulu.

### Regresi yang tertangkap tes
"Aturan `nil` tenggelam" sempat ditulis sebagai perbandingan biasa di dalam
closure yang sama dengan pembalikan `ascending`. Akibatnya `ascending == false`
membalik aturan itu juga — dan baris yang belum di-ping justru **melompat ke
paling atas**. Terlihat benar secara visual (yang lambat memang di atas)
padahal 15.000 node yang belum di-ping ikut naik bersamanya.

Diperbaiki dengan mengecek `isUnknown` **sebelum** `ascending` diterapkan.
Tes `testUnknownLatencySinksToBottom` menjaga kedua arahnya.

### Verifikasi
- **157/157 test lulus** (dari 149). Test baru (8): pengelompokan per sumber;
  klik ulang membalik arah; latency mulai lambat; `nil` tenggelam di kedua
  arah; sumber berbintang tetap di atas; urutan stabil terhadap `shuffled()`;
  bendera fallback ke 🌐; nama negara tetap ada untuk tooltip.
- `check-localization.sh` OK (316 kunci).
- Build Debug + Release sukses.

---

## D57 — Dropdown filter sumber di menu Server (11-Okt-2026)

### Permintaan
Filter per sumber di menu Server lewat **dropdown**, isi dari daftar sumber.

### Kenapa dropdown, bukan chip
Chip protokol hanya 4 pilihan — muat di baris. Sumber tidak: data asli punya
7 sumber dengan ukuran sangat tidak seimbang (EbraSha 12.721 dari 16.521
node, sisanya 92–1.788). Deretan chip akan memakan seluruh baris filter,
sehingga ketemu chip-nya tapi kehilangan "Sembunyikan yang mati" dan jumlah
server. Menu yang bisa dibuka menyelesaikan keduanya.

Bukti bahwa fitur ini pernah ada: kunci terjemahan `filter_all_sources` sudah
ada di `en.lproj` **dan** `id.lproj`, tapi tidak dipakai satu pun file Swift —
sisa UI sebelum redesign, seperti `sort` di D56.

### Isi menu
Hanya sumber yang punya node (`keptCount > 0 || nodeCount > 0`), berbintang
lebih dulu lalu menurut nama. Sumber mati tidak dicantumkan: memilihnya cuma
menghasilkan tabel kosong, dan itu terlihat seperti filter-nya rusak — bukan
seperti "sumber ini memang kosong".

Label tombol memakai `activeSourceFilter`, bukan `sourceFilter` mentah.
`activeSourceFilter` mengembalikan `nil` kalau sumber yang ditunjuk sudah tidak
ada. Tanpa itu, `sources.json` yang diganti dari luar app (atau sesi
sebelumnya) meninggalkan filter aktif tapi label sudah balik ke "Semua
sumber": **tabel terkunci kosong tanpa alasan yang terlihat dan tanpa cara
membatalkannya**. Tombol "Clear filter" sekarang juga ikut memakai nilai
yang sama, jadi tidak pernah menampilkan "Clear filter" untuk filter yang
tidak ada efeknya.

### Dua bug lama di `removeSource` (ketemu karena tes)
Tes "hapus sumber harus melepas filternya" gagal — dan penyebabnya bukan
fitur baru:

1. **`nodesAfterRemovingSource` mengembalikan node yang TETAP** (`!= id`),
   tapi pemanggilnya menyimpannya sebagai `dropped` dan memakainya sebagai
   daftar node yang **dihapus**. Akibatnya `gone = Set(dropped...)` berisi
   id node yang justru masih ada — jadi menghapus satu feed akan menghapus
   **seluruh favorit dan hasil ping milik feed lain**, dan membuat
   `selectedNodeID` kosong kalau node terpilih bukan dari feed yang dihapus.
2. **Kalau sumber yang dihapus adalah satu-satunya sumber**, sisa nodenya
   kosong sehingga `if !dropped.isEmpty` dilewati — node-nya tidak pernah
   hilang sama sekali dan tetap nangkring di daftar.

Keduanya diperbaiki dengan menghitung node yang terhapus lebih dulu. Kontrak
`nodesAfterRemovingSource` sendiri sudah benar dan sudah punya tes, jadi
dipakai apa adanya.

### Verifikasi
- **162/162 test lulus** (dari 157). Test baru (5): filter sumber menyaring;
  filter sumber basi tidak mengunci tabel; hapus sumber melepas filter;
  sumber/pin/favorit lain tetap utuh; filter sumber menyatu dengan pencarian
  dan filter protokol.
- `check-localization.sh` OK (317 kunci).
- Build Debug + Release + Helper sukses.

---

## D58 — Insiden: unit test menimpa data user (11-Okt-2026)

### Yang terjadi
D57 menambah dua tes untuk `removeSource`. Tesnya membuat `AppState()` —
**instance sungguhan** — lalu memanggilnya. `AppState.init` memuat dari
`~/Library/Application Support/FreePN/`, dan `persist()` menulis ke sana.
Akibatnya `sources.json`, `nodes.json`, dan `favorites.json` milik user
**tertimpa data uji coba**. Seluruh daftar langganan hilang.

Tingguhan beberapa detik setelah itu: tes itu gagal dengan
`XCTAssertTrue failed` — bukan karena fitur barunya salah, tapi karena
`removeSource` memang tidak berperilaku seperti yang diasumsikan. Kalau tes
sudah hijau lebih dulu (atau tidak pernah ditulis), data user hilang tanpa
sinyal apa pun.

### Akar masalahnya
Bukan salah tes — tapi **tidak ada batas antara penyimpanan app dan lokasi
test**. `JSONStore` dan `SubscriptionCache` masing-masing menghitung sendiri
`Application Support/FreePN/`, tanpa jalan untuk diarahkan ke tempat lain.
Jadi secara struktural, **unit test mana pun yang menyentuh `AppState` pasti
menulis ke data asli user**.

### Perbaikan
1. **`AppStorage`** — satu pintu untuk semua path disk. `overrideDirectory`
   (hanya test) mengarahkan `JSONStore` dan `SubscriptionCache` ke folder
   sementara. Di produksi perilakunya persis sama seperti sebelumnya.
2. **`TestSupport.isolateStorage()`** — dipanggil `setUp`, dibersihkan lewat
   `addTeardownBlock`. Tiga tes yang membangun `AppState` sekarang memanggilnya.
3. **Diverifikasi, bukan diasumsikan**: md5 + mtime `sources.json` dicatat
   sebelum dan sesudah seluruh suite dijalankan. Tidak berubah. Tes yang
   menghapus sumber sekarang hanya menyentuh folder sementara.

### Pemulihan
- `subcache/` (15 feed, 6,4 MB) **utuh** — ditulis 19:29, sebelum insiden.
- Cache di-key dengan **UUID sumber**, bukan URL. Jadi memulihkan UUID yang
  sama membuat semua feed kembali **offline** lewat fallback
  `SubscriptionCache.loadStale` — tanpa satu pun unduhan, dan tanpa bergantung
  pada URL yang saya tebak.
- `sources.json` dibangun ulang dengan 15 UUID asli + nama hasil identifikasi
  isi feed. Diverifikasi: `sources.json` deserialize OK dan 15/15 sumber punya
  cache valid.
- **Yang TIDAK bisa dipulihkan**: URL asli tiap feed, `favorites.json`, dan
  nama sumber yang tidak bisa dipastikan dari isi feed. URL hasil tebakan —
  cache tetap membuat node muncul, tapi refresh online bisa gagal sampai
  URL diperiksa di menu Sumber.
- `nodes.json` akan dibangun ulang sendiri saat app dibuka.

### Pelajaran
Tidak ada kode produksi yang perlu diubah untuk mencegah kebocoran data —
yang perlu diubah adalah **batasnya**. Dan setiap tes yang menyentuh
penyimpanan harus bisa dibuktikan tidak keluar, bukan hanya "seharusnya tidak".


---

## D59 — Nama sumber jujur, edit sumber, cincin fokus sidebar (11-Okt-2026)

### 1. Nama sumber setelah pemulihan — pisahkan "terbukti" dari "tebakan"
D58 memulihkan `sources.json` dengan nama hasil tebakan. Empat nama (EbraSha,
Au1rxx, Anaer, Ermaozi) **tidak punya bukti sama sekali** — hanya "mirip
ukuran jumlah proxy". Itu berbahaya: nama yang terlihat meyakinkan tapi
dipilih tanpa dasar, dan user tidak bisa bedakan mana yang benar.

Sekarang isinya dipisah tegas:

| Kelas | Jumlah | Contoh |
|---|---|---|
| **Terbukti** — feed menyebut namanya | 7 | morpheusadam, 0xRadikal, freenodedaily, barry-far, zhuhai, a9a, vvkj11 |
| **Perkiraan** — hanya cocok jumlah proxy | 5 | EbraSha, Au1rxx, Anaer, Ermaozi, Free18 |
| **Tanpa identitas** — feed tidak menyebut siapa pun | 3 | "Feed (400)", "Feed (150)", "Feed (0)" |

Tujuh feed yang tidak menyebut identitas **tidak lagi diberi nama karangan**.
Diberi nama netral plus jumlahnya, supaya jelas itu belum teridentifikasi dan
bukan keputusan.

### 2. Sumber bisa diedit
Sebelum D58 sumber hanya bisa ditambah, dihapus, di-refresh, dibintangi.
Artinya setelah pemulihan — nama salah dan URL tebakan — user **tidak punya
cara memperbaikinya kecuali mengedit JSON manual**.

Klik kanan tiap baris → **Ubah Nama / URL…** (form yang sama dengan tambah,
berubah jadi mode edit).

Dua detail yang menentukan benar/tidaknya fitur ini:
- **ID sumber tidak boleh berubah.** `SubscriptionCache` di-key dengan UUID
  sumber; mengubah ID membuat seluruh cache feed itu tidak terpakai dan semua
  node hilang sampai diunduh ulang. ID karena itu dikunci.
- **URL berubah → hitungan direset.** Kalau tidak, user melihat node dari feed
  LAMA dengan nama sumber yang sudah baru — sangat membingungkan dan sulit
  didiagnosis.

### 3. Cincin fokus abu-abu di "Connect"
macOS memberi fokus ke tombol pertama saat jendela dibuka, lalu menggambar
cincin fokus. Di sidebar berarti "Connect" selalu berbingkai abu-abu —
meski layar aktifnya Settings. Terlihat seperti **dua keadaan aktif
sekaligus**, persis yang tidak boleh terjadi di navigasi.

`.focusEffectDisabled()` hanya ada sejak **macOS 14**; project ini memakai
SDK macOS 13, jadi satu-satunya cara adalah `.focusable(false)`.

Konsekuensinya: navigasi papan ketik sidebar hilang — Tab tidak lagi sampai
ke butir sidebar. Supaya tidak menjadi regresi, ditambah menu **Navigate
⌘1…⌘6**. `selection` harus pindah dari `@State` di `ContentView` ke
`AppState`, karena `.commands` hanya bisa dipasang pada `Scene`, bukan pada
`View`.

### Verifikasi
- **166/166 test lulus** (dari 162). Test baru (4): nama dipangkas spasi dan
  cache nama ikut diperbarui; **ID sumber tidak berubah saat edit**; URL
  berubah mereset hitungan; input kosong tidak menimpa nilai lama.
- Isolasi storage **masih terbukti**: md5 `sources.json` identik sebelum dan
  sesudah seluruh suite dijalankan.
- `check-localization.sh` OK (321 kunci).

---

## D60 — Tabel sejajar, kartu daya setinggi rekomendasi, edit sumber dari baris (11-Okt-2026)

### 1. Kartu daya tidak sejajar bawah dengan kartu rekomendasi
Di layar Sambung, kartu "Terputus" berhenti di mana pun isinya berakhir,
sementara kartu "Server Direkomendasikan" tingginya ditentukan peta 260pt +
alamatan kualitas. `HStack` menyamakan posisi atas, bukan tinggi — jadi dua
kartu itu berujung di dua garis bawah beda.

Perbaikan: kartu daya kini `.frame(maxHeight: .infinity, alignment: .top)` +
`Spacer(minLength: 0)` sebelum penutup, sehingga ia mengisi tinggi baris
yang sama dengan kartu rekanannya.

### 2. Header tabel Sumber tidak sejajar dengan isinya
Dua penyebab yang saling menutupi:
- **Offset horizontal beda**: header diberi `padding(.horizontal, 14)`
  langsung, sedangkan baris berada di dalam `LazyVStack` yang punya padding 8
  DI PLUS `TableRowView` padding 14. Hasilnya seluruh header bergeser ±8pt
  dari kolomnya.
- **Lebar kolom Keterangan tidak sama**: header `minWidth: 220`, baris
  `minWidth: 160`. Kolom yang menyusut tidak pernah menyusut identik.

Perbaikan: header diberi lapisan padding 8 tambahan (identik dengan container
baris), kolom keterangan diset `minWidth: 280` di kedua sisi, kolom Status
110, Diperbarui 110, Aksi 98.

### 3. Aksi baris Sumber: edit kini tombol, bukan cuma klik kanan
Sejak D59 edit sumber hanya ada di context menu — tombol tak berlabel itu
benar tapi tidak dapat ditemukan. Setiap baris tabel Sumber sekarang punya
tiga ikon dalam lingkaran (mengikuti gaya tombol aksi tabel Server):
refresh, **pensil (edit nama/URL)**, dan hapus — lewat helper
`rowIconButton` yang dipakai tiga-tiganya.

### 4. Menu Sumber mepet → jendela minimum naik
Total lebar kolom tetap tabel Sumber sekarang 868pt (bintang 34 + sumber 230
+ status 110 + keterangan 280 + diperbarui 110 + aktif 46 + aksi 98 + spacing).
Ditambah tepi kartu/layar, batas jendema 1160 membuat bar aksi tepi kanan
terdesak dan mepet. `Theme.minWindowWidth` 1160 → **1240**, tinggi 700 → **760**.
Hanya menaikkan batas bawah — tidak ada kolom yang menyempit, D29 tetap
terpenuhi.

### Verifikasi
- Build Debug **BUILD SUCCEEDED** (ada tanda tangan Apple Development).
- **166/166 test lulus**. `check-localization.sh` OK — tidak ada key baru
  (semua label yang dipakai sudah ada: `action_retry`, `action_edit_source`,
  `delete_source_help`).

---

## D60b — Cincin fokus abu-abu di tombol "Segarkan", 11-Okt-2026

### Laporan
Saat jendela dibuka, tombol "Segarkan" di header layar Sambung punya
outline abu-abu — bukan outline mint dari `SecondaryButtonStyle` yang
digambar sendiri.

### Akar masalah
macOS memberi fokus keyboard ke tombol pertama yang bisa difokus saat
window tampil; SwiftUI memilih tombol "Segarkan" di header. Cincin fokus
abu-abu itu digambar SISTEM, menimpa outline mint tombol, dan tidak hilang
sampai user mengklik atau berpindah tab.

Upaya pertama gagal: memanggil `.focusEffectDisabled()` dari
`ButtonStyle` — API itu ada sejak macOS 14/SDK 14, sedangkan app ini
build dengan SDK 13.3 (Xcode 14.3.1), jadi compiler menolaknya. Upaya
kedua (`.focusable(false)` di sidebar, dari D59) hanya menutup satu titik
dan mencabut navigasi Tab di butir nav — justru melanggar D59.

### Perbaikan yang benar (root cause)
Setelah window terpasang, tarik kembali first responder ke window:
`window.makeFirstResponder(nil)`. Dibungkus `WindowFocusCleaner`, sebuah
`NSViewRepresentable` berukuran nol yang ditempel `.background()` di
`ContentView` — jaminan view-nya ada di window yang sama.

Konsekuensi yang menguntungkan:
- Tidak ada tombol yang otomatis jadi first responder saat app dibuka —
  cincin abu-abu itu menghilang di SEMUA layar, bukan cuma Sambung.
- Navigasi Tab antar tombol tetap berfungsi (beda dengan
  `.focusable(false)`), jadi D59 tidak regresi.
- Berlaku juga untuk app yang dibuka langsung ke layar lain (⌘1…⌘6).

### Verifikasi
- Build Debug **BUILD SUCCEEDED**, **166/166 test lulus**.
- Catatan SDK: kalau suatu saat upgrade ke Xcode 15 (SDK 14+), pendekatan
  ini tetap benar; `.focusEffectDisabled()` per tombol tidak lagi diperlukan.

---

## D60c — Kolom Keterangan tabel Sumber dipersempit, 11-Okt-2026

### Laporan
Kolom Keterangan di menu Sumber terlalu lebar — teksnya pendek
("12824 dipakai · 8 tidak didukung") tapi slotnya sampai ±300pt.

### Perubahan
Kolom Keterangan jadi **fleksibel**: `minWidth: 210, maxWidth: 290`
( daripada `minWidth: 280` yang menyentuh batas kanan ). Sisanya — antara
lebar kolom ini dan tombol aksi — diserap spacer (`Spacer(minLength: 0)`)
yang ditambah HANYA di header DAN di baris (identik, supaya tetap sejajar).

Kenapa spacer dan bukan mengecilkan minWidth saja: tanpa kontrol sisa itu,
kolom mengembang sampai penuh dan masalahnya kembali ke semula; dan
karena kolom fleksibelnya rata kiri, tombol aksi perlu ditarik nempel ke
kanan secara eksplisit, bukan otomatis menyusul.

### Verifikasi
- Build Debug **BUILD SUCCEEDED**, **166/166 test lulus**.
- Build Debug + Release + Helper sukses.

---

## D61 — Audit performa & kebenaran menyeluruh, 12-Okt-2026

### Laporan
Audit penuh 15.607 baris Swift (Core VPN/Ping/Helper, Parser/Persistence/
Subscription, App/UI/DesignSystem) menemukan masalah di empat kategori:
performa UI, kebenaran hasil, crash, dan keamanan helper.

### Akar masalah utama (semua diperbaiki di bawah)

**Performa — invalidasi global (paling merusak):**
`AppState.relayChildChanges()` meneruskan `objectWillChange` LENGKAP dari
`ConnectionManager`, yang publish `upRate`/`downHistory` **tiap 2 detik**
selama terhubung. Satu tick = seluruh pohon view di-invalidate, termasuk
tabel 16.000 baris dan peta dunia yang sama sekali tidak menampilkan byte.
Di sisi lain, tiga turunan mahal (`bestLatency` O(n), `previewNodes` yang
melakukan `sorted()` penuh 16.000 node, `recommendedNode` dua lintasan O(n))
dihitung ULANG di dalam `body` — beberapa kali per frame.

Ditambah: `persist()` menulis ulang seluruh `nodes.json` (multi-MB) pada
SETIAP toggle pengaturan dan tiap step slider CPU-share; keenam `JSONStore`
dibaca sinkron di `@MainActor init`; `ConnectionLog.snapshot` membaca berkas
sinkron di main thread tiap 5 detik; semua `Timer` terdaftar di RunLoop
`.default` sehingga mati saat window di-drag.

**Kebenaran — hasil yang salah:**
- `InternetProbe.beginSession` membangun peta `id -> tag` dari daftar node
  ASLI, padahal `probeConfigJSON` menomori tag berdasarkan daftar SETELAH
  penyaringan `sing-box check`. Begitu satu node terbuang, setiap `probe-N`
  berikutnya dipetakan ke node yang salah — **angka latensi tampil untuk
  server yang tidak diuji**.
- `NodeDeduper` mencocokkan cipher Shadowsocks secara case-sensitive, jadi
  `AES-256-GCM` (yang sangat umum di feed gratis) dibuang.
- `CountryInfer`: `印度尼西亚` mengandung `印度`, dan `印度` diperiksa lebih
  dulu — node Indonesia diberi bendera India.
- `ShareLinkParser`: cabang base64 `hysteria2://` tidak pernah bisa jalan
  (`guard lastIndex(of: "@")` mendahului, dan alfabet base64 tidak memuat
  `@`); host IPv6 ditolak di `ss://` dan `hysteria2://`.
- `SourceResolver` memakai `Calendar.current` (zona mesin user), bukan
  kalender WIB/UTC yang justru dibangun lalu dibuang.
- `MacSpoofClient.listInterfaces` mengisi `hardwareMAC` dengan nilai yang
  sama dengan `currentMAC`, sehingga status "di-spoof" secara struktural
  SELALU false.
- `decodeIfPresent` untuk field enum (`language`, `status`) melempar saat
  nilainya tak dikenal, dan lemparannya ditelan `try?` — seluruh pengaturan
  / daftar sumber user kembali ke default, diam-diam. `ProxyNode` memakai
  `Codable` sintesis: satu field wajib baru = `nodes.json` lama tak terbaca =
  user membuka app ke daftar server KOSONG.

**Crash:** `CPUGovernor.fdSafeLimit` mengonversi `rlim_cur` ke `Int` tanpa
membatasi rentang — trap bila hard limit > `Int.max`.

**Keamanan:** `shouldAcceptNewConnection` di helper root mengembalikan `true`
selalu, sementara komentarnya menyatakan verifikasi code-signing dilakukan.
Proses lokal mana pun bisa menjalankan sing-box sebagai root, mengubah MAC,
atau mematikan VPN. Log di `/tmp` (world-writable) ditulis helper root lewat
`FileHandle(forWritingTo:)` — symlink LPE lokal.

### Perubahan

- **Relay sempit.** `relay(connection)` diganti empat projected-value
  Combine (`$status`, `$errorMessage`, `$connectedSince`, `$lastExitIP`) dengan
  `removeDuplicates()`. Angka trafik tidak lagi sampai ke SwiftUI; kartu
  Trafik diekstrak jadi `TrafficCard` dengan `@ObservedObject` sendiri.
  `SettingsView.cpuStatus` diekstrak jadi `CPUSummary` — sebelumnya `cpu`
  tidak di-relay DAN tidak diamati langsung, jadi teksnya basi.
- **Cache turunan tunggal** di `AppState`: `ensureDerived()` menghitung
  `filteredNodes` + `bestLatency` + `previewNodes` sekali di satu tempat,
  di-reset lewat SATU fungsi `invalidateDerived()`. `selectedNode` memakai
  indeks `[id: ProxyNode]`. `topByLatency` mengambil 5 teratas dengan
  penyisipan terstruktur, bukan `sorted().prefix(5)`.
- **`persist(only…)`** per-store. Toggle pengaturan tidak lagi menulis ulang
  `nodes.json`; slider CPU-share persist hanya di akhir drag
  (`onEditingChanged:`). `applyUIScale`/`applyCPUPolicy` dipisah ke
  `persistSettingsSideEffects()`.
- **`JSONStore.loadAsync`** — pemuatan store keluar dari main actor. Kegagalan
  decode kini dicatat ke `os_log` dan dipulihkan dari `.bak` (rotasi isi lama
  saat setiap write).
- **Timer `.common`** di `ConnectionManager` (statistik + watchdog),
  `CPUGovernorMonitor`, dan timer log `ConnectView`.
- **Formatter di-hoist**: `RelativeDate` (cache per locale),
  `TrafficCard.byteFormatter`, `CorePaths.singBox` (`static let`),
  `Theme.baseSize` (cache per text style), regex ANSI di `ConnectionLog`.
- **Parser**: regex `CountryInfer` dibangun sekali (sebelumnya ~90.000
  kompilasi per feed 30.000 node) dan loop Mandarin dilewati untuk nama ASCII;
  `chineseNames` diurutkan panjang-ke-pendek; `Base64Detector` satu lintasan
  byte (sebelumnya lima salinan penuh payload 10 MB); `ClashYAMLParser.scalar`
  tidak `lowercased()` untuk scalar panjang; `ServerSorter` memakai Schwartzian
  transform (tanpa `localizedCaseInsensitiveCompare` per perbandingan);
  `AutoParser` jatuh ke jalur share-link bila jalur Clash kosong;
  `SubscriptionCache.load(ttl:)` akhirnya dipakai (TTL 6 jam sebelumnya konstanta
  mati) dan I/O-nya dipindah ke `DispatchQueue` khusus.
- **Blocking I/O dari main actor**: `SingBoxConfigBuilder.validateDetailed`
  (pipe dibaca konkuren, timeout 10 dtk, mengembalikan diagnostik sebenarnya),
  `ConnectionManager.startAfterCleanup`, `tryLocalCore` (sekarang
  `startAsync`, bukan `start` yang `Thread.sleep` 2 detik),
  `ConnectionLog.reloadLog`, `MacSpoofClient` (baca pipe sebelum `waitUntilExit`).
- **`LocalCoreRunner`** mendrains stdout DAN stderr sejak spawn lewat task
  background. Sebelumnya stdout di-`Pipe()` tanpa pembaca: core yang menulis
  >64 KB ke stdout akan tersendat dan `finish()` menyatakan BERHASIL untuk core
  yang macet.
- **Race `checkCoreAlive`**: `attemptID` + `status` dicek ulang setelah setiap
  `await`, jadi tidak lagi menimpa `.disconnected` dengan `.error`.
- **`helperCoreStatus`** dapat arms waktu 3 detik dan penjaga resume
  thread-safe (double-resume `CheckedContinuation` adalah fatal error).
- **`MapPin.id`** jadi `String` deterministik (node id) dan `pins` disimpan di
  `@State` lewat `.task(id:)` — UUID baru tiap render membuat `MapPinView`
  dihancurkan/dibuat ulang dan animasi denyut restart dari nol.
- **Keamanan**: `ClientTrust.isTrustedClient` memverifikasi `SecCode` klien XPC
  terhadap designated requirement `identifier "com.freepn.app"` (Release; Debug
  melewati karena build lokal tidak punya anchor), plus batas jumlah koneksi.
  Log helper & core pindah dari `/tmp` ke `/var/log` dengan `O_NOFOLLOW`.
- **Lain-lain**: `SubscriptionService` mengecek `Task.isCancelled` per kandidat
  dan meng-parse lewat `Task.detached`; `GeoIPResolver` membatasi lebar DNS
  dengan `DispatchSemaphore(16)`; `AppStorage.directory` tidak lagi force-unwrap;
  `nearestCPUShare` jadi satu sumber kebenaran di `AppSettings`; filter protocol
  memakai `NodeProtocol.allCases` (sebelumnya 3 dari 5); sumber bawaan tidak
  lagi dibintang.

### Verifikasi
- Build Debug + Release + Helper: **BUILD SUCCEEDED**.
- Test **200/200 lulus** (172 lama + 28 regresi baru di `D61RegressionTests.swift`).
- `./scripts/check-localization.sh`: EN == ID.
- `ClientTrust` diuji langsung terhadap build nyata: FreePN.app **MATCH**,
  `/bin/ls`, `/Applications/Safari.app`, `/usr/bin/swiftc` semua **ditolak**.

---

## D62 — Dukungan `http`/`socks5` + pemisahan counter "tidak didukung", 12-Okt-2026

### Laporan
Kolom Keterangan di layar Sumber menunjukkan angka "tidak didukung" yang besar
(EbraSha 7, ermaozi 279, mahdibland Public 249, zhuhai 15) tanpa penjelasan
apa pun. User menanyakan kenapa sebagian feed ditolak.

### Akar masalah — ditelvividi dari cache feed asli user
Diperiksa langsung dari `~/Library/Application Support/FreePN/subcache`, dengan
meng replikasi `entries(in:)` + `parse` dari `ClashYAMLParser` persis seperti
kode aslinya. Angka di UI cocok persis dengan hitungan di kode:

| Sumber | UI | Sebenarnya |
|---|---|---|
| ermaozi | 279 | `http` 210 · `socks5` 3 · `anytls` 10 · `hysteria` 1 = **224 protokol**, sisanya **55 node korup** |
| mahdibland Public | 249 | `http` 188 · `ssr` 55 · `socks5` 6 = semua protokol |
| zhuhai | 15 | `http` 11 · `socks5` 4 = semua protokol |
| EbraSha | 7 | 7 node korup — TAPI ada **34 `ssr://` yang hilang tanpa dihitung** |

Tiga sebab:

1. **`http` dan `socks5` sebenarnya bisa dipakai.** `NodeProtocol` tidak
   punya case-nya, jadi `ClashYAMLParser.swift:31` langsung
   `unsupported += 1`. Padahal `sing-box check` (1.12.1, binary bundle)
   **menerima** keduanya sebagai outbound — sudah diuji langsung sebelum
   perubahan ini.
2. **`ssr://` hilang tanpa jejak.** Di `ShareLinkParser.swift:41` baris itu
   jatuh ke `else { continue }`: tidak diparse DAN tidak dihitung. Angka di UI
   jadi lebih kecil dari kenyataan (EbraSha: 34 `ssr` tidak masuk hitungan 7).
3. **Dua hal berbeda dijumlahkan jadi satu.** `AutoParser` menambahkan
   jumlah node yang dibuang `NodeDeduper.keepingUsable` (jaring D51 untuk
   payload korup) ke counter yang sama, lalu semuanya ditampilkan "tidak
   didukung". Untuk ermaozi, 55 dari 279 adalah node korup — bukan salah app.

### Perubahan

- **`NodeProtocol` + `.http` dan `.socks`** (total 7), dengan
  `fromClashType` menerima `http`, `socks`, `socks5`, dan `badgeTitle`
  "HTTP"/"SOCKS". Warna kapsul baru `Palette.protoPlain` yang netral —
  keduanya tanpa enkripsi transport, tidak boleh berwarna sekelas VLESS.
- **`ClashYAMLParser`**: `case .http, .socks` membaca `username`/`password`
  ke satu slot `credential` berformat `"user:pass"` (kosong = tanpa auth),
  lewat `plainProxyCredential`.
- **`ShareLinkParser`**: skema `socks5://` / `socks://` / `http://` jadi node
  (`parsePlainProxy`, mendukung IPv6 dan userinfo). Skema yang **diketahui
  sebagai node tapi belum didukung** — `ssr`, `tuic`, `anytls`, `wireguard`,
  `snell`, `mieru`, `ssh`, `hysteria`, `naive+https`, `juicity`, `brook`,
  `shadowtls` — sekarang **dihitung** sebagai `unsupported`. `http`/`https`
  di luar daftar itu karena dipakai juga untuk link web biasa di feed.
- **`SingBoxConfigBuilder`**: `outboundJSON` menangani `.http` dan `.socks`
  (`version: "5"` + `applyPlainProxyAuth`).
- **Pemisahan counter**: `AutoParser.Outcome` dapat field baru `unusable`
  (node korup) terpisah dari `unsupported` (protokol). `FetchOutcome` dan
  `VPNSubscriptionSource.unusableCount` ikut. Kolom Keterangan menampilkan
  keduanya: "N dipakai · M tidak didukung · K korup".
- **Test infrastructure**: `SingBoxValidationTests` tidak lagi memakai path
  absolut mesin developer + `try!` (yang membuat SELURUH test target crash
  kalau binary tidak ada). Sekarang `XCTSkip` + `CorePaths.singBox` + baca
  pipe sebelum `waitUntilExit`.

### Bug yang ketahuan saat menambah test
`sing-box check` **menolak** `tls` pada outbound `socks`
(`outbounds[0].tls: json: unknown field "tls"`), sementara menerimanya pada
outbound `http`. Karena `check` bersifat all-or-nothing, satu node socks5
dengan `tls: true` di feed akan menggagalkan verifikasi internet untuk
ratusan node lain yang sehat — kelas bug yang `acceptedByCore` harusnya
cegah. Builder sekarang tidak pernah menulis `tls` untuk outbound `socks`;
node SOCKS-over-TLS akan terbaca "mati" saat diuji, yang jauh lebih murah
daripada membuat seluruh sesi probe gagal.

### Verifikasi
- **Diukur terhadap feed asli user** lewat `RealFeedImpactTests` (baru):
  **422 node http/socks5 dipulihkan** — ermaozi 213, mahdibland Public 194,
  zhuhai 15. `unsupported` ermaozi turun 279 → 66, mahdibland 249 → 55,
  zhuhai 15 → 0, dan EbraSha naik 7 → 35 karena 34 `ssr://` sekarang terlihat.
- Config hasil parser divalidasi nyata dengan `sing-box check` untuk keempat
  kombinasi http/socks × dengan-tanpa-auth.
- Build Debug + Release + Helper universal: **BUILD SUCCEEDED**.
- Test **208/208 lulus**. Localization EN == ID.

---

## D63 — GitHub di menu Tentang, 12-Okt-2026

### Permintaan
Tautan GitHub `https://github.com/YandiDesign` di kartu Tentang, memakai
ikon GitHub.

### Keputusan
- **SVG dikonversi jadi `SwiftUI.Shape`**, bukan aset PNG dan bukan `NSImage`.
  `NSImage` tidak bisa merender SVG di app sandbox (WebKit tidak tersedia
  tanpa biaya tambahan), dan PNG buram di Retina untuk glyph yang bentuknya
  statis. `GitHubMark` (DesignSystem) menerjemahkan atribut `d` Font Awesome
  Free 7.3.1 (viewBox 640×640) ke tabel outline.
- **Outlinenya ditulis SEKALI** sebagai daftar `Segment` dalam koordinat
  viewBox; `path(in:)` memetakannya ke SwiftUI dan `sourceBounds` menghitung
  kotak batangnya dari tabel yang sama. Dua-duanya tidak mungkin melenceng,
  dan geometrinya bisa diuji tanpa merender apa pun — `SwiftUI.Path` tidak
  punya `boundingBox` dan tidak meng-conform ke `Sequence`, jadi pendekatan
  "hitung bbox dari path yang sudah dirender" tidak tersedia di sini.
- **Satu konstanta URL** (`AppConstants.projectURL`) supaya tautannya tidak
  ditulis ulang di beberapa tempat.
- **`Link`**, bukan `Button` + `NSWorkspace`: Safari jadi penangan default
  (menghormati browser pilihan user) dan Cmd-klik tetap bekerja.
- **Warna netral** untuk ikon mengikuti palet teks — bukan warna merek GitHub,
  supaya tidak bersaing dengan mint yang dipakai sebagai aksen app.
- Strings baru `about_github` / `about_github_note` di EN + ID.

### Verifikasi
- Path diuji identik dengan SVG: **162 koordinat, urutan dan nilai sama
  persis** (dibandingkan otomatis dengan parsing atribut `d`).
- `testGitHubMarkMatchesTheSourceGlyphGeometry` mengunci kotak batang ke
  64,64 + 512×500 (nilai asli Font Awesome) — satu kurva yang hilang atau
  salah tempat akan langsung menggeser angka itu.
- Build Debug + Release + Helper: **BUILD SUCCEEDED**.
- Test **211/211 lulus**. Localization EN == ID.

---

## D64 — Ikon node mati + perbaikan toolbar Server, 12-Okt-2026

### Permintaan
1. Ganti label teks "Sembunyikan yang mati" dengan ikon SVG yang diberikan
   user (`REDESAIN/Death Emoji Icon.svg`).
2. Menu Server tampilannya berantakan.

### Keputusan
- **`DeadNodeMark`** = `SwiftUI.Shape`, satu keluarga dengan `GitHubMark`.
  Atribut `d` SVG dikonversi **dari file sumber di repo**, bukan dari catatan
  atau ingatan. Ini bukan pedantry: subpath colokan ketiga di SVG itu
  relational dan Its urutannya berbeda — `m3.27,0` lalu **busur dulu**, baru
  garis. Salah baca urutannya membuat colokan kanan meleset ~1 unit.
- **Cincin ditulis sebagai satu pita tertutup sederhana** (lingkaran luar +
  lingkaran dalam terbalik, 144 titik), bukan dua subpath dengan winding
  berlawanan. Bentuk terakhir benar secara matematis tapi bergantung pada
  aturan winding fill, dan ia tidak cocok dengan `Shape.fill()` SwiftUI —
  hasilnya cincin terisi penuh. Pita tertutup tidak punya ketergantungan itu.
- **Busur dipecah jadi polyline (0,5 derajat), bukan `Path.addArc`.**
  Konversi endpoint-ke-sentro SVG harus dijalankan di ruang y-NAIK, sedangkan
  `addArc` memakai ruang y-BAWAH; membalik sumbu juga membalik flag `sweep`.
  Kalau `sweep` ikut dibalik, bahu colokan (semicircle) terangkat ke atas
 — persis yang terjadi. Karena poliline tidak punya konvensi sudut sama
  sekali, kelas bug ini dihapus, bukan ditutup.
- **Toolbar filter dipecah dua baris.** Chip protokol tumbuh dari 4 ke 8
  (ada `.http` dan `.socks`); satu baris tidak cukup lebar dan SwiftUI
  memampatkan toggle sampai teksnya pecah beberapa baris. Baris atas =
  pencarian + sumber + clear + toggle + jumlah; baris bawah = chip protokol.
- **Label toggle diganti ikon**, maknanya pindah ke `.help()` tooltip.

### Verifikasi
- `IconRenderTests` membandingkan render `ImageRenderer` (jalur render yang
  benar-benar dipakai app) dengan PNG hasil `rsvg-convert` dari SVG sumber.
  Diuji di 16, 32, 128, dan 512 px karena bentuk yang benar di 512 px masih
  bisa berantakan di 16 px — ukuran yang benar-benar dipakai di toolbar.
- Dua jebakan di harness itu sendiri yang harus ditulis ulang:
  - `Shape` tanpa `.fill(...)` dirender penuh warna default — hasilIoU diam-diam
    selalu nol.
  - `ImageRenderer` menghasilkan alfa transparan, dan `colorAt` membaca RGB
    *premultiplied*, jadi piksel kosong terbaca hitam. Setiap render
    diletakkan di atas `Color.white`.
- PNG referensi disimpan di `FreePNTests/Fixtures/` dan dicari lewat
  `#filePath`, **bukan** environment variable — kalau referensinya cuma ada di
  `/tmp`, testnya `skip` dan tidak pernah mengunci apa pun.
- Build Debug + Release + Helper: **BUILD SUCCEEDED**.
- Test **213/213 lulus**. Localization EN == ID.

---

## D65 — Saklar tipe ping: "server merespons" vs cek internet, 12-Okt-2026

### Permintaan
Tambahkan di menu Setting satu saklar untuk memilih tipe ping. Ping sekarang
memakai cek koneksi internet (D27); tambah mode **ping biasa** yang cukup tahu
server merespons. Setting ini harus berlaku untuk **Ping All** dan untuk
**ping klik kanan pada satu server**.

### Keputusan
- **`AppSettings.fastPing: Bool`, default `false`.** Default TIDAK diubah:
  hanya cek internet yang menangkap node dengan kredensial salah atau egress
  diblokir, itu penyebab paling sering user connect sukses lalu tidak bisa
  memakai apa pun (D27). Mode cepat adalah alat yang dipilih user, bukan
  perilaku bawaan.
- **`ServerPinger` (file baru) sepenuhnya terpisah dari `InternetProbe`**,
  bukan sekadar parameter tambahan. Mode cepat tidak menjalankan core
  sing-box sama sekali, jadi tidak ada sesi/outbound/tag yang perlu disiapkan.
  Menyatukannya sebagai parameter berarti `InternetProbe` harus bisa tetap
  hidup tanpa core — dan setiap state-nya jadi mungkin salah.
- **Dua jalur, satu map `ping`.** Keduanya menulis ke `AppState.ping` dan
  dibaca UI yang sama, jadi tidak ada state ketiga yang harus disinkronkan.
  `pingOne` dan `pingAll` adalah titik cabangnya, yang juga persis cakupan
  yang diminta user (klik kanan per server + Ping All).
- **TCP timeout = MATI, UDP timeout = HIDUP.** Ini aturan paling berisiko di
  fitur ini, jadi dipisah per protokol, bukan satu aturan untuk keduanya:
  - TCP: tidak ada handshake = tidak ada bukti hidup → `dead`.
  - UDP/Hysteria2: QUIC **tidak pernah menjawab paket acak**, jadi kalau
    timeout diartikan mati, hampir semua HY2 yang sehat akan ditandai mati.
    Dan `isDeadEnd` **menolak `connect()`** — user kehilangan sebagian besar
    HY2 tanpa jalan membukanya lagi. Timeout jadi `aliveUpperBound`.
- **Batas atas ditandai, bukan dikarang jadi RTT.** `.aliveUpperBound` menyimpan
  `PingResult.approximate = true`, dan `LatencyCell` menampilkan "≤ms".
  Menampilkan angka polosnya akan berdusta soal apa yang terukur; tidak
  menampilkan apa-apa juga salah karena informasinya memang ada.
- **`apply(_: ProbeVerdict)` tidak diubah.** Verdict jalur internet dijaga
  selalu `approximate == false`; penanda batas atas hanya mungkin lewat
  `apply(_: ServerPingOutcome)` yang terpisah. Kalau flag-nya ikut nyantol di
  jalur internet, UI akan menampilkan "≤" untuk hasil yang sebenarnya terukur.
- **Decoder eksplisit untuk `PingResult`.** Field `approximate` yang baru
  ditambah akan membuat `Codable` hasil sintesis GAGAL decode seluruh
  `ping` lama — riwayat ping user hilang diam-diam. `decodeIfPresent` +
  default menutup kelas bug itu (pola yang sama dengan `ProxyNode`/D61).
- **Kontrol diletakkan di kartu Langganan**, berdampingan `auto_sort` dan
  `hide_dead`, bukan di Performance: ini mengatur APA yang diukur ping, bukan
  berapa banyak workers. Governor tetap jalan di kedua mode — AIMD-nya
  bereaksi pada beban CPU nyata, dan ribuan handshake socket memang bisa
  membuat mesin panas walau tanpa kriptografi.

### Verifikasi
- `ServerPingerTests` — aturan keputusannya, bukan jaringan sungguhan
  (192.0.2.0/24 = TEST-NET-1, RFC 5737, tidak pernah dialokasikan):
  timeout UDP harus `aliveUpperBound`; timeout TCP harus `dead`; jalur TCP
  tidak boleh pernah mengembalikan batas atas; endpoint tak valid ditolak
  sekilas (< 1 dtk untuk 4 node) tanpa membakar timeout penuh tiap node korup.
- `FastPingResultTests` — `replied` bukan `approximate`, `aliveUpperBound` ya,
  dan **beralih mode menimpa** flag itu (node HY2 yang lalu diuji ulang via TCP
  tidak boleh terus menampilkan "≤").
- `PingResultLegacyDecodeTests` — `ping` lama tanpa `approximate` tetap
  terbaca; penandanya bertahan lewat encode/decode.
- `AppSettingsTests` — `settings.json` lama tanpa `fastPing` dapat default dan
  setting lain tidak ikut ter-reset; default app tetap cek internet.
- Test **228/228 lulus** (dari 213). Localization EN == ID. Build: **SUCCEEDED**.

---

## D66 — Sumber yatim: kolom Source & filter rusak, 12-Okt-2026

### Permintaan
1. Kolom Source di tabel Server menampilkan kode aneh (`EA5A840F`), bukan
   nama sumber.
2. Filter source tidak bekerja — memilih sumber tidak menghasilkan satu pun
   server.
3. Sumber baru terbaca "semua duplikat".

### Bukti (diperiksa langsung ke data user)
`nodes.json` punya **8** `sourceID` berbeda, `sources.json` punya **12**, dan
**irisannya kosong**. Jadi `sourceNames[id]` selalu miss → kolom jatuh ke
`id.prefix(8)`, dan `applyFilters` yang mencocokkan `$0.sourceID == source`
(byte-exact) tidak pernahFinding apa pun. "Semua duplikat" muncul karena
`resort` menghitung `keptCount` per ID sumber — dan nol node yang cocok.

### Akar masalah
**Bukan** hash yang berubah format, dan **bukan** ID yang terpotong. `sources`
diinisialisasi dengan `VPNSubscriptionSource.builtIn()` yang meng-mint
**UUID acak setiap kali dipanggil**, sementara `loadPersistedState()` membaca
`files` secara **async**.

`.onAppear` → `startAutoRefreshIfNeeded()` → `nodes.isEmpty` **selalu true di
titik itu** (hydrasi belum selesai) → `refreshAll()` mengambil snapshot
`sources` = daftar **bawaan** → node ditulis dengan UUID yang tidak pernah ada
di `sources.json` milik user. `isHydrating` ada dan berkomentar seolah ia
menunggu, tapi **tidak pernah dibaca satu pun di luar `loadPersistedState`
sendiri** — penjaga yang dijanjikan tidak pernah ada.

Bukti pendukung: 5 cache feed yatim dibuat dalam rentang **2 detik** (17:25:22
– 17:25:24) — tanda satu burst `refreshAll` atas 10 feed bawaan.

### Keputusan
- **`hydrationTask` + `waitForHydration()`**, dan `refreshAll` /
  `refreshSource` / `startAutoRefreshIfNeeded` **wajib** menunggunya. Ini
  memperbaiki AKAR masalah, bukan gejalanya.
- **`refreshAll` mengembalikan `source.id`, bukan indeks.** Sebelumnya `idx`
  ditulis ke `self.sources` yang dibaca ULANG di dalam loop; kalau daftar itu
  berubah selama await, angka/status ditulis ke sumber yang salah.
- **Perbaikan data lama lewat `OrphanNodeAdopter`, dari CACHE SAJA.**
  `parseCachedOnly` sengaja tidak menyentuh jaringan — perbaikan ini jalan saat
  app dibuka, mengunduh 12 feed hanya untuk memperbaiki label akan terasa
  seperti refresh yang tidak diminta.
- **Pencocokan di level GRUP, bukan per node.** Ini koreksi dari versi pertama
  saya, yang hanya menerima jawaban "tidak ambigu" per node dan **hanya
  memulihkan 46%** node user: feed gratis mengulang node yang sama di banyak
  aggregator, jadi hampir semua node individual ambigu. Yang menentukan adalah
  **seluruh grup** — 12.104 node yatim jelas milik EbraSha meski 9.000-an
  juga ada di feed lain.
- **Aturan: `share >= 0.5` DAN bukan seri.** Margin multiplicative sempat
  ditulis dan **ditolak test**: menolak kasus "10 dari 10" vs "9 dari 10" yang
  justru bukti kuat. Yang ditolak hanya kondisi seri benar-benar.
- **Grup < 2 node tidak dipetakan.** Satu kecocokan bisa kebetulan; salah
  label lebih buruk daripada tidak ada label.
- **Tidak ada cache = tidak ada perubahan.** Lebih baik gagal diam daripada
  merusak label yang sebelumnya benar.
- **Dropdown filter memakai node nyata, bukan `keptCount`/`nodeCount`.**
  Metadata itu bisa basi, dan dropdown yang menunjuk sumber tanpa node
  memberi tabel kosong — yang terlihat persis seperti filter rusak.
- **Deteksi URL duplikat saat menambah sumber** (normalisasi huruf besar,
  spasi, garis miring akhir). Tanpa itu, 3 entri untuk 1 feed = 3 cache,
  3 unduhan, dan "semua duplikat" untuk 2 di antaranya.

### Verifikasi
- Dijalankan terhadap data user yang rusak (15.073 node, 8 grup yatim):
  **15.073 yatim → 0**. Setiap grup jatuh ke pemilik yang masuk akal
  (EbraSha 12.104 → EbraSha, anaer 1.567 → anaer, ermaozi 583 → ermaozi,
  Au1rxx 670 → Au1rxx, openproxylist 87 → openproxylist).
- **Konfirmasi silang**: tiga grup (anaer, ermaozi, openproxylist) sudah
  diverifikasi lebih dulu secara terpisah lewat **feed cache byte-identik**
  sebelum voting diuji — hasilnya cocok persis. Vote bukan kebetulan.
- `OrphanSourceTests` (8) — termasuk regresi eksplisit untuk pendekatan
  per-node yang gagal, dan untuk aturan margin yang salah.
- `BuiltInSourceTests` (2) — feed bawaan tidak boleh punya URL kembar, dan
  node tidak boleh memakai ID daftar bawaan.
- `DuplicateSourceTests` (5) + `LiveSourceFilterTests` (3).
- Test **246/246 lulus** (dari 228). Localization EN == ID.
- Build Debug + Release: **BUILD SUCCEEDED**.

### Catatan yang sengaja TIDAK dikerjakan
- **ID `builtIn()` tidak dibuat stabil.** Daftar bawaan hanya boleh bertahan
  bila `sources.json` kosong, dan ID stabil berisiko bentrok dengan UUID milik
  user. Yang dijaga adalah kebalikannya — daftar bawaan tidak boleh pernah
  dipakai memberi ID pada node.
- **~0 node tersisa tidak dipetakan.** Tidak ada bukti kepemilikan; membiarkan
  yatim lebih jujur daripada menebak.

---

## D67 — Cincin tombol daya meleset ke bawah, 12-Okt-2026

### Permintaan
Animasi cincin tombol on/off kadang erred — ring dan glow-nya bergeser
kebawah (terlihat di tombol daya menu Sambung saat status Error).

### Akar masalah
`.blur()` dipasang **SESUDAH** `.frame()`:

```swift
Circle().fill(...).frame(width: 196, height: 196).blur(radius: 14)
```

SwiftUI menyisihkan 196x196 untuk tata letak, lalu blur melebar piksel
ter-render jadi **224x224** — 28pt di luar batas yang dipesan. Lapisan yang
meluber itu tidak selalu sejajar dengan lapisan lain di `ZStack`, jadi cincin
utama ikut bergeser bersamanya. "Kadang" karena yang meluber adalah lapisan
render, bukan geometri tata letak — dan hasil pergeserannya bergantung pada
jalur render yang terpilih.

### Keputusan
- **Blur sebelum frame, frame sesudahnya memuat bleed.** 168 + 2 x 14 = 196.
  Presisi, jadi ukurannya sama persis dengan sebelumnya (196) — hanya
  bleed-nya yang sekarang muat di dalam frame, bukan meluber.
- **`HaloIcon` (kartu MAC) punya bug yang sama persis** dan ikut diperbaiki:
  122 + 2 x 14 = 150. Dicari karena polanya identik, bukan karena dilaporkan.
- **Rotasi cincin dirombak.** Yang lama `rotationEffect(working ? 360 : 0)`
  dengan `.animation(_:repeatForever:value: working)`: saat `working` berubah
  ke `false`, animasi `.default` ikut memutar cincin **BALIK** dari 360° ke 0°
  — kilatan berputar di setiap perubahan status. Sekarang `phase` (@State)
  berputar terus-menerus dan **tidak bergantung pada status sama sekali**,
  jadi transisi status tidak pernah menyentuh rotasi.
- **Cincin tetap terlihat di semua status**, persis seperti sebelumnya.
  Percobaan pertama sempat memakai `.opacity(working ? 1 : 0)` yang
  menghilangkan cincin saat diam — itu regresi visual, dibatalkan. Gradient-nya
  simetris, jadi sudut diamnya tidak berarti apa pun dan tidak perlu
  disamarkan.

### Verifikasi
- `BlurFrameInvariantTests` (3) mengunci **urutan modifier** di source:
  frame sesudah blur harus >= frame sebelum blur + 2 x radius; blur tanpa
  frame pemuat = gagal.
- **Test ini diverifikasi dua arah.** Bug-nya dikembalikan sementara dan test
  WAJIB gagal — karena dua versi pertama test ini justru hijau saat bug aktif:
  - v1 gagal karena memindai **komentar** yang kebetulan memuat kata
    `.frame()`.
  - v2 gagal karena salah paham invariansnya: ia menolak `.frame()` sebelum
    `.blur()`, padahal itu justru wajib — itu yang memberi ukuran isinya.
  Yang benar: bleed 2 x radius harus muat di frame **sesudah** blur.
- Test **249/249 lulus** (dari 246). Localization EN == ID.
- Build Debug + Release: **BUILD SUCCEEDED**.

---

## D68 — Teks "Mencari lokasi" di toolbar Server, 12-Okt-2026

### Permintaan
Ada tulisan "mencari lokasiu2026" yang muncul sebentar lalu hilang di menu
Server. Hapus tulisannya — sisakan hanya lingkaran loading, tanpa teks.

### Akar masalah
`.filterBar` menampilkan `HStack { ProgressView; Text("resolving_countries") }`
saat `isEnrichingCountries == true`. Dua hal yang membuatnya membingungkan:

- **Teksnya membingungkan.** Pekerjaan ini berputar beberapa detik setiap app dibuka
  karena `startAutoRefreshIfNeeded` menjalankan `enrichCountries()` diam-diam
  untuk `nodes.json` yang belum punya negara. Label "Resolving locations…"
  muncul sebelum kolom Country terisi, jadi terlihat seperti error yang
  muncul-hilang sendiri — bukan progres yang sedang berjalan.
- **`lokasiu2026` itu bug render string.** Sumbernya
  `"resolving_countries" = "Mencari lokasi\u2026"` — `\u2026` di dalam file
  `.strings` TIDAK selalu di-decode sebagai ellipsis, dan karena string ini
  dipakai sebagai `LocalizedStringKey`, escape-nya kadang tampil literal.

### Keputusan
- **Teks dihapus, spinner dipertahankan.** Alasannya spinner bukan sekadar
  sisa: tanpa penanda apa pun, kolom Country kosong selama beberapa detik akan
  dibaca sebagai "kolom ini rusak", bukan "pekerjaan sedang jalan".
  Permintaan user dijaga persis — **hanya spinner** — dan penjelasannya dipindah
  ke `.help()`, jadi informasinya tetap ada tapi tidak berteriak sendiri.
- **Escape `\u2026` diganti karakter `…` sungguhan** di key yang baru. Ini
  menutup kelas bug yang sama untuk tooltip mana pun, bukan cuma yang ini.
- **Key lama dihapus**, tidak dibiarkan menggantung. Kunci yang tidak dipakai
  di `.strings` adalah technical debt: `LocalizationTests` hanya mengecek
  kecocokan EN/ID, bukan key yang benar-benar terpakai.

### Temuan tak terduga: test jaringan yang tidak bisa dipercaya
Sambil memverifikasi, `ServerPingerTests.testTCPTimeoutMeansDead` **gagal di
mesin ini**: ia memakai `192.0.2.1` (TEST-NET-1) dan mengharapkan diam, tapi
alamat itu dijawab dan hasilnya `replied(4)`.

Test itu tidak menguji kode — ia menguji **jaringan tempat test berjalan**.
`.blackhole` (yang benar-benar menahan paket) hanya ada di SDK macOS 14,
sedangkan proyek ini target macOS 13. Jadi aturan timeout dipisah menjadi
`ServerPinger.verdictOnTimeout(for:)`, fungsi murni tanpa jaringan, dan diuji
sebagai kebijakan. Jalur `ping` yang sebenarnya tetap diuji untuk hal yang
tidak bergantung pada lingkungan (endpoint tak valid, jalur TCP tidak pernah
mengembalikan batas atas).

Test **249/249 lulus, 3× berturut-turut** (dulu bisa gagal sesuai jaringan).
Localization EN == ID. Build Debug + Release: **SUCCEEDED**.

---

## D69 — Panel log "tak terbaca" padahal log-nya ada, 12-Okt-2026

### Permintaan
Panel log di menu Sambung berbunyi "(tak terbaca — instal ulang helper bila
berlanjut)" untuk Helper maupun Core, padahal koneksi sedang `connected`.

### Bukti (diperiksa langsung ke mesin user)
- `/var/log/freepn-helper.log` dan `/var/log/freepn-core-stderr.log`: **TIDAK ADA**.
- `/tmp/freepn-helper.log`: **32 KB, isinya nyata** (`accept connection pid=...`),
  dan masih diperbarui per detik.
- `strings /Library/PrivilegedHelperTools/com.freepn.helper` →
  `/tmp/freepn-helper.log`, bukan `/var/log/...`.

Jadi ini **bukan** masalah izin baca (file 0644, user bisa baca). App dan helper
sederhana menunjuk **file yang berbeda**, tanpa error apa pun.

### Akar masalah
D61 memindahkan log helper & core dari `/tmp` ke `/var/log` (mitigasi symlink LPE).
Helper di mesin user masih build **10-Okt**, sebelum D61. App diperbarui, helper
tidak — dan karena kedua sisi memakai path yang di-hardcode, tidak ada yang gagal
dengan keras: panel hanya diam-diam membaca file yang memang tidak ada.

### Keputusan
- **Helper dinaikkan ke 1.4** (`AppConstants.helperVersion`, satu sumber
  kebenaran; `HelperService` membacanya, bukan literal). Ini yang membuat
  mismatch TERLIHAT. Helper 1.3 yang sudah terpasang **tetap dianggap kompatibel**
  — hanya beda lokasi log, dan menolaknya akan memutus VPN pada semua user yang
  belum reinstall tanpa ada yang rusak.
- **`HealthCheck` tidak lagi `contains("1.3")`.** Dua jebakan nyata:
  `contains` menerima "1.30", dan `\b` saja TIDAK cukup karena `-` bukan
  karakter word sehingga "1.4-beta" tetap lolos. Pola akhirnya: token yang tidak
  didahului/diikuti digit maupun delimiter versi.
- **Fallback baca ke lokasi lama (`/tmp`).** Panel tidak lagi menampilkan
  "tak terbaca" untuk log yang benar-benar ada. Header menampilkan path yang
  **benar-benar dibaca**, jadi user (dan kita) langsung melihat helper perlu
  reinstall. Fallback ini HANYA untuk MEMBACA; menulis ke `/tmp` sebagai root
  tetap primitive LPE dan tidak dikembalikan.
- **File yang ada tapi KOSONG tetap dipakai.** Helper yang baru start menulis
  log kosong sesaat; mengembalikan "tak terbaca" di titik itu membuat user mulai
  reinstall helper yang sebenarnya sehat.

### Verifikasi
- Diuji terhadap kondisi NYATA di mesin ini: fallback membaca log helper 32 KB
  dan stderr core yang berisi `ERROR ... listen packet connection` — bukan
  "tak terbaca".
- `ConnectionLogFallbackTests` (5) + `HelperVersionTests` (7).
- **`HelperVersionTests.testHelperSourceUsesSharedConstant`** memindai source
  helper dan gagal kalau versinya jadi literal lagi — dua angka yang ditulis di
  dua tempat akan menyimpang diam-diam dan pemeriksaan kesehatan akan menilai
  build yang salah sebagai "OK".
- Satu test di versi pertama dihapus dengan alasan yang dicatat di komennya:
  ia mengoper path temp ke `snapshot()`, padahal `snapshot()` memakai konstanta
  legacy yang tidak bisa di-override — jadi ia tidak menguji apa pun yang
  terjadi pada user.
- Test **261/261 lulus** (dari 249). Build Debug + Release: **SUCCEEDED**.

### Yang harus dilakukan user
**Pasang ulang helper** (Settings → Periksa, atau tombol reinstall). Itu satu
langkah yang membuat log kembali ke `/var/log` dan menutup mismatch-nya.
Panel sudah bisa menampilkan log lama sampai saat itu.

---

## D70 — Sembunyikan bagian log Core saat kosong, 12-Okt-2026

### Permintaan
"Log bawah hapus saja, kosong" — bagian `===== Core sing-box =====` di panel log
selalu menampilkan `(kosong)`.

### Kenapa TIDAK dihapus permanen
Log core **tidak selalu kosong**. Ia SEPI saat core start bersih (sing-box tidak
menulis apa pun ke stderr kalau sehat), tapi begitu ada masalah isinya justru
yang paling menentukan. Dari mesin user sendiri, sebelum core start ulang pada
19:03, isinya:

```
ERROR[0086] [3690196449 0ms] connection: listen packet connection using tun...
```

Persis baris yang dibutuhkan saat connect gagal. Menghapus bagiannya secara
permanen berarti membuang satu-satunya bukti kenapa core gagal — dan user yang
baru mengalami masalah justru akan mendapat panel paling sunyi.

### Keputusan
- **Sembunyikan saat kosong, tampilkan begitu ada isi.** Permintaan user
  terpenuhi (bagian `(kosong)` hilang dari panel), sementara diagnostik tetap
  utuh. Ini bukan mengabaikan permintaan: panel yang bersih ADALAH hasil yang
  diminta; yang dipertahankan hanya kemampuan melihat masalah nanti.
- **`isBlank` menyatakan KOSONG**, dan itu mencakup tiga keadaan: string kosong,
  spasi saja, dan penanda localized `log_empty` / `log_unreadable`. Dua yang
  terakhir penting karena keduanya berasal dari `tail()` — kalau hanya
  `isEmpty` yang dicek, bagian core tetap muncul dengan isi "(kosong)", yaitu
  persi kondisi yang dikeluhkan.
- **Blok kosong diqus juga dihapus**, supaya tidak ada dua baris kosong yang
  menggantung di akhir panel saat core disembunyikan.

### Verifikasi
- `CoreSectionVisibilityTests` (4) — core kosong tidak muncul, core berisi
  muncul, core "tak terbaca" tidak muncul, dan `isBlank` mengena pada ketiga keadaan
  kosong itu.
- **Test diverifikasi dua arah**: kondisi `if true` (yaitu penghapusan
  permanen, pembacaan paling naif dari permintaan) membuat 2 dari 4 test gagal.
  Test yang hanya menguji kondisi scrambling tidak menangkap apa pun.
- Test **265/265 lulus** (dari 261). Localization EN == ID.
- Build Debug + Release: **BUILD SUCCEEDED**.

---

## D71 — Cincin tombol daya diam saat terputus, 12-Okt-2026

### Permintaan
"Saat terputus animasi tombol mati saja."

### Konteks (kenapa ini muncul sekarang, bukan dari awal)
D67 memperbaiki kilatan berputar dengan cara membuat `phase` **naik tanpa
henti**. Itu memang menghilangkan kilatan, tapi efek sampingnya: cincin berputar
terus-menerus di SEMUA status — termasuk saat terputus, yang justru status yang
paling sering dilihat user. Perbaikan D67 karena itu benar dalam menghilangkan kilatannya, tapi
salah dalam KAPAN animasi itu dijalankan.

### Keputusan
Dua aturan yang hanya benar BERSAMAAN, keduanya diimplementasikan:
- **Berputar hanya saat `connecting`/`disconnecting`** — dari lima status,
  tepat dua yang berputar. `disconnected`, `connected`, dan `error` diam.
  (`connected` diam karena cincinnya menyala solid, bukan berputar — sesuai
  dokumen komponen sejak awal.)
- **`phase` hanya NAIK, tidak pernah turun.** Inilah yang D67 awalnya jamin,
  dan itu yang membuat mematikan animasi aman: mematikan **berhenti** tanpa
  mengubah nilai. Karena tidak ada nilai yang perlu dikembalikan ke titik awal,
  kilatan berputar mustahil terjadi lagi.

Versi pertama mencoba memakai `.animation(nil)` yang berharap cukup untuk
menghentikan putaran; itu tidak cukup — animasi `repeatForever` yang sedang
berjalan sudah punya target, dan mematikan modifier tidak membatalkan gerakan
sedang berlangsung. Karena itu putaran sengaja di-toggle lewat state
`spinning`, dan `phase` tidak disentuh saat dimatikan.

Gradient cincin simetris, jadi sudut di mana pun cincin berhenti terlihat sama —
tidak ada "lonjakan" yang bisa dirasakan saat animasi dimatikan.

### Verifikasi
- `PowerRingSpinStateTests` (7): dua status berputar, tiga status diam, dan
  simulasi `setSpinning` persis seperti di view membuktikan `phase` monoton
  pada aliran status nyata (terputus → connect → terhubung → disconnect →
  terputus → connect).
- **Test diuji dua arah**, karena dua aturan ini punya mode kegagalan yang
  saling berlawanan dan keduanya mudah dikembalikan tanpa sengaja:
  - `shouldSpin -> true` (perilaku D67): **4 test gagal**.
  - `phase -= 360` saat dimatikan (perilaku D67 lama): **2 test gagal**.
  Kalau hanya satu arah diuji, perbaikan ini bisa "hijau" sambil salah — persis
  yang terjadi pada dua versi test saya sendiri di D67.
- Test **272/272 lulus** (dari 265). Localization EN == ID.
- Build Debug + Release: **BUILD SUCCEEDED**.

### Catatan jujur
Perubahan ini murni State SwiftUI; saya tidak bisa menjalankan app-nya di sini.
Logika status dan monotonic phase ter-cover test, tapi **nuansa visual** —
apakah cincin terlihat "diam" atau "macet" saat transisi — hanya bisa dinilai
dari GUI. Perlu sekali cek visual setelah update.

---

## D72 — Spinner diganti denyut terang-redup, 12-Okt-2026

### Permintaan
"Animasi spinning matikan saja, ganti animasi opacity, jadi terlihat seperti
terang redup."

### Konteks — kenapa ini adalah revisi ketiga, bukan pertama
Riwayat tombol daya menunjukkan pola yang sama berulang: setiap perbaikan
sebelumnya memperbaiki satu keluhan dan memunculkan yang lain.
- **D67a**: `rotationEffect(working ? 360 : 0)` → saat `working` jadi false,
  nilai turun 360° dan cincin terpuntir **balik**. Kilatan tiap status berubah.
- **D67b**: `phase` naik tanpa henti → kilatan hilang, tapi cincin berputar
  **terus-menerus di semua status** termasuk terputus.
- **D71**: spinner hanya saat `connecting`/`disconnecting` → benar, tapi
  rotasi tetap **tidak memberi informasi apa pun**; yang ditanyakan user adalah
  "apakah sedang connect".
- **D72 (sekarang)**: rotasi dihapus **total**.

### Keputusan
- **Tidak ada `rotationEffect` sama sekali.** Cincin hanya
  `.opacity()` + animasi. Karena tidak ada lagi sudut yang berubah, kilatan
 balik yang D67a perbaiki **tidak mungkin terjadi** — masalahnya dihapus dari
  akar, bukan ditutup dengan aturan tambahan.
- **`repeatForever(autoreverses: true)`** pada `.easeInOut(1.1)` memberi
  denyut bolak-balik dari satu perubahan `Bool`. Tanpa callback, tanpa timer.
  `autoreverses: true` inilah bedanya dengan versi D67 (`false` = satu arah).
- **Animasi `nil` saat tidak bekerja.** Kalau modifier animasi tetap terpasang,
  denyut bisa berhenti di tengah jalan dan meninggalkan cincin setengah redup
  saat app idle.
- **Opacity saat diam = PENUH (1.0), bukan redup.** Tombol terputus adalah
  tombol utama aplikasi; kalau ikut redup bersama denyut, ia kehilangan daya
  tariknya justru di saat paling dibutuhkan.
- **Lembah denyut 0.35, bukan 0.** Cukup redup untuk terbaca sebagai denyut,
  tidak cukup redup untuk membuat cincin hilang saat sedang connect.
- **State `phase`/`spinning` dihapus**, bukan dipensiunkan. Kode rotasi mati
  hanya menambah permukaan bug tanpa fungsi.

### Verifikasi
- `PowerRingPulseTests` (10, menggantikan `PowerRingSpinStateTests` D71):
  hanya dua dari lima status yang berdenyut; idle selalu 1.0; denyut punya dua
  ujung berbeda dan tidak terlalu redup; flip Bool benar-benar menghasilkan
  gerakan.
- **`testNoRotationCodeRemainsInSource`** memindai blok `PowerRing` dan gagal
  kalau `rotationEffect`, `autoreverses: false`, atau `@State phase` muncul lagi
  — dengan sengaja mengabaikan baris KOMENTAR, karena komentar sengaja menyebut
  riwayatnya.
 balik yang D67a perbaiki **tidak mungkin terjadi** — masalahnya dihapus dari
  tersebut gagal. Kalau hanya jalur hijau yang diuji, penjaga ini tidak
  menjalankan apa pun.
- Test **275/275 lulus** (dari 272). Localization EN == ID.
- Build Debug + Release: **BUILD SUCCEEDED**.

### Catatan jujur
Masih pure SwiftUI dan tidak bisa dijalankan di sini. Logika status + nilai
opacity ter-cover test, dan penjaga source mengunci penghapusan rotasi. Yang
tidak bisa dinilai tanpa GUI: apakah denyut 1.1 dtk terasa pas (terlalu cepat /
terlalu lambat), dan apakah 0.35 cukup terlihat untuk `connecting` yang lama.
Kedua angka itu mudah perlu disetel ulang setelah dicoba.

---

## D73 — "Total Traffic" reset tiap 2 detik, 12-Okt-2026

### Permintaan
Total Traffic di kartu Trafik aplikasi menjadi reset sendiri. Contoh yang diberikan:
download ~1 MB/detik, selesai, lalu diam — totalnya kembali ke nol berulang.

### Akar masalah
`/traffic` adalah websocket **STREAM**. `fetchStats()` membuka koneksi **BARU**
setiap 2 detik, membaca **SATU** pesan, lalu menutupnya
(`ConnectionManager.swift:559-565`). Artinya angka pada setiap pesan adalah
trafik **sejak koneksi itu dibuka** — delta ~1 detik terakhir, bukan total
kumulatif sejak core start.

`applySample` memperlakukannya sebagai kumulatif:

```swift
upBytes = up        // ← menimpa total dengan delta 1 detik terakhir
downBytes = down
```

Dua angka rusak karena satu kesalahan:
- **Total** hanya berisi trafik 1 detik terakhir → naik-turun, dan kembali ke 0
  begitu trafik berhenti. Persis gejala yang dilaporkan.
- **Laju** dihitung dari `up - upBytes`, yaitu selisih antara dua delta yang
  **tidak berkaitan** (`upBytes` sudah ditimpa sampel sebelumnya). Hasilnya
  sampah yang kebetulan terlihat masuk akal saat trafik stabil — itulah sebabnya
  laju tidak ikut dilaporkan sebagai rusak.

### Keputusan
- **`applySample` menerima DELTA secara eksplisit** (`upDelta:`/`downDelta:`).
  Nama parameternya yang berubah adalah bagian dari perbaikannya: versi lama
  `up:`/`down:` yang berarti kumulatif sudah lolos dari semua test, jadi
  memperjelas kontrak di tempat yang dipakai.
- **Total dijumlahkan** (`+=`), bukan ditimpa.
- **Laju = delta / interval.** Benar karena delta sudah embody "berapa banyak
  selama ~satu interval". Sampel pertama tetap tidak menghasilkan laju
  (`interval == 0` = belum tahu delta itu mencakup berapa lama; menebak jadi
  angka liar).
- **`upBytes`/`downBytes` ikut di-reset di `startStats`.** WAJIB setelah total
  dipindah ke app: sebelumnya total "kebetulan" ikut hilang bersama core yang
  baru, karena ia berasal dari nilai yang ditimpa. Kalau tidak di-reset, total
  sesi lalu bercampur dengan sesi ini.
- **Delta negatif di-clamp ke 0.** Secara fisika mustahil; data rusak dari core
  tidak boleh mengikis total atau menggambar sparkline ke bawah sumbu.

### Verifikasi
- **Regresi utama: `testTotalSurvivesIdlePeriods`** — 10 sampel × 1 MB, lalu 5
  sampel delta 0. Total harus tetap. Ini skenario yang persis dilaporkan.
- **Test diverifikasi dua arah**: perilaku lama (`upBytes = du`) dikembalikan
  sementara dan **6 test gagal** — termasuk ketiga test total. Test yang hanya
  hijau di kode benar tidak mengunci apa pun.
- Test lama yang menguji kontrak SALAH (angka kumulatif) ditulis ulang ke
  kontrak delta. Menyesuaikan kode tanpa menulis ulang testnya akan membuat test
  lama "hijau" karena menguji bug yang sama.
- Catatan: `applySample` tidak bisa diuji langsung terhadap core sungguhan di
  sini (proses core berjalan sebagai root, port tidak terjangkau dari shell
  user), jadi pemverifikasiannya lewat simulasi kontrak di test.
- Test **277/277 lulus** (dari 275). Localization EN == ID.
- Build Debug + Release: **BUILD SUCCEEDED**.

---

## D74 — Satuan laju trafik adaptif (KiB/s → MiB/s), 12-Okt-2026

### Permintaan
Satuan laju trafik dibuat adaptif: dari KiB/s ke MiB/s.

### Akar masalah
`TrafficCard.rate` hardcoded `"\(Int(bytesPerSecond / 1024)) KB/s"` — label
selalu KB apa pun besarnya, jadi unduh 8 MB/s tampil **"8192 KB/s"**. Bug ini
tidak pernah dilaporkan sebelum D73 karena sampai saat itu ANGKANYA sendiri
salah (laju dihitung dari selisih dua delta yang tidak berkaitan). Sekali
D73 memperbaikinya, masalah satuan ini langsung terlihat.

### Keputusan
- **Satuan biner: KiB/MiB/GiB/TiB/PiB/EiB (1024)**, bukan KB/MB (1000),
  supaya konsisten dengan `byteFormatter` `countStyle = .binary` yang dipakai
  untuk total tepat di bawahnya. Dua angka dalam satu kartu yang pakai basis
  berbeda akan saling bertentangan.
- **Tanpa desimal, batas atas 999.** Angka berubah tiap 2 detik; "12,3 MiB/s"
  yang lebarnya berganti-ganti membuat kolom ikut bergoyang. Batas 999 menjaga
  lebar label stabil (3 digit + satuan) di semua satuan.
- **Trafik di bawah 1 KiB/s tidak pernah tampil "0".** Download 300 byte/detik
  itu trafik, bukan ketiadaan trafik; "0 KiB/s" akan dibaca sebagai idle.
- **Nilai tidak valid → "0 KiB/s".** `NaN`/`.infinity`/negatif.

### Bug NYATA yang ditemukan sambil menulis test
Versi pertama tidak punya clamp tidak punya clamp, dan `Int(value)` **TRAP** kalau
nilainya di luar rentang `Int`. `rate(pow(1024, 20))` **mematikan proses** —
dan di app itu berarti jendela hilang, bukan sekadar salah tampil.

Ini ditemukan karena test memang memanggil rentang eksponen lebar. Verifikasi:
tanpa clamp, tiga test memicu `Restarting after unexpected exit, crash` di
XCTest — membuktikan trap-nya nyata, bukan teoritis.

Diperbaiki dengan clamp ke 999 sebelum konversi, dan daftar satuan diperpanjang
sampai EiB supaya nilai astronomis tertahan di satuan terakhir ("999 EiB/s")
alih-alih jadi "1048576 TiB/s".

### Test yang tidak hermetik (D75) — ditemukan saat test D74
`CoreSectionVisibilityTests` tiba-tiba gagal padahal tidak ada kode log yang
disentuh. Penyebabnya: test itu mengoper `helperPath`/`corePath` temp, TAPI
path LEGACY-nya konstanta hardcode. Jadi `snapshot()` jatuh ke
`/tmp/freepn-core-stderr.log` — yang **sedang berisi error core asli** di
mesin ini karena app sedang berjalan. Test gagal karena file nyata milik user.

`snapshot()` kini menerima `legacyHelperPath`/`legacyCorePath`, dan semua test
memakai tempdir sepenuhnya. Test yang bergantung file di luar tempdir bukan test
hermetik: hijau di laptop bersih, merah di mesin yang sedang dipakai.

### Verifikasi
- `TrafficRateUnitTests` (14): peralihan satuan, batas tepat di bawah 1 MiB,
  sub-KiB tidak jadi nol, `NaN`/inf/negatif aman, lebar label terbatas, basis
  biner konsisten dengan total, dan label ekstrem tidak crash.
- **Crash diverifikasi dua arah**: tanpa clamp, test memicu *unexpected exit*
  di XCTest. Dengan clamp, 292 test hijau.
- Sifat hermetiknya diverifikasi secara struktural (path di-inject), bukan dengan
  menghapus file log root — percobaan itu memang tidak bisa dilakukan tanpa
  sudo, dan justru itulah bukti bahwa testnya sebelumnya bergantung pada
  lingkungan.
- Test **292/292 lulus, 3× berturut-turut**. Localization EN == ID.
- Build Debug + Release: **SUCCEEDED**.

---

## D76 — Monitor trafik realtime: sumber 1 Hz, render 60 fps, 12-Okt-2026

### Permintaan
Sampling 100–250 ms, grafik kontinu tanpa "berhenti lalu melompat", interpolasi
visual + scrolling window halus, target 60 FPS, minimalkan CPU/alokasi/update
SwiftUI, pertahankan desain UI dan sumber data.

### TEMUAN PERTAMA — sampling 100–250 ms TIDAK BISA DICAPAI
Diverifikasi langsung ke core sungguhan (sing-box 1.12.1, bundle app), bukan
dari dokumentasi:

```
/traffic (websocket, koneksi sama, 12 pesan berurutan):
  msg 0  t=1.032   msg 1  t=2.031   delta=0.998
  msg 2  t=3.030   msg 3  t=4.031   delta=1.000   ... (semua 1.000)
```

**Tepat 1 Hz, keras, tanpa knob config.** Polling 4–10× lebih cepat tidak
menambah data — ia membaca angka yang sama lebih sering. Yang bisa dicapai:
**1 Hz akurat + interpolasi 60 fps.** Itu yang dikerjakan. Angka 100–250 ms
tidak direkayasa karena itu berarti mengarang data yang tidak pernah diukur.

Diverifikasi juga bahwa pesan itu **delta per interval**, bukan kumulatif:
saat 100 MB dialirkan lewat proxy, nilainya ikut naik-turun (28461 → 498240 →
2855520 → 5962588 → …) dan **tidak pernah terakumulasi**; 5.2 MB/dtk cocok
dengan throughput terukur 5.02 MB/dtk. Ini sekaligus mengonfirmasi D73.

### BUG AKURASI YANG LEBIH SERIUS DARI PERMOHONAN
Pola lama: timer 2 dtk → **connect** → tunggu ~1 dtk sampai pesan pertama →
baca **SATU** delta (yang mewakili 1 detik) → **close**. Jadi tiap siklus
~3 detik hanya menangkap **1 detik** trafik: total dan laju **kurang laporan
sekitar 50–65%**. Bug ini lama tersembunyi karena D73 membuat angkanya "terlihat
normal" padahal masih salah.

### Keputusan
- **SATU websocket hidup per sesi** (`runTrafficStream`), bukan
  connect-per-sampel. Socket permanen menangkap setiap delta yang memang ada,
  dan reconnect ditangani di dalam loop dengan backoff (0.5→5 dtk).
- **Laju = delta ÷ waktu aktual** antar pesan. Bila socket tersendat, interval
  membesar dan laju ikut turun — itu benar, karena byte itu memang tersebar
  selama interval itu.
- **`TrafficSeries`: circular buffer kapasitas tetap (128).** Array + `removeFirst`
  adalah O(n) dan menggeser seluruh buffer tiap sampel; dengan jendela
  bergeser tiap frame itu jadi alokasi berulang. Backing array dialokasi sekali
  di `init` dan tidak pernah tumbuh.
- **Riwayat TIDAK `@Published`.** Dulu `@Published var upHistory: [Double]` —
  tiap sampel (1 Hz) membatalkan seluruh view tree yang mengamatinya, termasuk
  peta dunia dan tabel server yang tidak menampilkan byte. Sekarang sparkline
  menggambar dirinya sendiri per frame lewat `TimelineView`, jadi perubahan
  isi tidak perlu disiarkan ke seluruh app.
- **Sumbu X berbasis WAKTU, bukan indeks.** Setiap sampel punya cap waktu;
  garis menggeser sendiri secara kontinu karena `now` maju setiap frame. Tidak
  ada yang perlu dianimasikan.
- **`.animation(_:value:)` DIHAPUS dari Sparkline.** Itu penyebab sebenarnya
  "berhenti lalu melompat": tiap sampel baru memulai animasi easeOut 1,4 dtk
  yang mengubah SELURUH path, lalu diam 0,6 dtk. Itu pola "mengaduk lalu
  berhenti", bukan gerak.
- **Ujung kanan DIPATOK dengan nilai terakhir.** Tanpa itu ujung garis mundur
  ~lebar-satu-sampel tiap detik lalu melompat maju saat sampel berikutnya
  mendarat. Segment datar < 1 detik ini jujur: di detik pecahan itu memang
  tidak ada data baru.
- **Ease-in 0,22 dtk** untuk sampel terbaru: blend dari **dua nilai nyata**
  (sebelum & sesudah), bukan tebakan. Menghilangkan "gunting" 1 Hz di ujung.
- **Interpolasi tidak mengekstrapolasi.** Sebelum sampel pertama dipakai nilai
  pertama; sesudah yang terakhir dipakai nilai terakhir. Grafik tidak boleh
  menunjukkan lonjakan yang tidak pernah terjadi.
- **Trafik nol tetap masuk riwayat** (sebagai laju 0) — kalau dilewati, ada
  celah di garis tepat saat trafik berhenti.
- **Reconnect TIDAK mereset total/riwayat** (core yang sama masih hidup);
  hanya sesi baru (`startStats`) yang mereset.
- **`Canvas` TIDAK dipakai.** Grafik ini memang sudah `Path`, bukan Swift
  Charts — hanya ±60 titik per frame, jauh di bawah ambang di mana Canvas
  memberi keuntungan. `Path` + `TimelineView` menjawab semua yang diminta
  tanpa menambah dependensi maupun kompleksitas.
### Verifikasi
- `TrafficSeriesTests` (9) + `SparklineGeometryTests` (11).
- **Test diuji dua arah, dan tiga di antaranya saling melengkapi:**
  - dihapus hold ujung kanan → **158 failure** (ujung garis tidak pernah di tepi).
  - x diganti berbasis INDEKS (perilaku lama: diam lalu lompat) →
    `testInteriorPointsScrollContinuously` **gagal**. Test ini ditulis karena
    test "no jump" saja punya titik buta: ujung kanan dipatok, jadi ia tidak
    pernah bergerak, dan grafik yang benar-benar DIAM pun akan lulus.
  - `testNoPointJumpsWhenNewSampleArrives` memakai sampel ekstrem (9 MB/s)
    tepat di tengah pengujian — momen paling rawan glitch.
- `RedesignLogicTests`: total bertahan saat idle, buffer menahan sampel
  terbaru, trafik nol tercatat, dan idle→traffic pulih bersih.
- Test **320/320 lulus** (dari 292). Localization EN == ID.
- Build Debug + Release: **SUCCEEDED**.

### Yang TIDAK bisa diverifikasi di sini
FPS nyata dan kehalusan visual hanya bisa dinilai di GUI. Yang terkunci lewat
test adalah **geometri**: ujung kanan selalu di tepi, tidak ada titik yang
melompat lebih dari ~1/15 detik dalam satu frame, dan titik interior benar-benar
bergerak tiap frame. Kalau di layar masih terasa ada "tarikan" saat sampel
baru datang, kandidat tuning-nya ada di dua angka: `settleIn` (0,22 dtk) dan
`window` (60 dtk).

---

## D77 — Grafik upload (biru) di kartu Trafik, 12-Okt-2026

### Permintaan
Tambahkan line graph untuk upload, warna biru.

### Keputusan
- **Satu grafik per arah, masing-masing DI BAWAH angkanya** — download (hijau
  `Palette.mint`) dan upload (biru `Palette.info`). Bukan dua grafik penuh
  yang ditumpuk.
  - Asosiasi jelas tanpa label tambahan: kurva tepat di bawah laju yang
    dijelaskannya.
  - Tinggi kartu hampir tidak bertambah — 42pt grafik penuh diganti 34pt
    setengah-lebar di dalam kolom yang sama.
  - Warna upload memakai `Palette.info`, persis warna tile dan ikon upload, jadi
    tidak ada warna baru yang harus dipelajari user.
- Grafik upload memakai **`upHistory`** (yang sejak D76 sudah terisi, tapi
  sebelumnya tidak pernah digambar sama sekali).

### Kenapa test-nya MEMINDAI SOURCE, bukan merender
Tertukar satu baris — grafik upload membaca `downHistory` — akan terlihat sangat
wajar: dua kurva hijau dan biru yang isinya salah. Kode tetap `compile`, UI tetap
rapi, dan tidak ada yang salah sampai ada yang membandingkan keduanya. Uji visual
mahal dan rapuh; yang harus dijaga adalah PASANGAN grafik ↔ seri ↔ warna, dan
itu — dan seluruh pasangan itu ada di teks source.

### Jebakan yang hampir lolos
Versi pertama test ini memakai anchor `public func bytes(` untuk batas bawah
blok `TrafficCard`. Anchor itu **tidak pernah ada** (method-nya `static`), jadi
seluruh test di file ke-**skip** dan terlihat hijau tanpa menguji apa pun.
Test yang skip sama dengan test yang tidak ada.

Perbaikan dua lapis:
- batas bawah dicari dari deklarasi top-level berikutnya;
- ditambah `testHelperActuallyFindsTheBody` yang memastikan helper-nya benar
  benar menemukan blok — supaya kegagalan helper itu terbaca, bukan diam-diam hijau.

Parser warna juga sempat gagal karena memecah dengan `,` lalu `Double()` per
bagian; dua bagian berlabel (`green:`, `blue:`) jadi `nil`. Diganti regex angka.

### Verifikasi
- `TrafficCardGraphPairingTests` (4).
- **Diuji dua arah**: grafik upload sengaja ditukar ke `downHistory` →
  **2 test gagal**.
- Test **324/324 lulus** (dari 320). Localization EN == ID.
- Build Debug + Release: **SUCCEEDED**.

### Catatan jujur
Penempatan grafik (34pt, `spacing: 8`) adalah penilaian visual dan hanya bisa
dinilai dari GUI. Kalau terasa terlalu pendek atau jaraknya kurang, dua angka itu
yang perlu diubah — logika dan warnanya sudah benar.

---

---

## D78 — Disatukan: satu grafik untuk download + upload, 12-Okt-2026

### Permintaan
"apakah bisa disatukan saja? jadi jangan dipisah seperti itu graph line nya"
— D77 sempat memisahkan upload dan download menjadi dua grafik setengah lebar.

### Keputusan
Kembali ke **SATU plot** yang menggambar kedua arah sekaligus:
- download = `downHistory`, garis hijau, **lengkap dengan isi gradien**
- upload = `upHistory`, garis biru, **garis saja, tanpa isi**

### Kenapa hanya satu yang diberi isi gradien
Dua gradient yang bertumpuk di area yang sama saling menutup — hasilnya
kabut, bukan grafik. Yang turun ke bawah adalah isian download; garis biru
diatas di area yang sudah terisi itu jauh lebih kontras, dan menumpuk di area
yang sama persis maksud dari digabung dalam satu panel.

### Keputusan paling penting: SKALA Y BERSAMA
Kedua garis memakai **satu sumbu** (puncak = max dari keduanya).

Alternatifnya ditolak secara sadar: menormalisasi tiap garis ke puncaknya
sendiri. Kalau begitu, upload yang 50x lebih kecil dari download akan
tergambar **setinggi** download — panelnya terlihat sangat meyakinkan,
padahal kedua kurva memakai skala berbeda dan sama sekali tidak bisa
dibandingkan. Grafik yang menipu dengan rapi adalah kegagalan yang lebih
buruk daripada grafik yang membosankan.

Konsekuensi yang jujur: saat browsing, garis biru akan menempel di dasar.
Itu memang kenyataannya. Kalau justru yang diinginkan adalah **melihat
bentuk** upload tanpa peduli perbandingan, skalanya harus dipisah — dan itu
berarti dua grafik lagi. Trade-off nyata, bukan gratis.

### Jebakan test yang muncul
`points()` sebelumnya mengembalikan `[CGPoint]`; versi gabungan mengembalikan
tuple. Kalau hanya mengganti tipe balik, seluruh test geometri lama langsung
gagal kompilasi. Jadi overload tunggal `points(_:now:size:)` dipertahankan
utuh agar test lama tetap bermakna — dan ada test yang menjaganya:
`testSingleSeriesOverloadStillNormalisesToItsOwnPeak`.

Overload ganda **sengaja tidak diberi default** untuk `secondary`: dengan
default, `points(s, now:size:)` jadi ambigu dan Swift menolaknya dengan pesan
yang tidak membantu.

### Satu asumsi saya yang ternyata salah
Test pertama saya mengira puncak harus memetakan ke y=0; gagal dengan y=3.36.
Ternyata `project` memang menyisakan **8% ruang kosong di atas** dengan
sengaja, supaya garis tertinggi tidak menempel di tepi. Kodenya benar, asumsi
test salah — jadi testnya yang ditulis ulang, bukan kodenya.

### Verifikasi
- `TrafficCardGraphPairingTests` (5) + `CombinedSparklineScaleTests` (4).
- **Mutasi diuji**: `peak: shared` diganti `peak: nil` di kedua cabang ->
  **2 test gagal**. Inilah cacat yang paling mungkin muncul tanpa disadari.
- Test **329/329 lulus** (dari 324). Localization EN == ID.
- Build Debug + Release: **SUCCEEDED**.

### Catatan jujur
Tinggi grafik 42pt dan proporsi isi-vs-garis hanya bisa dinilai dari GUI.

---

## D79 — Grafik "tidak stabil": skala Y dihitung ulang tiap frame, 12-Okt-2026

### Gejala
"bisa tapi tidak stabil" + tangkapan layar. Garis turun hampir rata dengan
satu puncak tajam, lalu kurvanya melompat.

### Penyebab: BUG di `project`, bukan di data
`points()` menghitung `series.peak(from: start)` dari jendela yang
**bergeser setiap frame**. Jendela 60 detik pada 1 Hz berarti begitu satu
sampel lama keluar dari layar, puncaknya berubah mendadak — dan karena
seluruh titik dihitung ulang terhadap puncak itu, **SELURUH garis melompat
vertikal dalam satu frame**.

Jadi grafiknya tidak salah data. Yang salah adalah skalanya ikut berdenyut
setiap detik. Selama satu lonjakan masih berada di jendela, grafik juga
terlalu kecil sehingga semua yang lain menempel di dasar.

### Perbaikan: peak-hold (`TrafficYScale`)
- **Attack seketika**: nilai yang lebih tinggi langsung dipakai, supaya
  lonjakan baru tidak terlambat terlihat.
- **Release pelan**: half-life 5 detik. Inilah yang menghilangkan lompatan —
  skala tidak pernah jatuh mendadak saat sampel puncak keluar dari jendela.
- Dilepas berdasarkan **Waktu**, bukan jumlah frame. Kalau per frame,
  perilakunya berbeda di monitor 60 Hz dan 120 Hz.

### Bug kedua yang membuat perbaikan pertama tak mungkin berhasil
`project` menulis `max(forcedPeak, series.peak(...))`. Begitu `TrafficYScale`
mulai melepas skala ke bawah, nilai mentah di baris itu **menyalakannya lagi
setiap frame**. Redaman yang sudah benar pun jadi tidak ada efeknya.
`forcedPeak` sekarang dipakai apa adanya.

### Diperbaiki: jepit `dt` max 1 detik
Kalau tab sempat tidak aktif lalu kembali, `dt` bisa jauh lebih besar dan
seluruh pelepasan terjadi sekaligus — terasa seperti glitch. Dijepit 1 detik.

### Test: tiga kerangka pengukuran yang salah sebelum berhasil
Pengukuran "lompatan" versi pertama salah tiga kali berturut-turut, dan
semuanya menghasilkan test hijau yang tidak menguji apa pun:

1. **Bandingkan titik per INDEKS.** Jendela bergeser, jumlah titik berubah,
   jadi indeks ke-N menunjuk sampel berbeda antar frame. Ukurannya jadi
   pergeseran horizontal. Akibatnya dua skenario memberi angka **persis sama
   (38.157px)** — tanda jelas pengukurannya salah, bukan kebetulan.
2. **Rentang observasi tidak memuat peristiwa yang diuji.** Saya
   mengasumsikan jendela 30 detik; `Sparkline.window` sebenarnya **60**,
   sehingga lonjakan di detik 10 keluar dari jendela sekitar detik 70 —
   observasi 12..32 tidak pernah sampai ke sana.
3. **Pencarian titik bisa kena titik yang salah** sebelum sampel target ada.

Akhirnya diukur dengan cara yang benar: satu sampel dengan **waktu tetap**,
posisi vertikanya dilacak antar frame. Hasilnya:

| tanpa peredam | dengan peak-hold |
|---|---|
| lompatan **38.45px** dalam satu frame | **0.003px** |

### Verifikasi
- 10 test baru (`TrafficYScaleStabilityTests`, `SparklineScaleStabilityOverTimeTests`).
- **Mutasi diuji**: `release` diubah jadi instan -> **4 test gagal**.
- Test **339/339 lulus** (dari 329). Localization EN == ID.
- Build Debug + Release: **SUCCEEDED**.

### Catatan jujur
Satu puncak besar masih bakal compressing sisa kurva selama +-30 detik.
Peak-hold membuat **lompatan** hilang, tapi tidak membuat puncak itu hilang.
Kalau masih terasa "tidak stabil", kemungkinan besar yangyang dikehendaki
adalah mengabaikan puncak sesaat (misal pakai persentil, bukan max) — itu
perubahan kebijakan tampilan, bukan pembetulan, jadi perlu keputusan.

---

## D80 — Sumbu Y logaritma: burst speed test meratakan seluruh grafik, 12-Okt-2026

### Gejala
"saya tes speed test, awal curve normal, setelah beberapa detik curve jadi
error". Tangkapan layar: hampir seluruh garis datar di dasar dengan satu
puncak tajam di kanan.

### Diagnosis — dibuktikan dengan test SEBELUM diperbaiki
Disimulasikan persis: burst 100 MiB/s di detik ke-3, lalu trafik normal
8 KiB/s. Di detik ke-24, **trafik aktif hanya memakai 0.003px dari 42px** —
0,007% tinggi plot. Gejalanya terkonfirmasi reproducible, bukan perkiraan mata.

### Akar masalah, dan kenapa solusinya BUKAN "perbaiki easing"
D79 membuat skala halus, tapi dua hal lain masih salah:

1. **Skala diambil dari jendela yang sama dengan gambar (60 detik).** Satu
   burst menahan skala sampai burst itu keluar dari jendela — 60 detik.
2. **Pelepasan eksponensial di ruang LINEAR.** Turun dari 100 MiB ke 8 KiB
   butuh **~28 half-life**. Dengan half-life 2 detik itu 56 detik; dengan 5
   detik lebih dari 2 menit. Half-life yang masuk akal pun tidak bisa menutup
   rentang itu.

Percobaan pertama (perpendek `scaleWindow` ke 12 detik + half-life 2 detik)
**tidak memperbaiki apa pun**: 0.048px, masih gepeng. Itu bukti bahwa
masalahnya bukan konfigurasi, tapiRUANG ANGKA-nya.

### Keputusan: sumbu Y logaritma (3 dekade)
Trafik nyata melintasi **4 dekade** — idle ~8 KiB/s sampai burst ~100 MiB/s.
Tidak ada sumbu linear yang bisa menampilkannya; begitu satu burst ada,
seluruh trafik normal berikutnya *harus* tergambar gepeng di dasar.

Dengan log, posisi antar dekade seragam: jarak dari burst ke trafik normal
hanya ~4 "langkah", jadi pelepasan halus menutupnya dalam hitungan detik.

Konsekuensi yang perlu jujur disebut:
- Bentuk kurva **tidak** lagi proporsional-linear. Garis datar bukan berarti
  "tidak ada trafik", tapi "trafikya tetap di rentang bawah yang sama".
- `TrafficYScale` sekarang menyimpan `log10(peak)`. Half-life berarti
  **separuh dari log(peak)** meluruh, bukan separuh dari peak.

### Perbaikan pendukung
- `scaleWindow` 12 detik, terpisah dari `window` 60 detik. Gambar tetap
  panjang (bentuk kurva enak dibaca), skala cepat mengikuti kondisi terbaru.
- Nilai **di bawah** dasar dijepit ke dasar, bukan diekstrapolasi. Menampilkan
  bentuk yang tidak ada lebih menipu daripada menamparkannya datar.
- `.clipped()` — dengan log, nilai sesaat bisa berada di atas puncak plot
  selagi peak-hold menyusul; tanpa ini garis bocor keluar kotak dan menimpa
  kartu.

### Test yang harus ditulis ulang, dan alasannya
Enam test gagal setelah perubahan — **semua karena mengasumsikan sumbu
linear**, bukan karena kodenya salah. Kontrak yang berubah memang harus
diperbarui:

- `testReleaseFollowsHalfLife` (linear) -> `...InLogSpace`.
- `testResetClearsScale`: `peak` setelah reset adalah `10^0 = 1`, bukan 0.
- `testForcedPeakIsUsedVerbatim`: nilai di atas peak sekarang dijepit ke
  puncak plot, bukan digambar keluar kotak.
- `testBothSeriesUseTheSameVerticalScale` → `testBothSeriesShareTheSameLogMapping`.

Test D79 (`SparklineScaleStabilityOverTimeTests`) sempat **lolos diam-diam**
setelah `scaleWindow` diperkecil: observasinya masih 60..80 detik, padahal
peristiwa yang diuji sekarang terjadi di detik ~17. Keduanya mengukur 0.0px.
Rentang observasi dipindahkan ke 14..30.

### Verifikasi
- `SpeedTestTransientDoesNotFlattenGraphTests` — reproduksi-gejala, gagal
  sebelum fix (0.003px), lulus sesudah (0.048px -> <<12.6px).
- Mutasi diuji dua kali: `peak` paksa diabaikan -> stability test gagal;
  `release` jadi instan -> 4 test gagal.
- Test **342/342 lulus**. Localization EN == ID.
- Build Debug + Release: **SUCCEEDED**.

### Catatan jujur
Kandidat test yang saya buat sengaja **tidak** mengulang
`renderedHeight`: Test ini membangun ulang seluruh riwayat follower tiap frame
yang diperiksa, jadi hanya sah untuk waktu yang dipanggil — lambat, tapi
cukup untuk membuktikan diagnosis sebelum kodenya disentuh.

---

---

## D81 — Tepi kiri grafik hilang per detik, 12-Okt-2026

### Gejala
"line graph bagian belakang itu hilangnya tidak smooth, padahal yang depan
itu line nya muncul nya smooth, yang belakang itu seperti hilang per detik".

Sangat tidak simetris sebagai laporan: ujung KANAN mulus, ujung KIRI melompat sekali per
detik. Keduanya digambar oleh kode yang sama, jadi simetri itu sendiri
menunjuk penyebab: bukan animasi, tapi cara memilih titik yang digambar.

### Penyebab
`project` memang mengambil satu sampel sebelum jendela — niatnya supaya
kurva tidak terpotong di tepi kiri. Tapi sampel itu **langsung dibuang lagi**
oleh `guard age < window else { continue }` di baris berikutnya.

Akibatnya jalur yang digambar TIDAK PERNAH mencapai x = 0. Setiap titik
paling kiri berada pada x = (sisa waktu sampai keluar dari jendela), yaitu
antara 0 dan satu spasi sampel (~5px di jendela 60 detik). Celah di tepi
kiri itu lebarnya naik-turun 0..5px dan **kembar sekali per detik** — tepat
"hilang per detik". Ujung kanan tidak terpengaruh karena di sana memang
selalu ada sampel baru yang menempel di tepi.

### Perbaikan
- Satu sampel PERTAMA boleh berada sedikit di luar jendela, dengan x-nya
  negatif, lalu dipotong `.clipped()`. Jalur sekarang selalu menutup x = 0.
- Hanya satu sampel, dan dibatasi `edgeSlack = 10% jendela`. Kalau jeda
  datanya besar (lama idle lalu tersambung lagi), sampel lama bisa jauh
  lebih tua; menjahitnya akan menggambar garis panjang yang tidak pernah
  terjadi. Batas ini mencegah itu, dan ada test-nya.
- `lastX` diinisialisasi `-infinity`, bukan `-1` — kalau tidak, titik
  negatif justru terbuang oleh guard `x > lastX`.

### Bug logika di percobaan pertama
`guard i > start, age < window + edgeSlack else { break }` — ini **terbalik**.
Untuk `i == start` (sampel tepi yang justru mau diizinkan), `i > start` false
sehingga langsung `break` dan jalur jadi kosong. Diganti jadi
`if i > start || age >= window + edgeSlack { break }`.

### Test yang HIJAU TANPA MENGUJI APA PUN — untuk kedua kalinya
Mutasi "kembalikan `break` sebelum menggambar apa pun" **LULUS** di kedua
test D81. Sebabnya keduanya `continue`/`if let` saat titik tidak ada:
- `testPathAlwaysReachesTheLeftEdge` memakai `guard let first = pts.first
  else { continue }` -> jalur kosong = "lolos".
- `testLeftEdgeValueDoesNotStepOncePerSecond` tidak pernah punya `prev`,
  jadi `worst` tetap 0 -> "lolos".

Jadi "tidak ada data" dan "data-nya salah" menghasilkan hijau yang sama.
Diperbaiki: jalur kosong kini `XCTFail`, dan jumlah frame yang benar-benar
terukur harus > 2000. Pola ini sudah berulang beberapa kali dalam D77-D81 —
test yang bisa "lolos karena tidak bisa menghitung" bukan test.

### Verifikasi
- `SparklineLeftEdgeContinuityTests` (2): jalur menutup tepi kiri, dan nilai
  di x = 0 bergerak < 1px antar frame. Gagal sebelum fix (titik paling kiri
  di x=5), lulus sesudah.
- `SparklineGapDoesNotDrawFalseLineTests` (2): jeda 100 detik tidak
  menghasilkan garis panjang yang menyesatkan; data rapat tetap menutup tepi.
- Mutasi diuji 2x: (1) buang sampel tepi -> 2 test gagal; (2) buang
  `edgeSlack` -> 1 test gagal.
- Test **346/346 lulus**. Localization EN == ID.
- Build Debug + Release: **SUCCEEDED**.

### Catatan jujur
`.clipped()` yang dipakai di sini adalah downgrade dari rencana "pakai
Canvas kalau perlu". Uzahnya justru precipitated oleh D80 (nilai bisa
sembul ke atas kotak), dan sekarang dipakai lagi untuk memotong tepi kiri.---

## D82 — Tombol Sambung & Quick Connect meloncat saat status berubah, 12-Okt-2026

### Gejala
"saat saya klik sambung atau putus, di tombol bawah (yang ada tulisannya)
bukan logo power, saat diklik posisi tidak fix, kadang naik turun".

### Penyebab: reflow, BUKAN animasi
Bagian yang isinya berubah-ubah menurut status berada **DI ATAS** tombol:

```
PowerRing
statusText            <- panjang tiap status berbeda
statusDetail          <- panjang tiap status BERBEDA, bisa membungkus
if .connected {       <- <- INI: blok bersyarat
    timer (durasi)
    IP keluar
}
[ Tombol Sambung/Putus ]     <- terdorong ke bawah saat blok muncul
[ Quick Connect ]
```

Setiap sambung berhasil, blok `.connected` muncul dan menambah tinggi **di
atas** tombol, sehingga tombol melorot ke bawah. Setiap putus, blok itu
hilang dan tombol naik lagi. Itulah "naik turun"-nya.

Sebab kedua: `statusDetail` berbeda panjang per status —
"Your internet is not protected" / "Setting up the tunnel…" / "Your traffic
goes through the VPN". Di lebar kartu yang sempit, yang panjang membungkus ke
dua baris dan yang pendek tidak, jadi tinggi berubah lagi.

`PrimaryButtonStyle` memang punya `.scaleEffect(0.98)` saat ditekan, tapi itu
tidak menggeser tata letak — bukan penyebabnya.

### Perbaikan: tinggi terkunci
Blok `.connected` dijadikan view `connectedInfo` yang **ruangnya selalu ada**;
isinya boleh hilang, luarnya tidak. Ditambah:
- `statusText` → `.lineLimit(1)` + tinggi tetap
- `statusDetail` → `.lineLimit(2)` + tinggi tetap

Semua tinggi dihitung dari font yang dipakai (`statusTitleHeight` 24,
`statusDetailHeight` 32, `connectedInfoHeight` 35) dan diberi komentar
asalnya, karena angka tanpa asal akan terasa arbitrer.

Konsekuensi yang harus jujur disebut: saat tidak terhubung, kini ada ruang
kosong ~35pt di bawah status. Itu harga dari tombol yang diam — dipilih
sengaja karena itu yang diminta.

### Test yang hijau tanpa menguji apa pun — untuk KETIGA kalinya
`testLockedHeightsAreDeclaredInVisualOrder` awalnya hanya mengecek konstanta
tinggi **ada**. Mutasi yang menghapus `.frame(height: Self.statusDetailHeight)`
dari call site — perubahan yang justru mengembalikan bug aslinya — tetap
**LULUS**. Deklarasi bukan tata letak; call site-nya yang menentukan.

Ditambah `testLockedHeightsAreActuallyApplied` yang memeriksa `.frame(height:)`
benar-benar terpasang di `powerCard` dan di `connectedInfo`.

Pola "lolos karena tidak bisa mengukur" ini sudah muncul di D77, D81, dan kini
D82. Tiga kali berturut-turut adalah pola, bukan kebetulan: test sumber harus
membaca **call site**, bukan hanya keberadaan simbol.

### Verifikasi
- `ConnectViewLayoutStabilityTests` (5), file BARU dan terdaftar di pbxproj
  (dicek: `plutil -lint` OK, 3 entri, dan test-nya benar-benar jalan).
- Mutasi diuji 3x, semuanya tertangkap:
  1. blok `if status == .connected` dikembalikan -> 1 test gagal;
  2. `.frame(height:)` dibuang dari detail -> 1 test gagal;
  3. `.frame(height:)` dibuang dari connectedInfo -> 1 test gagal.
- Test **351/351 lulus** (dari 346). Localization EN == ID.
- Build Debug + Release: **SUCCEEDED**.

### Catatan jujur
Tinggi terkunci dipilih dari perkiraan font, bukan dari pengukuran nyata.
Kalau nanti teks status jadi lebih panjang (mis. Ditambah bahasa ketiga),
`statusDetailHeight` harus ikut dinaikkan — kalau tidak, teks terpotong.
Pengecekan yang berguna nanti adalah(sizeof) hilang: user tidak bisa
menilai ini tanpa menjalankan app.---

## D83 — Menu `…` pakai panel sendiri; tinggi terkunci ikut skala UI, 12-Okt-2026

### Permintaan
"kanan atas ada menu, tapi saat saya klik hanya menu kecil bawaan menu mac,
coba desain dengan gaya yang lebih sesuai dan lebih besar"

### Penyebab menu terlihat kecil dan asing
`Menu { } label: { }` + `.menuStyle(.borderlessButton)`. Di macOS, SwiftUI
me-nyawakakan **NSMenu** apa adanya — `menuStyle` cuma mengubah pemicunya,
isi menunya tetap milik sistem: tinggi baris ~22pt, system font, warna terang.
Di aplikasi dark navy seperti ini, hasilnya terlihat dipinjam.

### Perbaikan
Panel digambar sendiri dari komponen yang sama dengan kartu lain:
- lebar **300pt** (NSMenu ~180pt), tinggi baris **46pt** (NSMenu ~22pt)
- ikon dalam kotak rounded beraksen warna + judul + keterangan
- dua kelompok: "Tindakan" dan "Pindah ke"
- hover STATE (sort of native menu punya, dan itu yang bikin transplantasinya
  terasa pas — bukan sekadar daftar tombol)
- tombol pemicunya ikut berubah: bulatan mint + latar penuh saat terbuka

`.popover` dipakai, bukan `.overlay` buatan sendiri, karena sudah memberi
perilaku yang mahal ditulis ulang: tutup saat klik luar, tutup saat Esc, dan
posisi yang mengikuti tepi jendela.

Semua aksi lama dipertahankan persis, termasuk `pingAll` yang nonaktif saat
belum ada server.

---

## D83b — Bug yang saya bawa sendiri: tinggi terkunci TIDAK ikut skala UI

Tangkapan layar D83 memperlihatkan "Internet Anda tidak terlindu..." —
**teks terpotong**. Ini regresi dari D82.

D82 mengunci tinggi dengan literal: 24 / 32 / 35. Tapi `Theme.uiScale` bisa
diubah user lewat Pengaturan. Di 125%, satu baris callout sudah lebih tinggi
dari 32pt, jadi teks detail dipangkas oleh `.lineLimit(2)` + frame 32pt.

Jadi benar dalam pemakaian biasa, salah saat skala bukan 100%. Dan user yang melaporkannya
justru yang memakai Bahasa Indonesia — teksnya lebih panjang dari terjemahan
Inggris, jadi lebih lebih dulu terpotong.

Diperbaiki: tinggi diturunkan dari `Theme.pointSize(.callout)` dan
`Theme.uiScale`, jadi ikut diskalakan. Faktor 1.3 = tinggi baris tipikal.

Test-nya sekarang **numerik**, bukan pindai source: `Theme.uiScale` bisa
langsung diset di dalam test dan tinggi yang dihasilkan dibandingkan.

### Test helper yang terlalu longgar — muncul lagi
`slice()` mencari baris ber-indentasi 0 sebagai batas blok. Tapi anggota
struct ber-indentasi 4 spasi, jadi **tidak pernah cocok** dan potongannya
melaju sampai akhir file (1094 baris!).

Akibatnya `assertFalse(body.contains("Menu {"))` tersandung `.contextMenu {`
di bagian file yang lain — test gagal karena alasan yang salah, dan kalau
stavanya kebetulan lolos, itu hijau karena salah alasan juga.

Dua sebab, dua perbaikan:
1. batas blok harus sadar indentasi (cari anggota struct berikutnya pada
   indentasi yang sama);
2. `range.lowerBound` menunjuk awal **frasa**, bukan awal baris, jadi
   indentasi `lines[0]` hilang dan `base` jadi 0. Harus mundur ke `\n`.

Helper yang sama bermasalah juga ada di `ConnectViewLayoutStabilityTests`
dan sudah diperbaiki di sana juga.

### Pola "hijau karena salah alasan" sudah muncul 4x
D77 (anchor yang tak pernah ada → semua test skip), D81 (jalur kosong →
`continue`), D82 (konstanta ada tapi call site-nya tidak), D83 (blok yang
dipotong sampai akhir file). Empat kali berturut-turut sudah jadi pola:
test sumber yang hanya memeriksa **kehadiran simbol** tidak ada nilainya sebagai bukti.
Yang dihitung adalah call site-nya, dan batas bloknya harus benar.

### Verifikasi
- `OverflowMenuStylingTests` (9), file baru terdaftar di pbxproj.
- `ConnectViewLayoutStabilityTests` (7), diperluas dengan uji skala numerik.
- Mutasi diuji:
  1. tinggi dikembalikan ke literal -> 2 test gagal;
  2. tinggi baris 46 -> 22pt -> 1 test gagal;
  3. `disabled: state.nodes.isEmpty` -> `false` -> 1 test gagal;
  4. `.popover(isPresented:)` dihapus -> build GAGAL (perlindungan compile-time).
- Test **362/362 lulus** (dari 351). Localization EN == ID.
- Build Debug + Release: **SUCCEEDED**.

### Catatan jujur
`.popover` di macOS memakai NSPopover, jadi ia masih punya **panah kecil**
menunjuk ke tombol. Panah itu tidak bisa disembunyikan dari SwiftUI di
macOS 13. Kalau tanpa panah diminta, jalurTERNATIVANYA adalah `.overlay`
 buatan sendiri — tapi itu berarti menulis ulang penanganan klik-dari-luar
 dan Esc, dan itu bukan sesuatu yang bisa dipastikan benar tanpa pengujian
 di GUI.---

## D84 — Lisensi MIT + kewajiban atribusi GitHub, 12-Okt-2026

### Permintaan
"di Pengaturan, Tentang tambahkan lisensi app ini set ke MIT dan wajib
atribusi ke GitHub saya"

### Kondisi sebelumnya
Kartu Tentang hanya punya: versi, tautan GitHub, dan "Third-party licenses".
**Lisensi FreePN sendiri tidak disebut sama sekali.**

Ini masalah, bukan sekadar kekurangan tampilan. MIT mewajibkan:
"The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software." Kalau satu-satunya
mention lisensi di app adalah sheet yang berisi DAFTAR DEPENDENSI,
pembacaan paling wajar dari situ adalah "lisensi app = isi sheet itu" — dan
itu tidak benar.

### Yang ditambahkan
1. **Berkas `LICENSE`** di root: MIT lengkap, PLUS bagian
   "ATTRIBUTION REQUIREMENT" yang menyatakan eksplisit apa yang boleh dan
   tidak boleh dilakukan Siapa pun mendistribusikan ulang.
2. **Baris "License"** di kartu Tentang, dengan badge MIT, membuka sheet
   berisi: entri lisensi, blok atribusi siap-tempel, penjelasan kewajiban,
   lalu teks MIT LENGKAP.
3. **Kalimat kewajiban atribusi** di bawah tautan GitHub. Atribusi harus
   berupa kalimat, bukan cuma URL di layar — URL tidak memberi tahu apa
   kewajiban yang sebenarnya.
4. **`licenses_self_note`** di sheet pihak ketiga, supaya "lisensi app ada di
   sheet ini" tidak terjadi.
5. **README** dapat bagian Lisensi (ID + EN) plus tabel komponen pihak ketiga.

### Dua keputusan yang perlu disebut
- **Teks MIT ditampilkan LENGKAP, bukan ringkasan.** Kalau yang tampil
  ringkasan, yang tampil BUKAN notice yang diwajibkan, dan menyalin dari
  layar tidak memenuhi syarat. Karena itu `.textSelection(.enabled)` dipakai
  di seluruh sheet: notice bisa disalin utuh.
- **Blok atribusi ditulis sebagai kalimat siap-tempel** dalam font monospaced
  di dalam kotak, bukan paragraf istilah. Yang perlu dilakukan orang yang
  fork adalah menyalin, bukan membaca.

### Test yang hijau karena alasan yang salah — untuk KELIMA kali
`testAboutCardShowsTheAppLicenseNotOnlyDependencies` awalnya hanya mengecek
`showAppLicense` ADA. Tapi simbol itu juga muncul di
`Button { showAppLicense = true }`, jadi mutasi yang **MENGHAPUS
`.sheet(...)`-nya** tetap LULUS — tombolnya jadi tidak melakukan apa-apa dan
tidak ada yang memberi tahu.

Diperbaiki: test memeriksa call site-nya, yaitu `.sheet` benar-benar
terpasang.

Dua masalah pengukuran lain di file yang sama:
- jendela karakter tetap 3.000 tidak sampai ke baris `.sheet`; `aboutCard`
  saja sudah 3.469 karakter dari deklarasi ke sana. Diperbaiki dengan memotong
  per anggota struct, bukan per jumlah karakter.
- `licenseEntry` awalnya `private` di dalam `LicensesView`, padahal
  `AppLicenseView` juga membutuhkannya. Daripada menyalin, fungsinya
  diangkat ke scope file — baris lisensi justru yang paling harus akurat,
  jadi paling rawan punya dua definisi yang melenceng.

Dan `testAttributionTextCarriesCopyrightAndGitHub` memindai call site SwiftUI
lalu mengambil potongan dari nama key-nya sendiri, jadi hanya menguji bahwa
key ADA, bukan isinya. Sekarang dibaca dari berkas `.strings` di kedua bahasa.

### Lima kali berturut-turut sudah jadi pola
D77, D81, D82, D83, D84. Test sumber yang memeriksa **kehadiran simbol**
tidak punya nilai sebagai bukti; yang menentukan adalah call site-nya, dan
batas bloknya harus benar. Untuk teks hukum seperti lisensi, ini bukan soal
keberanian — artefak yang salah di sini berarti ada build yang tersebar
tidak memenuhi syarat yang justru dia tetapkan sendiri.

### Verifikasi
- `AppLicenseTests` (11), file baru terdaftar di pbxproj.
- Test membandingkan teks MIT di app dengan berkas `LICENSE` per kalimat
  kunci, supaya keduanya tidak bisa melenceng tanpa ada yangmemberi tahu.
- Mutasi diuji 4x, semuanya tertangkap:
  1. kalimat wajib MIT diganti di LICENSE -> 2 test gagal;
  2. `.sheet` lisensi dihapus dari aboutCard -> 2 test gagal;
  3. kalimat kewajiban atribusi dihapus -> 1 test gagal;
  4. teks atribusi dihapus dari `.strings` -> 1 test gagal.
- Test **373/373 lulus** (dari 362). Localization EN == ID.
- Build Debug + Release: **SUCCEEDED**.

### Yang BELUM dikerjakan, dan sebaiknya dikerjakan terpisah
- **`Info.plist` belum punya `NSHumanReadableCopyright`.** macOS
  menampilkannya di dialog About aplikasi — jalan yang paling native untuk
  menampilkan notis hak cipta, dan saat ini tidak terpakai.
- **Berkas `LICENSE` belum di-bundle** ke dalam .app. Notice-nya tampil di
  dalam app (cukup untuk MIT), tapi tidak ikut tersebar bersama binary kalau
  ada yang menarik `.app` saja.
- **Helper (`FreePNHelper`) belum punya berkas lisensinya sendiri.** Dia
  bagian dari project ini dan ikut MIT, tapi belum dicatat eksplisit.---

## D85 — Escape `\u` huruf kecil tidak di-parse; teks tampil literal, 12-Okt-2026

### Gejala
User melaporkan di layar: `MIT u00b7 ...` dan `FreePN u2014 Hak cipta ...`.
Karakter `·` dan `—` tidak muncul; yang tampil justru teks harfiahnya.

### Akar masalah
Parser `.strings` bergaya lama yang dipakai bundle ini mengenali escape
Unicode sebagai **`\Uxxxx` dengan U KAPITAL**. Kalau ditulis `\uXXXX` huruf
kecil, hasilnya bukan karakter: backslash-nya hilang dan yang tersisa adalah
teks `u00b7`. Build tetap sukses, string tetap "ada", tidak ada error.

Diverifikasi dengan tiga probe di dalam app:

| ditulis | hasil runtime |
|---|---|
| `A\u00b7B` | `Au00b7B` — SALAH |
| `A\U00b7B` | `A·B` — benar |
| `A·B` (UTF-8 langsung) | `A·B` — benar |

Petunjuk yang mempercepat identifikasi: `\n` di string yang
sama **berjalan normal** (jadi baris baru sungguhan), sementara
`\u2014` tidak. Dua escape di satu value, hasil berbeda. Itu
langsung mengarah ke parser, bukan ke encoding.

### Ini BUKAN kesalahan yang saya buat
Key lama `licenses_dotmap_note` juga memakai `\u2014` dan **sudah menampilkan
"u2014" sebagai teks sejak dulu**. Hanya saja itu keterangan kecil di sheet
lisensi yang tidak pernah dibaca teliti. Saya hanya mengikuti konvensi yang
sudah rusak di project ini, lalu tidak sengaja mengulanginya di teks yang
justru sedang ditunjukkan user.

Pemeriksaan awal saya mengira bentuknya sudah benar karena memang sama
dengan bentuk yang sudah ada. Yang dibandingkan adalah **penampilan di app**,
bukan bentuk di berkas.

### Perbaikan
Semua `\uXXXX` (7 per berkas) diganti **karakter UTF-8 aslinya**. Dipilih
daripada `\U` kapital karena tidak ada lapisan escape yang bisa rusak salah
lagi, dan jauh lebih mudah dibaca.

### Test yang GAGAL menangkap apa pun — untuk KELIMA kali
`LocalizationEscapeTests` punya dua test:
1. memindai berkas Localization dan melaporkan **nomor baris** yang bermasalah;
2. memanggil `NSLocalizedString` dan memastikan value berisi karakter sungguhan.

Test (2) langsung menangkap mutasinya. Test (1) **lolos**, padahal bersihnya
justru tugas utamanya.

Penyebabnya subjenis yang sama: polanya ditulis `"\\u[0-9a-fA-F]{4}"`. Swift
mengubah `\\` jadi satu backslash, jadi mesin regex menerima
`\u[0-9a-fA-F]{4}` — dan di ICU itu berarti "karakter unicode dengan digit
heksadesimal", bukan "backslash lalu huruf u". `range` selalu `nil`, test
selalu hijau, dan tidak ada mutasi yang bisa menggagalkannya.

Backslash harus digandakan dua kali: satu untuk string Swift, satu lagi untuk
mesin regex. Test yang ditulis khusus untuk menangkap kesalahan escape punya
kesalahan escape sendiri.

### Verifikasi
- `LocalizationEscapeTests` (3).
- Mutasi `MIT ·` -> `MIT \u00b7` -> **2 test gagal**, dan pesan kegagalan
  menyebut `id.lproj baris 360`.
- Semua 7 escape per berkas sudah dikonversi.
- Test **376/376 lulus** (dari 373). Localization EN == ID.
- Build Debug + Release: **SUCCEEDED**.

### Yang perlu diingat
`check-localization.sh` hanya membandingkan daftar KEY antar bahasa. Ia tidak
pernah memeriksa nilai string-nya, jadi kelas kesalahan seperti ini sama
sekali di luar jangkauan skrip itu. Yang ada sekarang: pemindaian escape
(`LocalizationEscapeTests`) dan pemeriksa isi nilai. Keduanya source-scan;
pemeriksaan runtime hanya menutup tiga key tertentu.
---

## D80 — Terminal Mode sebagai mode ketiga Split Tunneling, 14-Okt-2026

Laporan: Ghostty dicentang di split tunneling tapi tetap keluar tanpa VPN,
padahal Chrome jalan. Chrome bukan kebetulan — semua helper network-nya ada
di dalam `Google Chrome.app`, jadi `process_path_regex` ke path bundle-nya
cocok. Ghostty tidak melakukan koneksi apa pun; yang bicara ke internet adalah
cucu-cucunya (`curl`, `ssh`, `git`, brew, AI CLI) yang path-nya di luar bundle.

### Kenapa tidak daftar regex yang lebih panjang
Awalnya binary sing-box 1.12.1 diperiksa langsung. Matcher proses yang ada
tepat tiga: `process_name`, `process_path`, `process_path_regex`. Tidak ada PID,
tidak ada penelusuran silsilah. Jadi "terminal X ⇒ semua perintahnya ikut"
tidak bisa ditulis sebagai rule dengan panjang berapa pun.

Jalur Apple-native juga tertutup: per-app VPN hanya lewat MDM, seluruh
Network Extension sudah dihapus di D42 (tanpa target `.appex`, tanpa
entitlements, tanpa `PBXCopyFilesBuildPhase`), dan app sengaja tidak sandboxed
supaya bisa lewat Personal Team gratis. NE juga tidak akan menyelamatkan
masalah silsilah: extension berjalan sebagai `_networkextension`, sedangkan
pemetaan socket→PID butuh hak root.

### Yang dilakukan: kebijakan melekat pada sesi, bukan ditebak dari paket
`SplitMode` dapat case `.terminal`. Di mode ini **TUN dimatikan** dan tidak ada
rule per-proses sama sekali — tidak ada yang bisa dicocokkan, jadi tidak ada
yang bisa salah pilih. Satu-satunya inbound adalah `mixed` di 127.0.0.1, dan
`TerminalLauncher` membuka binary aplikasi secara langsung dengan env proxy
disuntik (`SessionProxyEnv`). Env diwarisi seluruh keturunan, jadi "proses
turunan mengikuti terminal asal" dijamin secara konstruksi, bukan lewat
pencocokan.

Konsekuensi yang justru diminta user: **tidak ada daftar terminal hardcoded
di FreePN sama sekali**. App mana pun bisa dicentang dan akan diperlakukan
terminal, jadi terminal baru tidak perlu update app.

`open -a` tidak pernah dipakai di sini — LaunchServices membangun ulang
environment dari launchd, jadi env yang disetel di pemanggil tidak akan
diteruskan. Konsekuensinya jendela tidak otomatis maju, ditutup dengan
`NSRunningApplication.activate`. `NO_PROXY` memuat loopback + RFC1918 karena
tanpa itu `curl http://127.0.0.1:28909` ikut diproxy dan gagal; `ALL_PROXY`
memakai `socks5h` agar hostname dipecah di sisi proxy (socks5 biasa =
kebocoran DNS). `NO_PROXY` berbasis CIDR butuh curl ≥ 7.86.

### "Putuskan" tidak mematikan core
Environment proses yang sudah berjalan tidak bisa dihapus dari luar di macOS.
Membunuh port akan membuat setiap perintah berikutnya di terminal yang terbuka
gagal dengan `connection refused` — kesalahan yang menyuruh user menduga
FreePN rusak. Jadi ada tiga state: `idle`, `active` (`final: proxy`), dan
`passthrough` (`final: direct`, core tetap melayani). Putuskan hanya
menurunkan egress; terminal yang sudah terbuka tetap bisa dipakai, tanpa VPN
dan tanpa error.

Meninggalkan Terminal Mode sementara ada terminal hidup memicu dialog
(keep-core/stop-core) lewat `AppState.requestModeChange`, bukan keputusan diam.
`AliveTerminals` disaring `kill(pid, 0)` supaya terminal yang sudah ditutup user
tidak membuat dialog muncul sia-sia.

Terminal Mode dan TUN penuh saling meniadakan: port `mixed-in` akan berebut dan
`route.final` TUN yang default-nya proxy akan ikut menjatuhkan terminal yang
tidak terdaftar — persis kebalikan dari yang dijanjikan mode ini.

### Batasan yang ditulis di UI, bukan disembunyikan
`ping`/`dig`/`nc` mengabaikan env · `sudo` menghapus env (`sudo -E`) ·
`open`/`osascript`/`launchctl` membangun ulang environment sehingga app GUI
yang dijalankan dari terminal tetap direct. Ketiganya adalah fakta runtime
yang akan ditemukan user sendiri dan disimpulkan sebagai "split tunnels
rusak".

### Perbaikan tak sengaja: parser `LocalizationTests`
Menambah key yang value-nya berbeda antar bahasa membuat parser test lokalisasi:
`var idx = t.index(after: eq.upperBound)` melewati satu karakter, karena
`upperBound` sudah menunjuk karakter pertama value. Akibatnya `%d app` terbaca
`d app` di **setiap** key. Tidak pernah ketahuan karena kedua bahasa kehilangan
karakter yang sama dan jumlah placeholder tetap cocok — test placeholder
memang buta untuk value yang dimulai `%d` di satu bahasa saja.

### Verifikasi
- `TerminalSessionTests` (14), termasuk `sing-box check -c` nyata untuk kedua
  egress (config tanpa TUN, tanpa rule per-proses).
- **390/390 lulus**. Localization EN == ID.

---

## D81 — Log perubahan split per aplikasi, 14-Okt-2026

Permintaan: "saat set sebagai VPN tampilkan lognya, dan saat disable juga —
beserta keterangan di keduanya". Dua sisi, bukan satu: kalau hanya yang
berhasil yang dicatat, kasus yang paling sering dikeluhkan (kenapa sudah
dimatikan tapi masih lewat VPN) justru tidak punya jejak.

### Aksi menu jadi bermakna seragam
Menu baris punya dua aksi: **Set sebagai VPN** dan **Hapus set sebagai VPN**.
Keduanya selalu ada di semua mode. "Set sebagai VPN" berarti *trafiknya lewat
proxy* — di inklusif itu masuk daftar, di eksklusif itu justru **keluar** dari
daftar (karena daftar eksklusif berisi app yang bypass). Menyembunyikan salah
satunya per mode hanya membuat user mencari menu berbeda untuk tiap mode.

Konsistensi definisi itu satu: `SplitMode.usesVPN(appIsListed:)`, hidup di
Shared tanpa UI supaya bisa diuji. Badge, menu, dan diff log semuanya
memanggilnya. Tiga tempat dengan aturan sendiri pasti akan berbeda, dan yang
berbeda selalu berbohong.

### Diff: bandingkan EFEK, bukan daftar
`SplitChangeLog.diff` membandingkan "apakah traffic app ini lewat VPN"
sebelum/sesudah, bukan "ada/tidak di daftar". Untuk mode eksklusif keduanya
berlawanan — membandingkan daftar mentah akan mencatat perubahan yang tidak
mengubah apa pun sekaligus melewatkan perubahan yang mengubah segalanya,
termasuk saat mode diganti tanpa menyentuh satu pun app. Karena itu mode
sebelum ikut jadi parameter dan harus disalin sebelum `replaceActive`
menimpa daftar lama.

### Isi log harus jujur soal KAPAN berlaku
Dua informasi yang paling sering disalahartikan:

- **APA** yang ditulis. Mode TUN menulis rule `process_path_regex` dan sama
  sekali TIDAK menyuntik env — disebut eksplisit, karena user yang baru pakai
  Terminal Mode akan mencari `ALL_PROXY` di log dan menyimpulkan app-nya
  rusak kalau tidak disebut. Mode Terminal menyebut env persisnya
  (`127.0.0.1:<port>`), nama variabelnya, dan `NO_PROXY`.
- **KAPAN** berlaku. Aturan baru hanya ditulis ke config saat connect, dan
  env hanya masuk ke proses yang dibuka SESUDAH perubahan. Untuk sisi
  "dimatikan" juga ditambah catatan bahwa env yang sudah tertanam tidak bisa
  dicabut, dan(core bertahan `direct`) supaya user tahu harus menekan Putuskan
  dulu.

### Dua tempat, satu sumber
Riwayat disimpan di `split_changes.json` (maks 100 entri) dan tampil di dua
tempat: panel **Log perubahan** di Split Tunneling (tempat aksinya terjadi)
dan header panel Log di menu Sambung (tempat yang ikut tersalin saat user
menyalin log untuk melapor). `describe()` murni dan deterministik — input sama
→ output sama — supaya bisa diuji tanpa UI.

Entri **tidak** memakai timestamp di dalam string header ConnectView:
`logHeader()` dipanggil tiap 5 detik, dan `Date()` per baris akan
mengubah string pada tick mana pun lalu menginvalidasi seluruh daftar baris
log. Waktu tampil di baris entri pada panel Split Tunneling, yang tidak
di-refresh timer.

### Verifikasi
- `SplitChangeLogTests` (17): arah `usesVPN` per mode, diff (tambah/hapus,
  ganti mode, mode+lista kosong, determinisme), isi log untuk keenam kombinasi
  mode×aksi, dan round-trip berkas.
- Alur nyata di app: toggle → Simpan → entri "Aktif"; toggle lagi → Simpan →
  entri "Nonaktif". Menu terlihat dengan ketiga itemnya.
- **407/407 lulus**. Localization EN == ID.

---

## D82 — Terminal jadi TANDA per app, bukan mode, 14-Okt-2026

Koreksi atas D80. Terminal Mode sebagai mode ke- tiga menunjukkan kesalahpahaman
awal: ia memaksa user memilih antara "semua app" atau "hanya terminal",
padahal yang sebenarnya diinginkan adalah **menandai beberapa terminal di antara
daftar app yang sudah ada**. Keduanya bisa benar-benar berlaku bersamaan:
Ghostty lewat VPN, dan *perintah-perintah di dalamnya* juga lewat VPN.

### Model
- `SplitMode` kembali ke dua case. `configJSON` tidak lagi punya cabang
  terminal sama sekali.
- `terminalApps` menjadi daftar mandiri, tidak ikut tersentuh
  `replaceActive` dan tidak ikut hilang saat sakelar split dimatikan.
  Mematikan split = VPN penuh; itu tidak ada hubungannya dengan env proxy.
- `SplitChangeLog.Entry` dapat `kind` (`.vpn` / `.terminal`) karena entri
  terminal tidak lagi punya mode. Labelnya `[terminal]`, bukan `[inclusive]` —
  menulis mode yang salah di sini akan membuat user mengira menandai terminal
  juga mengubah aturannya.
- `terminalDiff` membandingkan keanggotaan daftar, bukan efek mode.

### Dua mesin boleh hidup berdampingan
D80 melarang TUN dan core sesi bersamaan karena berebut `mixed-in`. Dengan
terminal jadi tanda per app, larangan itu justru salah: Ghostty ditandai
terminal tidak boleh membuat Chrome kehilangan VPN. Kedua mesin memakai port
masing-masing (`FreePort.tcp` mencari yang bebas), dan core sesi tetap punya
nama proses `sing-box` sehingga traffic proxy-nya ikut dikecualikan dari TUN —
persis yang dibutuhkan, kalau tidak setiap koneksi terminal akan masuk dua kali.

Dialog tidak lagi soal "ganti mode" (menukar inklusif/eksklusif tidak
menyentuh env sama sekali), tapi soal **melepas semua tanda terminal**
sementara ada terminal hasil FreePN yang masih hidup — pertanyaannya sama:
matikan core atau biarkan sebagai jalur direct.

### Race hidrasi di tabel Split Tunneling (temuan tak terduga)
Saat verifikasi, `split.json` tiba-tiba berisi `exclusive[]` +
`terminalApps[Ghostty, Chrome]` padahal isinya `inclusive[Ghostty, Chrome]`.
Penyebabnya bukan writer misterius melainkan race yang sudah ada sejak awal:
`loadFromStateIfNeeded()` dipanggil dari `onAppear`, yang bisa berjalan
SEBELUM `loadPersistedState()` selesai menempelkan hasil baca. Buffer lokal
kemudian menangkap daftar BAWAAN, tabel sempat menampilkan "0 aplikasi dipilih",
dan Save di celah itu menimpa daftar user dengan kosong.

`AppState` sudah punya `waitForHydration()` dengan peringatan eksplisit
("tanpa itu operasi berjalan terhadap daftar bawaan dan menimpa data user") —
`SplitTunnelView` ternyata lupa memanggilnya. Sekarang `.task` menunggu
hidrasi, `save()` menolak keras sebelum `hydrated`, dan tombol Save nonaktif
selama itu. Bug ini tidak bergantung pada fitur Terminal: dia sudah
merusak daftar app user sebelum tanda terminal ada.

### Cacat teks yang ketahuan karena log dibaca
`splitlog_env_injected` punya `127.0.0.1:{port}` sementara `{port}` sudah
berisi `host:port` — hasilnya "127.0.0.1:127.0.0.1:28108". Dan kalimat "TUN is
off in Terminal Mode" masih menyebut mode yang sudah tidak ada. Dua-duanya
sekarang dikunci test (`testInjectedHostIsNotDoubled`,
`testTerminalSidesDoNotPromiseReconnect`).

### Verifikasi
- `TerminalSessionTests` (14) ditulis ulang untuk model baru: menandai terminal
  TIDAK boleh mengubah config TUN, `mode: "terminal"` versi lama tetap decode,
  tanda terminal bertahan saat sakelar split dimatikan.
- `SplitChangeLogTests` (19): diff terminal, label, isi teks keenam kombinasi.
- Alur nyata: centang Terminal di Ghostty → Save → `terminalApps` terisi
  sementara `inclusiveApps` tetap utuh, log menampilkan env yang disuntik.
- **409/409 lulus**. Localization EN == ID.

---

## D83 — "IP terminal tetap direct": dua bug berlapis, 14-Okt-2026

Laporan: Ghostty ditandai Terminal, tapi `curl ifconfig.me` di dalamnya
menampilkan IP biasa. Gejalanya persis seperti bug yang sudah pernah dibahas:
split tunneling tidak bekerja. Yang sebenarnya terjadi ada dua, dan keduanya
harus diperbaiki supaya gejalanya hilang.

### Bug 1 — lingkaran DNS saat resolusi hostname node (satu baris)
`sessionConfigJSON` memberi outbound `proxy` sebuah `domain_resolver`, dan
memilih `proxy-dns`. Tapi `proxy-dns` ber-detour ke outbound `proxy` itu juga.
Maka me-resolve `cf.090227.xyz` berarti membangun koneksi ke
`cf.090227.xyz`, dan menyelesaikan koneksi itu harus lewat `cf.090227.xyz`:

```
lookup cf.090227.xyz: DNS query loopback in transport[proxy-dns]
```

Yang membuatnya sulit. Semua ini diverifikasi:

1. Config hasil builder **lolos `sing-box check`** — jadi tes yang ada tidak
   bisa menangkapnya; loop bukan kesalahan sintaks.
2. Core **tetap hidup dan port tetap melayani**, sehingga UI menampilkan
   "sesi aktif".
3. Yang gagal hanya koneksi dari terminal:
   `curl: (97) Can't complete SOCKS5 connection`.
4. Karena `curl` di terminal keluar dengan IP asli — persis gejala "tetap
   direct" — padahal tidak ada satu pun rule routing yang salah.

Perbaikan: `outbound["domain_resolver"] = "direct-dns"`. `dns.final` tetap
`proxy-dns` supaya pencarian domain milik user sendiri tetap lewat VPN dan tidak
bocor ke ISP — hanya hostname node sendiri yang boleh di-resolve lokal. Bukti:
sebelum → `curl` keluar kosong dengan exit 97; sesudah → `2a09:bac5:…` (IP
exit node), berbeda dari IP langsung mesin.

### Bug 2 — `pkill -x sing-box` di helper membunuh core sesi
`CoreRunner.killLeftovers()` (helper, root) menjalankan `pkill -x sing-box`
untuk membersihkan core-nya sendiri dari percobaan gagal. Tapi itu membunuh semua
proses dengan nama itu di seluruh mesin — termasuk core sesi Terminal Mode, yang
memakai binary dan nama yang sama.

Yang membuatnya Nearly lolos: sing-box memperlakukan SIGTERM sebagai shutdown
rapi, jadi ia **keluar dengan kode 0** tepat setelah mencetak "sing-box started".
Tidak ada error, tidak ada crash, dan `LocalCoreRunner` melaporkannya sebagai
"core exited (code 0)" — terbaca seperti hal biasa.

Akibatnya sesi mati setiap kali VPN disambung ulang, dan karena UI menampilkan
status "mati" tanpa alasan, user menyimpulkan fiturnya memang tidak berfungsi.
Bukti pola: dengan core sesi hidup, `pgrep -x sing-box` cocok dua proses
(TUN + sesi) sementara `pgrep -f 'freepn/config.json'` hanya cocok satu.
Perbaikan: `pkill -f 'freepn/config.json'` di helper DAN di skrip installer.

### Bug 3 (pendukung) — menebak node, mematikan core saat probe gagal
- `syncTerminalSession()` memakai `nodes.first` sebagai cadangan kalau tidak
  ada node terpilih: itu menebak node pertama dari daftar 19.000 server, yang
  hampir pasti mati. Diganti: hanya node yang benar-benar dipilih user, kalau
  tidak ada, panel menampilkan "pilih server dulu".
- Probe IP keluar yang gagal **tidak lagi** mematikan core. Probe gagal belum
  tentu berarti node mati (bisa timeout atau DNS lambat), dan mematikan core
  membuat terminal kehilangan endpoint-nya sepenuhnya — lebih buruk dari error
  yang terlihat.
- App sekarang juga menyalakan core sesi **saat launch** kalau ada terminal
  yang ditandai; sebelumnya menutup-membuka app meninggalkan terminal menunjuk
  port yang sudah tidak ada.

### Diagnostik yang benar-benar berguna
Pesan error core tadinya dipotong satu baris dan bocor kode ANSI
(`[36mINFO[0m`), sehingga penyebabnya tidak pernah terbaca. Sekarang dibersihkan
dengan `ConnectionLog.stripANSI` dan dibungkus penuh, plus `LocalCoreRunner`
menambahkan baris "core exited (code N)" atau "core killed by signal N".

### Verifikasi
- 2 tes regresi baru: `testProxyOutboundResolvesServerHostWithoutLooping` dan
  `testUserDomainsStillResolveThroughProxy`.
- Config yang sama dijalankan manual: sebelum → gagal, sesudah → IP exit node.
- **411/411 lulus**. Localization EN == ID.

---

## D86 — Terminal direct padahal dibuka dari FreePN: app single-instance, 14-Okt-2026

Laporan kedua untuk gejala yang sama seperti D83, dan sekali lagi penyebabnya
bukan routing. Duplikat dari user yang sudah menjalankan semua langkah yang
dianjurkan UI: Ghostty ditandai Terminal, mode Inclusive, tombol ▶ ditekan,
`curl` di dalam jendela itu tetap keluar dengan IP asli.

### Penyebab — eksekusi binary tidak berlaku untuk app single-instance

`TerminalLauncher.launch()` meng-`Process.run()` binary app terminal. Prinsipnya
benar dan tetap benar: `open -a` membangun environment dari launchd, bukan dari
environment pemanggil, jadi env proxy tidak akan ikut. Tapi ada asumsi tersembunyi
di dalamnya — **asumsi bahwa menjalankan ulang binary akan membuka jendela baru**.

Hampir semua terminal modern justru sebaliknya. Saat app-nya sudah hidup, `run()`
yang kedua tidak menjalankan app: ia mengirim permintaan "buka jendela" ke
instance yang sudah ada, lalu proses yang baru **keluar dalam hitungan milidetik**.
Jendela yang muncul adalah milik instance LAMA, yang env-nya tidak pernah
berubah.

Yang membuat ini lolos diam-diam: `launch()` mengembalikan `error: nil` tanpa
memeriksa apa pun. Jadi FreePN mencatat PID yang sudah jadi mayat, menampilkan
"berhasil", dan user melihat jendela yang benar dengan isi yang salah. Tidak ada
satu pun tanda failure di mana pun.

Mode Inclusive memperburuk tanpa tambahan alasan: `route.final = direct`, jadi
begitu env hilang, terminal tidak punya jalur lain ke VPN. Di mode Exclusive anak
prosesnya masih tertangkap `route.final = proxy` lewat TUN; di Inclusive tidak
pernah.

### Perbaikan 1 — verifikasi, dan `isAlive` harus benar dulu

`kill(pid, 0)` mengembalikan 0 untuk anak proses yang sudah keluar tapi belum
di-reap. Statusnya zombie, dan zombie masih ada di tabel proses. Verifikasi baru
karena itu akan **selalu lolos**, persis seperti bug yang diperbaikinya. Diperbaiki
dengan membaca `p_stat` lewat `sysctl(KERN_PROC_PID)` — tanpa fork, tanpa parse
output.

Bonus yang sama pentingnya: `aliveLaunched()` memakai fungsi yang sama, jadi
sebelum ini daftar `launched` juga tidak pernah menyusut dan dialog "terminal
masih terbuka" muncul padahal semua jendela sudah ditutup.

### Perbaikan 2 — env pindah dari proses app ke proses shell

Env tidak lagi ditempelkan ke proses app. `Shared/TerminalInvocation` menulis
wrapper script yang meng-export env lalu `exec $SHELL`, lalu menyuruh app membuka
jendela baru yang menjalankan script itu lewat argumen yang sudah dikenal:

| App | Argumen |
|---|---|
| Ghostty | `-e <script>` |
| kitty | `<script>` |
| Alacritty | `-e <script>` |
| WezTerm | `start -- <script>` |

App yang tidak dikenal **tidak ditebak** — falls back ke perilaku lama (diverifikasi,
bukan diam-diam). Menebak flag yang salah lebih buruk daripada tidak memakai
wrapper: app bisa memperlakukan script sebagai file config dan gagal start.

Warp sengaja tidak ada. Warp tidak mendokumentasikan cara menjalankan perintah
dari CLI, dan ia menutup jendela yang baru dibuat begitu proses pertama selesai.

Dua detail yang mudah salah dan sekarang tertutup tes:
- **Login shell dari `/etc/passwd`, bukan `$SHELL`.** Kalau FreePN dibuka dari
  Finder, `$SHELL` yang diwarisi launchd sering salah (`/bin/bash` walau user
  pakai zsh), dan wrapper menjalankan shell yang salah.
- **Nilai di-quote.** `NO_PROXY` berisi `*.local` dan CIDR; tanpa quote `*`
  di-expand shell. `testWrapperScriptActuallyExportsEveryProxyVariable` benar-benar
  menjalankan script-nya lewat `/bin/sh` lalu `env`, bukan membandingkan string.

### Yang TIDAK berubah, dan alasannya

Dugaan awal saya: `ALL_PROXY=socks5h://` hanya dipahami curl, jadi tool lain
memabaikannya dan keluar direct. **Terbukti salah.** Diuji langsung di mesin dengan
proxy yang tidak reachable (`127.0.0.1:1`):

| | `socks5h://` | `socks5://` |
|---|---|---|
| curl 7.87 | `Uses proxy env variable ALL_PROXY == 'socks5h://…'` | diterima |
| python requests 2.32 | `SOCKSHTTPSConnectionPool` | `SOCKSHTTPSConnectionPool` |

Keduanya sama-sama diterima, jadi tidak ada gain portabilitas dari menurunkan
skema, dan `socks5h` mencegah kebocoran DNS. `SessionProxyEnv` tidak diubah.

### Bagian D83 yang belum benar-benar selesai

D83 mengklaim `pkill -x sing-box` sudah diperbaiki "di helper DAN di skrip
installer". Yang benar: helper saja. `scripts/install-helper.sh` masih
memakai `pkill -x sing-box` di kedua jalur, jadi `sudo ./scripts/install-helper.sh`
masih mematikan core sesi terminal milik user yang sedang berjalan. Diganti
`kill_freepn_cores {vpn|session|all}` yang match per-config; jalur install hanya
menyentuh core TUN, jalur uninstall — dan hanya di situ — menyentuh keduanya.

### Di luar scope: `SplitChangeLogTests` gagal 9 assertion

Ditemukan tak sengaja karena suite merah saat verifikasi. Penyebabnya bukan
kode: `AppleLanguages` mesin ini `id-ID`, jadi `NSLocalizedString`
mengembalikan teks Indonesia, sementara 9 assertion itu menuliskan kalimat
literal bahasa Inggris ("No proxy environment", "close it and reopen",
"inherits", "reconnect", "session core starts on its own"). Semua literal
Inggris diganti pemanggilan key yang sama dengan production code. Suite jadi
hijau di bahasa mana pun.

### Verifikasi
- 6 tes baru: peta plan, kapitalisasi bundle id, eksekusi wrapper sungguhan
  (termasuk kasus kutip tunggal), `exec` vs `&`, dan `isAlive` untuk
  zombie/PID asing.
- `bash -n scripts/install-helper.sh` bersih.

## D87 — Tanda Terminal & core sesi DIHAPUS TOTAL; Split Tunneling hanya dua mode, 14-Okt-2026

Permintaan user: di Split Tunneling ada fitur menandai app sebagai Terminal;
hapus total fiturnya — termasuk kartu "core sesi mati" — supaya yang tersisa
hanya Inklusif dan Eksklusif.

### Yang dibuang

- `SplitTunnelConfig.terminalApps` + `hasTerminals`. Satu keputusan "app ini lewat
  VPN atau tidak" sekarang hanya punya satu tempat menjawabnya: mode + daftar
  app aktif. Tidak ada lagi daftar kedua yang bisa sworek dengan `mode.usesVPN`.
- `TerminalSessionManager`, `TerminalLauncher`, `TerminalInvocation`,
  `SessionProxyEnv` — dihapus sebagai berkas, bukan dinonaktifkan.
- `SingBoxConfigBuilder.sessionConfigJSON` + `SessionEgress`. Config sesi itu
  tidak pernah memakai TUN: ia hanya `{mixed-in} → proxy`, jadi setelah env
  proxy tidak ada lagi, config itu tidak punya pembaca.
- Kartu status sesi, tombol ▶ buka aplikasi, kolom + checkbox Terminal,
  dialog "terminal masih terbuka", dan tombol Tes Jalur di panel Split
  Tunneling.
- `AppState.syncTerminalSession`, `pendingTerminalClear`,
  `aliveSessionTerminals`, `resolvePendingTerminalClear` — beserta pemanggilan
  `session.connect/disconnect` di `AppState.connect/disconnect`. `connect` kini
  menjalankan satu mesin (TUN), tidak dua.
- `SplitChangeLog.Kind` + `terminalDiff` + `mixedPort`. Setiap entri log sekarang
  selalu bermakna "aturan TUN", jadi label `[terminal]` tidak mungkin lagi muncul.
- Semua key `terminal_*`, `splitlog_env_*` selain `splitlog_env_none`,
  `splitlog_session_core_*`, `col_terminal`, dan `action_ok` (yang tidak lagi
  dipakai view mana pun) di `en` + `id`.
- `FreePNTests/TerminalSessionTests.swift` (355 baris).

### Data milik user yang sudah ada di disk

Dua berkas, dua penanganan berbeda — sengaja:

- `split.json` **tidak diubah decoder-nya**. `terminalApps` kini tidak ada di
  `CodingKeys`, dan `Codable` membuang key asing, jadi daftar TUN user tetap
  utuh. `mode: "terminal"` dari versi lama tetap jatuh ke `.exclusive`
  (mekanisme `decodeIfPresent` + `SplitMode(rawValue:)` sudah ada sejak D80).
- `split_changes.json` **harus diubah cara bacanya**. Entri lamanya ber-`kind`
  `"terminal"`, dan field itu tidak punya padanan lagi. Kalau dibiarkan,
  entri itu akan tampil sebagai entri VPN biasa berlabel `[exclusive]` — log
  yang berbohong soal app yang tidak pernah disentuh. Kalau decode-nya
  dibiarkan gagal untuk satu baris, SELURUH riwayat ikut hilang termasuk entri
  TUN yang masih relevan. Jadi `SplitChangeLog.decode` membaca per-baris lewat
  `Row` dan melewati baris yang `kind`-nya bukan `vpn`.

### Yang DIPERTAHANKAN, dan kenapa

- `splitlog_env_none` ("tanpa environment proxy: mode ini memakai TUN dan
  pencocokan path") masih jujur dan masih berguna: user yang mencari `ALL_PROXY`
  di log harus menemukan jawaban negative, bukan-teks-yang-hilang.
- `LocalCoreRunner` tetap: dipakai `ConnectionManager` dan `RealDelayTester`.
  Hanya `TerminalSessionManager` yang memakainya sebagai "mesin kedua" yang
  hilang, bukan ability menjalankan core tanpa helper.
- Match per-config (`pkill -f freepn/config.json`, bukan `pkill -x sing-box`)
  tetap. Alasannya tidak berubah — yang berubah hanya salah satu contoh
  korbannya (dari core sesi FreePN ke sing-box milik tool VPN lain milik user),
  jadi penjelasan di `CoreRunner`, `HelperInstaller`, dan
  `scripts/install-helper.sh` ditulis ulang agar tidak menyebut fitur yang sudah
  tidak ada. Cabang `session)` di `kill_freepn_cores` dihapus; `vpn` dan `all`
  tetap.

### Verifikasi
- `xcodebuild … build` bersih; `… test` 397 tes, 0 kegagalan.
- Tes baru: entri log tidak boleh menjanjikan core sesi (`testNoEntryPromisesASessionCore`),
  `kind: "terminal"` di riwayat lawas dilewati tanpa menenggelamkan entri TUN
  (`testLegacyTerminalEntriesAreSkippedWithoutLosingTunEntries`), `split.json`
  yang masih punya key `terminalApps` tetap utuh
  (`testSplitFileWithLegacyTerminalKeyKeepsItsApps`), dan hanya ada dua mode
  (`testOnlyInclusiveAndExclusiveExist`).
- `bash scripts/check-localization.sh` → key EN == ID.

---

## D88 — Peta dunia menandai server yang DIPAKAI, bukan yang DIREKOMENDASIKAN, 14-Okt-2026

### Permintaan
"map menunjukkan lokasi server yang direkomendasikan, bukan server yang
dipakai"

### Akar masalahnya

Tidak di `ServerWorldMap` — view itu benar. Salah di **call site**:

```swift
// ConnectView.swift, recommendedCard
ServerWorldMap(node: n)     // n = state.recommendedNode
```

`AppState.recommendedNode` (`AppState.swift:1016`):

```swift
let value = selectedNode ?? quickConnectNode() ?? filteredNodes.first
```

Tiga konsekuensi, semuanya salah untuk peta:

1. **Peta bisa menunjuk negara yang berbeda dari tunnel yang jalan.** Kalau
   tunnel aktif di node A tapi `selectedNode`/ping-fastest menunjuk node B,
   peta bergeser ke B.
2. **Peta menunjuk server tebakan saat tidak ada sambungan.** `filteredNodes.first`
   adalah node pertama di feed — bukan pilihan user.
3. **Pin bisa loncat sendiri.** `recommendedCache` di-invalidate setiap ping
   datang (`invalidateDerived()`), jadi koordinat peta ikut berubah mengikuti
   hasil latency terbaru.

Yang memperburuk: komentar di `pins(for:)` mengklaim `node` "hanya non-nil
saat ada server aktif". Klaim itu tidak pernah benar, dan `isActive` di-hardcode
`true` — jadi pin berdenyut di server yang tidak pernah dipakai. `activeNode`
(`connection.lastNode ?? selectedNode`) yang sebenarnya melacak sambungan
tidak pernah dipakai peta sama sekali.

### Yang diubah

1. **Peta pindah dari kartu Rekomendasi ke kartu Daya** (`powerCard`),
   berdampingan dengan `nodeStrip` yang juga soal node aktif. Peta dan
   tombolnya sekarang satu kartu, jadi tidak bisa berbeda pendapat.
2. **`ServerWorldMap` dapat `isConnected`** — denyut (halo) sekarang berarti
   "tunnel hidup", bukan sekadar "ada node".
3. **`ConnectView.mapNode(connected:selected:)`** — fungsi murni
   `connected ?? selected`, dipakai `activeNode`. Dipisah supaya aturan
   "terhubung menang atas terpilih" bisa diuji tanpa `AppState`.
4. **Layout kolom kanan dirapikan.** Peta 260pt keluar dari kartu Rekomendasi,
   jadi kartu itu kehilangan ~280pt isinya dan `statsRow` (Traffik + Sumber)
   naik ke kolom kanan supaya tinggi baris atas tetap seimbang.
   `maxHeight: .infinity` dicabut dari `recommendedCard` — tanpa peta tidak ada
   lagi isi yang justifies tinggi penuh, dan flag itu menyisakan ~130pt ruang
   kosong di bawah isinya.

### Perilaku final yang dikunci

| Keadaan | Node yang dipetakan | Pin |
|---|---|---|
| Tersambung | `connection.lastNode` (server yang membawa trafik) | denyut |
| Belum sambung, ada node terpilih | `selectedNode` | diam |
| Tidak ada node | — | peta tampil tanpa pin |

Peta tidak pernah kosong/di-`if` supaya kartunya tidak reflow tiap user ganti
server.

### Yang DIPERTAHANKAN, dan kenapa

- **`ServerWorldMap` tetap view murni tanpa baca state.** `pins(for:isConnected:)`
  tetap `nonisolated` dan statis, jadi koordinatnya bisa diuji tanpa merender
  GeoJSON.
- **Prioritas lokasi tidak berubah**: koordinat kota (`GeoIP`, kalau host IP
  literal) → koordinat DNS ter-cache → centroid negara → tanpa pin.
- **Kartu Rekomendasi tetap ada** dan tetap punya badge kualitas. Yang hilang
  hanya peta-nya; kartu itu tetap menjelaskan "server yang sarankan" tanpa
  menuduh peta soal dia.

### Verifikasi
- `xcodebuild … build` bersih; `… test` **405 tes, 0 kegagalan** (dari 397).
- **Regresi negatif dijalankan**: `node: activeNode` diganti balik jadi
  `node: recommended` → `MapNodeSourceTests` gagal tepat 2 tes dengan pesan
  yang menyebut baris yang salah (`ConnectView.swift:407`). Fix dipulihkan.
- Tes baru: `testSelectedButNotConnectedPinDoesNotPulse`,
  `testMapNodePrefersTheServerInUseOverTheOneSelected`,
  `testPinCoordinatesBelongToTheGivenNode`, dan
  `MapNodeSourceTests` (source-scan call site — fungsi yang benar tetap bisa
  disalahpakai pemanggil yang salah, persis yang terjadi di sini).
- Dijalankan sungguhan: sambung ke node 🇸🇬 → pin muncul di Asia Tenggara
  (sesuai `103.8°E, 1.35°N`) dengan halo denyut; putus → pin tetap di sana
  tapi kecil dan diam.
- `bash scripts/check-localization.sh` → key EN == ID.

---

## D89 — Peta jadi elemen dominan; Recommended dipangkas jadi strip, 14-Okt-2026

### Permintaan
"peta wajib menonjol, recommended server kecil saja, tidak terlalu penting"

### Kondisi sebelumnya (setelah D88)
Peta sudah benar menandai server yang dipakai, tapi masih kecil: 224 x 160pt
di dalam kolom Daya 260pt, dengan pin ~10pt. Recommended masih makan ~250pt
tinggi di kolom yang sama. Rasio proporsinya terbalik: yang penting
kecil, yang tidak penting besar.

### Yang diubah

1. **`mapCard` baru** — kartu sendiri dengan header "Lokasi Server" + nama
   negara di kanan. Mengisi seluruh sisa tinggi kolom kanan, jadi peta
   ~630 x 340pt: elemen paling besar di layar.
2. **Recommended jadi strip satu baris**: bendera, nama, asal, negara,
   badge protokol, latensi, tombol connect. Header + tombol refresh tetap.
3. **Peta keluar dari kartu Daya** (`Spacer` saja yang tersisa), dan
   `statsRow` kembali lagi penuh di bawah baris atas — supaya baris atas
   tidak jadi satu kolom tinggi + satu kolom pendek.
4. **`ServerWorldMap.pinRadius` 0.42 → 0.72.** Radius pin dinyatakan dalam
   *satuan peta*, lalu `MapPinView` mengalikannya dengan skala peta — jadi
   memperbesar peta otomatis memperbesar pin secara proporsional. Angka lama
   dipakai saat peta cuma 224pt; dipinjam ke peta 630pt, pin-nya tetap
   ~10pt dan nyaris tak terlihat.
5. **Negara pindah ke header peta.** `countryLabel(n)` (bukan
   `displayName` telanjang) supaya kode negara tak dikenal jatuh ke nama
   node — header tidak pernah menampilkan "ZZ".
6. **Badge "Fast / Stable / Reliable" (`qualityTagRow`) dihapus.** Tidak ada
   satu pun angka atau ikon di layar yang mengukurnya; itu klaim
   yang ditandai sebagai fakta di atas server yang nilainya belum diuji.
   `qualityTags` ikut dibuang.

### Kenapa peta TIDAK dibuat "baris penuh" selebar jendela

Pertanyaan itu sempat jadi pilihan di brief, dan memang perlu dijawab:
proyeksi Robinson punya rasio ±1.9:1. Peta setinggi 240pt yang selebar
1160pt hanya akan memakai ~460pt dari lebar itu — peta kecil dengan 350pt
ruang kosong di kiri dan kanan. Peta 2:1 di kolom kanan (~630 x 340pt) jauh
lebih besar DAN pin-nya tetap terbaca. Memilih layout yang tidak
benar-benar memperbesar peta adalah pilihan yang salah.

### Perilaku yang dikunci

| Keadaan | Yang tampil |
|---|---|
| Tersambung | Header peta = negara; pin besar + halo denyut |
| Belum sambung, ada node terpilih | Header peta = negara; pin kecil diam |
| Tidak ada node | Header peta tanpa negara; peta tanpa pin |

Peta tidak pernah hilang/reflow — kartu selalu tinggi yang sama.

### Yang DIPERTAHANKAN, dan kenapa

- **Tombol connect Recommended = tombol yang sama** dengan tabel Server
  (panah / spinner / centang). Mengeklik "Recommended" tidak lagi berarti
  ada jalur connect terpisah yang bisa berbeda dari `nodeStrip`.
- **`qualityTags` dihapus dari `qualityTagRow`, tapi `CardHeader` dan
  `latencyChip` tetap** — angka latensi (ms) masih tampil dan itu satu-
  satunya klaim performa yang memang terukur.

### Verifikasi
- `xcodebuild … build` bersih; `… test` **406 tes, 0 kegagalan** (dari 405).
- Tes baru: `testMapLivesInItsOwnCardAndNowhereElse`,
  `testRecommendedCardIsASingleCompactRow`; `testMapIsFedActiveNodeWithConnectionStatus`
  dan `testMapIsNeverFedTheRecommendedNode` diperbarui untuk struktur baru.
- Dijalankan sungguhan, sambung ke node 🇸🇬 → header peta berbunyi "Singapore",
  pin besar dengan halo denyut berada di Asia Tenggara; Recommended jadi strip
  satu baris dengan centang hijau.
- `bash scripts/check-localization.sh` → key EN == ID. Key baru:
  `card_server_location` ("Server Location" / "Lokasi Server").

## D90 — Cache feed dihapus: hapus sumber langsung 0, akun/entri baru langsung terpakai, 15-Okt-2026

### Permintaan
"Hapus fitur cached di source. Kalau source dihapus, angkanya jadi 0. Kalau
ada akun yang berubah, pakai yang baru."

### Masalah yang dibetulkan

`SubscriptionCache` menyimpan salinan teks feed mentah per sumber di
`Application Support/FreePN/subcache/<uuid>.json`, dan `fetchOne` memakainya
sebagai jalan PERTAMA: selama TTL 6 jam, `SubscriptionService` **tidak
menyentuh jaringan sama sekali**. Tiga konsekuensi langsung:

1. **Refresh tidak pernah melihat perubahan.** Entri baru yang ditambahkan
   penyedia, dan node yang dihapus/diubah di sana, tidak akan muncul selama
   masih di dalam masa TTL. Tombol Refresh hanya mem-parsing ulang teks yang
   sama — dan UI justru memberi tahu lewat pil "Cached" bahwa itulah yang
   terjadi, bukan permintaan data baru.
2. **Sumber yang dihapus meninggalkan puing.** Cache di-key dengan UUID
   sumber, dan `removeSource` tidak pernah memanggil api hapus (memang tidak
   ada) — jadi berkasnya menumpuk selamanya. Di mesin ini: **413 berkas,
   ±190 MB**, dan hanya 13 yang masih milik sumber yang terdaftar. 44 berkas
   lainnya memakai nama versi lama ber-percent-encoding yang `url(for:)` versi
   sekarang tidak akan pernah cocok — mati total, tidak bisa dihapus lewat
   app, tidak bisa dibaca.
3. **Ganti URL = sumber yang salah label.** `renameSource` sengaja menjaga
   UUID tetap (demi node), lalu hanya mengosongkan angkanya. Berkas cache
   masih dipecet dengan UUID yang sama, jadi refresh berikutnya—in spite of
   URL baru—melayani feed LAMA. Server dari URL lama tampil dengan nama baru.

### Yang diubah

- **`SubscriptionCache.swift` dihapus seluruhnya.** `load(ttl:)`, `loadStale`,
  `save`, `parseCachedOnly`—semuanya hilang. Tidak ada jalur kode yang
  menulis atau membaca `subcache/` lagi.
- **`SubscriptionService.fetchOne` langsung ke jaringan.** Short-circuit TTL
  dan fallback stale dihapus; kalau semua kandidat URL gagal, hasilnya
  `nil` + error, sumber jadi `0`. Nol itu jujur — lebih baik daripada
  menampilkan jumlah server dari feed yang sudah dihapus.
- **`FetchOutcome.fromCache` dihapus** dari struct, sekaligus assignment
  `lastError = "cached"` di `refreshAll`/`refreshSource`. Sukses selalu
  `lastError = nil`.
- **Pil status "Cached" dihapus** dari `SourcesView.statusPill`, key
  `status_cached` dihapus dari `Localizable.strings` (en + id).
- **`AppConstants.subscriptionCacheTTL` dihapus.** Tidak ada TTL karena tidak
  ada yang di-cache.
- **`removeSource` menghitung ulang angka.** `keptCount` tiap sumber dihitung
  ulang dari `nodes` yang baru (`resortCountsOnly`), jadi setelah hapus
  selesai tidak ada angka di layar yang berasal dari refresh sebelumnya.
- **`renameSource` juga membuang node lama saat URL berubah.** Sebelumnya
  hanya angka yang dikosongkan; node dari URL lama tetap nangkring dengan
  label baru. Sekarang keduanya dibuang — termasuk ping, favorit, dan node
  terpilih, lewat helper `detachNodes` yang dipakai kedua jalur (hapus
  sumber & ganti URL) supaya tidak ada "terbukti hidup" untuk server yang
  sudah tidak ada.
- **Pembersihan satu kali saat app start.** `AppState.init` menyalin
  `AppStorage.legacyCacheDirectory` di actor utama lalu menghapusnya lewat
  `Task.detached(priority: .utility)` — 400+ berkas di `@MainActor init` akan
  menahan frame pertama. Kegagalan diabaikan: tanpa cache, app tetap jalan.
  Yang hilang cuma ±190 MB yang tidak pernah terpakai lagi.

### Kode mati yang ikut dibuang

- **`OrphanNodeAdopter` + `repairOrphanedSources` dihapus.** Perbaikan node
  yatim (D66) hanya mungkin lewat salinan lokal: tanpa cache, "dari mana
  node ini berasal" mustahil dijawab tanpa mengunduh 12 feed saat app dibuka
  — hal yang D66 sendiri sudah tolak. `repairOrphanedSources` sudah punya
  penjaga "kalau tidak ada satu pun feed terbaca, jangan sentuh apa pun",
  jadi tanpa cache ia jadi no-op diam-diam. Lebih baik tidak ada daripada
  ada tapi tidak pernah jalan.
- **`RealFeedImpactTests` dihapus.** Seluruh input-nya adalah cache feed di
  disk; setelah D90 folder itu tidak pernah dibuat lagi, jadi ketiga test-nya
  akan `XCTSkip` selamanya. Mengukur dampaknya butuh feed nyata — bukan
  tempatnya di unit test yang tidak boleh bergantung jaringan.
- Class `OrphanSourceTests` (test yang menguji `OrphanNodeAdopter`) dihapus
  dari `OrphanSourceTests.swift`. `BuiltInSourceTests`,
  `DuplicateSourceTests`, dan `LiveSourceFilterTests` tetap — tidak bergantung
  cache.

### Konsekuensi yang diterima

- **Offline tidak bisa refresh.** Refresh saat offline akan menandai sumber
  `unavailable` dan emptied dari nol. Itu konsekuensi langsung dari
  "hapus total" — dan memang lebih jujur daripada menahan angka lama
  tanpa memberitahu kalau angka itu sudah basi. `nodes.json` yang sudah
  tersimpan tetap ada, jadi daftar server yang tampil tidak ikut hilang saat
  app dibuka; yang hilang hanya kemampuannya mengambil feed baru.
- **Perbaikan node yatim (D66) hilang.** Sumber yang mewarisi UUID generasi
  lama akan tetap kosong sampai refresh berikutnya menimpanya dengan ID yang
  sekarang. Karena `waitForHydration()` masih ada, kasus itu tidak akan
  muncul lagi di masa depan.

### Perilaku yang dikunci

| Keadaan | Yang tampil |
|---|---|
| Refresh dalam masa TTL lama | Unduh ulang dari jaringan (tidak ada TTL lagi) |
| Semua URL gagal | Sumber `unavailable`, jumlah server 0 |
| Sumber dihapus | Baris hilang, node ikut hilang, angka sumber lain dihitung ulang |
| URL sumber diganti | Angka 0 + node lama ikut dibuang sampai refresh mengunduh feed baru |
| Pil status | Tidak ada lagi "Cached"; `ok` berarti data dari unduhan terakhir |

### Verifikasi
- `xcodebuild … build` bersih; `… test` **395 tes, 0 kegagalan** (dari 406 —
 Penurunan datang dari `RealFeedImpactTests` (3) dan `OrphanSourceTests` (8) yang
  dihapus bersama kodenya).
- `bash scripts/check-localization.sh` → key EN == ID (`status_cached`
  dihapus dari kedua berkas).

## D91 — Ping dan refresh: perbaiki false negative, jujur soal penyebab, dan jangan kunci user di layar yang membeku, 15-Okt-2026

### Permintaan
Comparer dengan Clash FX: setelah subscribe `openproxylist`, Clash FX menampilkan
lebih banyak akun, dan sebagian yang di sana hidup tapi di FreePN mati semua saat
ping. Dugaan user: "sistem ping dengan mengaktifkan internet mungkin terlalu
strict, mungkin bisa dibuat longgar dengan hanya ping ke google.com". Plus dua
keluhan: pesan error selalu menyalahkan kredensial, dan segarkan per baris sangat
lama.

### Ringkasan temuan (semua diverifikasi ke kode, bukan asumsi)

| Dugaan | Kenyataannya |
|---|---|
| URL uji terlalu ketat | Bukan. `gstatic generate_204` sudah target yang benar (204, tanpa body, CDN). Mengganti ke google.com tidak memperbaiki apa pun; kalau HTTPS malah menambah satu handshake TLS lagi ke budget yang sama. |
| Jumlah node berbeda | Parser bukan penyebab besarnya. Feed `openproxylist` diuji langsung: 150 link -> 148 ke-parse -> 145 setelah dedup. Yang hilang cuma 5 — tapi 3 di antaranya akibat dedup yang kelewatan, dan ada bug grpc yang bikin node gagal saat connect. |
| Ping terlalu strict | **Betul — dan ada empat penyebab terpisah yang lebih besar daripada timeout-nya sendiri.** |

### Empat false negative yang ditemukan

1. **`URLSession.shared` membatasi 6 koneksi per host.**
   Semua request probe menuju `127.0.0.1:<clashPort>` yang sama, jadi bawaan
   `httpMaximumConnectionsPerHost = 6` membatasi seluruh probe — berapa pun
   konkurensi yang diminta `CPUGovernor`. Sisanya MENUNGGU di antrean koneksi
   sambil **memakan `timeoutIntervalRequest` sendiri**, lalu timeout sebelum
   sing-box pernah mencoba node itu. Dicatat sebagai "tanpa internet" padahal
   core-nya tidak pernah attempting. Ini sebab besarnya hasil probe yang kosong
   sementara sebagian node jelas hidup.

2. **DNS probe lewat direct, DNS connect lewat proxy.**
   `SingBoxConfigBuilder.swift:45` (connect) memakai `proxy-dns` dengan
   `detour: "proxy"`; `:113` (probe) memakai DoH ke 8.8.8.8 dengan
   `detour: "direct"`. Jadi probe WAJIB bisa menjangkau 8.8.8.8:443 tanpa proxy —
   dan banyak jaringan memblokir atau memperlambat DoH langsung. Akibatnya
   setiap node ber-hostname (~30%) gagal di probe tapi berhasil saat connect.
   Sekarang keduanya memakai resolver sistem.

3. **Core probe yang mati = ratusan node divonis mati.**
   `verifyInSession` tidak pernah mengecek `runner.isRunning`. Kalau proses core
   tumbang di tengah sesi, setiap `URLSession` berikutnya gagal dengan
   "connection refused" dalam ~1 ms — dan semuanya dicatat `.noInternet`. Satu
   core yang tumbang menghasilkan vonis "mati" untuk ratusan node sekaligus.

4. **Nol retry, dan timeout 4 dtk untuk seluruh rantai.**
   Dial + handshake proxy + TLS (plus uTLS `chrome` untuk REALITY) + HTTP lewat
   tunnel semuanya harus muat dalam 4 detik. Handshake dingin Hysteria2/QUIC dan
   ws+TLS belum selesai dalam itu, dan sekali gagal vonisnya permanen.

### Yang diubah

**Ping**
- `RealDelayTester.probeSession`: `URLSession` khusus dengan
  `httpMaximumConnectionsPerHost = 0`. Governor yang menentukan berapa banyak
  yang hidup, bukan angka bawaan URLSession.
- Timeout dua tahap: tahap 1 dengan `internetCheckTimeout` 4 -> **6 dtk**,
  tahap 2 hanya untuk yang gagal dengan `internetCheckRetryTimeout` **14 dtk**.
  Kredensial dan config yang ditolak TIDAK dicoba ulang — tidak berubah dalam
  beberapa detik. `ProbeFailure.worthRetrying` yang memutuskan.
- `runner.isRunning` diperiksa tiap hasil masuk. Kalau core mati, hasil itu dan
  seluruh sisa dilepas sebagai `.skipped` — bukan `.noInternet` — supaya vonis
  lama tidak dirusak oleh kegagalan infrastruktur.
- `ProbeFailure` (enum: `auth`, `timeout`, `unreachable`, `dns`, `rejected`,
  `coreDown`, `unknown`) + `ProbeFailure.classify` memetakan pesan error
  sing-box. Dulu `let (data, _)` membuang status code DAN body, jadi
  "authentication failed" dan "network is unreachable" nilainya sama persis.
  Semua request probe menuju loopback, jadi error lapisan koneksi dipetakan ke
  `coreDown` — itu bukti tentang core, bukan tentang node.
- `PingResult.failure` menyimpan sebabnya (decoder toleran, field lama tetap
  terbaca). `ProbeVerdict` mendapat kasus `failed(_)` yang membawa
  `ProbeFailure`, sementara `.noInternet` tetap ada untuk kompatibilitas.
- Sasaran `Ping All` (`AppState.pingTargets`) menghormati filter cari/tipe/sumber
  tapi **tidak** menghormati "Sembunyikan yang mati". Sebelumnya filter itu
  mengeluarkan node mati dari `filteredNodes` — yang persis daftar sasaran —
  sehingga vonis yang salah mengukuhkan dirinya sendiri selamanya.

**Connect**
- `connect()` tidak lagi menolak node yang vonis ping-nya mati. Dulu
  `isKnownDead` jadi gerbang: satu klik ditolak tanpa percobaan. Vonis ping
  tetap berguna (Quick Connect tidak memilihnya duluan, UI tetap menandainya);
  hanya penolakan paksa yang dihapus. User yang menekan Sambung sudah memberi
  persetujuan — menolak keputusan eksplisit demi hemat beberapa detik adalah
  kesombongan, bukan layanan.
- `error_node_dead` tidak lagi menyebut "kredensial salah" sebagai penyebab
  tunggal, dan `error_node_no_internet` tidak lagi menyuruh memilih server lain
  tanpa opsi memaksa.

**Refresh per sumber**
- `SourceResolver` menghasilkan sampai **15 kandidat** untuk openrunner.net (7
  hari x WIB+UTC + URL asli). Semuanya dicoba BERURUTAN dengan timeout 15 dtk ->
  **225 detik**, ditambah `enrichCountries()` 45 dtk. Sekarang: kandidat pertama
  tetap dapat timeout penuh, sisanya 5 dtk, ada **plafon total 45 dtk per
  sumber**, dan HTTP 401/403/404/410 langsung berhenti (path-nya memang salah,
  mencoba tanggal lain tidak akan mengubahnya).
- `AppState.refreshTask` + `cancelRefresh()`. Sebelumnya `Task.isCancelled` di
  `fetchOne` adalah kode mati karena tidak ada yang pernah membatalkan.
- `refreshProgress` ("Trying link 3 of 15…") dan pita progres dengan tombol
  batal di `SourcesView`. Overlay lama menelan seluruh input layar selama
  refresh dan tidak punya tombol batal — satu-satunya jalan keluar adalah
  menutup app.
- `isRefreshing` diturunkan SEBELUM `enrichCountries()`. `defer` di dalam fungsi
  yang `await` enrichment baru berjalan setelahnya, jadi spinner tetap berputar
  selama pekerjaan yang sama sekali bukan refresh.

**Parser & dedup**
- VLESS gRPC: nama service dibaca dari query `serviceName`/`service_name`. Versi
  lama hanya membaca `path`, jadi config menghasilkan `"service_name": ""` —
  node itu dijamin ditolak saat connect, sementara di Clash FX jalan. Feed
  openproxylist sendiri banyak memakai `type=grpc&serviceName=`.
- VLESS: `alpn` diteruskan (`TLSOptions.alpn`, field baru dengan decoder
  toleran).
- `dedupID` sekarang membedakan `transportHost` (header Host WS), `flow`,
  `realityPublicKey`/`realityShortId`, `cipher`, dan `alterId`. Di feed nyata
  ada dua link `kclx.eu.org:443` dengan uuid sama yang hanya beda header Host —
  dua rute CDN berbeda — dan versi lama meringkasnya jadi satu node.
- **Kompatibilitas dijaga**: field baru hanya masuk hash kalau terisi, jadi node
  tanpa field baru menghasilkan string hash yang PERSIS sama dengan versi lama
  dan `favorites.json` milik user tidak ikut rusak.
- `ClashYAMLParser`: `e["alterId"]` selalu `nil` karena semua key disimpan
  `.lowercased()` — lookup harus `e["alterid"]`. Bug ini ada sejak awal.
- `malformed` di kedua parser: entri ber-skema yang didukung tapi gagal di-parse,
  serta entri Clash tanpa field wajib, sekarang DIHITUNG sebagai korup. Sebelumnya
  `continue` polos tanpa penghitung, jadi angka di kolom "Keterangan" tidak pernah
  cocok dengan isi feed dan user tidak bisa tahu ada yang hilang.

### Perilaku yang dikunci

| Keadaan | Sebelum | Sesudah |
|---|---|---|
| Probe dengan 20 node konkuren | paling banyak 6 yang jalan | semua sesuai governor |
| Node lambat (QUIC/REALITY/ws+TLS) | vonis mati permanen di 4 dtk | coba 6 dtk, lalu 14 dtk |
| Core probe tumbang di tengah | ratusan node divonis mati | sisanya `.skipped`, vonis lama utuh |
| Gagal karena kredensial vs jaringan | selalu "kredensial salah" | dibedakan, tersimpan di `PingResult.failure` |
| "Sembunyikan yang mati" nyala | node mati tak pernah diuji ulang | tetap ikut diuji |
| Tekan Sambung di node mati | ditolak tanpa percobaan | dicoba, pesan error jujur |
| Segarkan per baris (openrunner) | 225 dtk, layar beku, tanpa batal | maks 45 dtk, ada progres + tombol batal |
| 404 di semua kandidat tanggal | 15 tries x 15 dtk | berhenti di kandidat pertama |

### Verifikasi
- `xcodebuild … build` bersih; `… test` **423 tes, 0 kegagalan** (dari 395).
- Tes baru (28): `ProbeFailureTests` (klasifikasi pesan error, `worthRetrying`,
  `coreDown` bukan bukti mati, round-trip + decode payload lama), `DedupIdentityTests`
  (ws host / flow / pbk / sid / cipher / alterId membedakan; hash node biasa
  tetap sama dengan versi lama), `MalformedEntryCountingTests` (entri tanpa
  server/password dan link rusak terhitung; skema asing tetap `unsupported`),
  `VlessGrpcServiceNameTests` (`serviceName`, kedua ejaan, ws tetap pakai `path`,
  alpn terbawa), `PingTargetScopeTests` (sasaran mengabaikan filter mati tapi
  menghormati filter lain).
- `bash scripts/check-localization.sh` -> key EN == ID. Key baru:
  `refresh_progress`, `refresh_cancel`; `error_node_dead` dan
  `error_node_no_internet` ditulis ulang di en + id.

### Yang SENGAJA tidak diubah

- **`AppConstants.testURL` tetap `gstatic generate_204`.** Mengganti URL tidak
  memperbaiki satu pun dari empat false negative di atas, dan HTTPS akan menambah
  satu handshake TLS lagi ke budget yang sama.
- **`nodeCount` vs `keptCount`.** Angka keduanya berbeda untuk feed aggregator
  (sebelum vs sesudah dedup lintas sumber) dan itu memang disengaja sejak D44 —
  "dipakai" bukan "terbaca".
- **Maksimal 300 outbound per sesi probe.** Membesarkan `sessionSize` mengurangi
  jumlah sesi, tapi config dengan ribuan outbound berat sekali bagi sing-box.

### D91 (lanjutan) — Ping All belum juga bisa dipakai: 21.965 node

user melaporkan setelah D91 masuk build: "fitur ping semua (dengan internet)
error, ping tidak muncul dan lama. kalau ping biasa normal dan cepat."

User benar. Semua perbaikan D91 benar secara lokal, tapi tidak ada satu pun
menyentuh biaya operasionalnya, dan itulah yang bikin fitur ini tidak bisa
dipakai sama sekali.

### Diukur, bukan ditebak

| Yang diukur | Angka |
|---|---|
| Node di `nodes.json` user | **21.965** |
| Config probe 300 outbound | 108 KB, `sing-box check` 0,06 dtk |
| Config probe 600 outbound | 267 KB, `sing-box check` 0,66 dtk |
| Clash API siap setelah `run` | **0,07 dtk** |
| `settleDelay` yang di-hardcode | **2,0 dtk** |
| Sesi yang dibutuhkan (300/sesi) | **73** |
| 100 node asli, tahap 1 (6 dtk, 32 konkuren) | 12,1 dtk — **50 hidup** |
| 100 node asli, tahap 2 retry (9 dtk) | 9,5 dtk — **10 diselamatkan** |
| Latensi node yang benar-benar hidup | 46 / 422 / **5.777** dtk |

Tiga fakta yang mengubah keputusan:

1. **Separuh node yang diuji benar-benar hidup**, dan yang paling lambat
   5.777 ms — jauh melewati timeout lama 4 dtk. Jadi kenaikan timeout D91
   memang dibutuhkan, bukan sekadar tebakan. Tapi kalau node hidup butuh ~6 dtk
   per percobaan, maka menguji 21.965 node memang tidak bisa selesai.
2. **73 sesi x 2 detik tidur = 146 detik terbuang.** Clash API sebenarnya siap
   dalam 0,07 dtk; `settleDelay` 2,0 dtk itu asal-usulan, bukan safety margin.
3. **Pengurutan hanya terjadi setelah SELURUH putaran selesai.** Itu sebab
   kolom Load menampilkan "—" untuk semua orang sepanjang itu, dan user tidak
   punya cara memastikan pengujiannya sedang bekerja.

### Yang diperbaiki

- **`settleDelay` 2,0 -> 0,25 dtk.** Keamanan tetap utuh: `startCore` sudah
  melakukan poll `apiHealthy()` sampai 10 dtk setelah `startAsync` selesai, jadi
  kesiapan API diperiksa dengan benar di sana. Hemat ~146 dtk untuk daftar
  20.000 node.
- **`sessionSize` 300 -> 600.** Config naik 108 -> 267 KB dan `sing-box check`
  0,06 -> 0,66 dtk, tapi jumlah sesi turun 73 -> 37. Yang mahal di sini biaya
  TETAP per sesi, bukan biaya per outbound.
- **`pingInternetBudget` = 5 menit.** Pengujian berhenti bersih setelah itu,
  sisa node dilepas sebagai **belum teruji** (bukan mati), dan UI memberi tahu
  berapa yang sempat diuji lewat `ping_budget_hit`. Hasil yang sudah didapat
  tetap disimpan. Berpura-pura sudah selesai lebih buruk daripada
  berhenti dengan angka yang jujur.
- **`internetCheckRetryTimeout` 14 -> 9 dtk.** Diukur: node hidup terlambat ada
  di 5,7 dtk, jadi 9 dtk sudah menutupnya dengan sisa yang cukup. Sisa 5 dtk
  hanya memperpanjang rounds.
- **Pengurutan berkala** setiap 2 detik selama Ping All berjalan
  (`sortByMeasuredLatency`, stabil lewat `enumerated()`). Inilah yang membuat
  angka yang sudah diperoleh langsung terlihat di tabel, alih-alih menunggu
  putaran yang tidak pernah selesai. Ia juga hanya menulis `nodes` kalau
  urutannya benar-benar berubah, karena `didSet` membuang semua cache turunan.
- **Tiga key localization yang hilang** (`probe_unavailable`,
  `probe_all_nodes_invalid`, `ping_budget_hit`). Dua yang pertama dipakai
  `InternetProbe` tapi tidak pernah ada di `Localizable.strings` — jadi yang
  tampil di layar adalah literal `probe_all_nodes_invalid`, dan itu dibaca
  sebagai error mysterious.

### Verifikasi lanjutan

- Diuji langsung ke node asli user dengan core sungguhan: 100 node, tahap 1 +
  retry = 21,5 dtk, **60 dari 100 terbukti hidup** (50 di tahap 1, 10 lagi
  diselamatkan oleh retry). Angka itu yang masuk ke `DECISIONS.md` — bukan
  estimasi.
- `… test` **423 tes, 0 kegagalan**.
- `ProbeSessionRestartTests` diperbarui: angka mutlak mengikuti `sessionSize`
  baru, plus assertion baru bahwa 21.965 node harus tertangani dalam <= 40 sesi.
- `bash scripts/check-localization.sh` -> key EN == ID.

## D92 — Instalasi benar-benar bersih: nol sumber sampai user memilih, 15-Okt-2026

### Permintaan
"buat apps nya itu bersih saat install, she'snya di sumber itu kosong, pokoknya
bersih".

### Yang benar-benar tidak bersih sebelumnya

`AppState.sources` punya nilai awal `VPNSubscriptionSource.builtIn()` — sepuluh
feed gratis yang aktif secara diam-diam di setiap instalasi baru. App membuka
dengan tabel server terisi, daftar langganan yang bukan pilihannya, dan refresh
otomatis yang mengunduh semuanya sebelum user melakukan apa pun.

Yang lebih buruk: feed yang dibintang di bawaan membuat `ServerSorter` mengunci
sumber itu ke urutan paling atas tanpa memandang kolom apa pun — jadi daftar
milik user yang baru terbuka sudah terurut oleh pilihan arbitrer. D61 pernah
memperbaiki sebagian kecilnya (tidak ada yang dibintang), tapi daftar itu sendiri tetap di-seed.

### Yang diubah

- **`VPNSubscriptionSource.defaultSources: [VPNSubscriptionSource] = []`** —
  satu-satunya definisi "instalasi bersih" di seluruh app. `AppState` dan tes
  sama-sama mengambil nilai ini, jadi kalau suatu saat daftar bawaan dikembalikan
  lagi, satu tempat berubah dan `testAppStartsWithNoSources` langsung gagal.
- **`builtIn()` dihapus**, diganti `curated: [(name, url)]` — daftar feed yang
  **ditawarkan**, bukan yang di-seed.
- **Layar Sumber yang kosong jadi titik masuk**, bukan kalimat pasif:
  - tombol "Tambah URL langganan",
  - grid "Atau mulai dari feed gratis:" berisi 10 chip satu-klik.
  - Tawaran yang sudah dipakai user **disaring** dari daftar — kalau tidak,
    ada tombol yang kalau ditekan justru ditolak sebagai duplikat.
- **`addSource(name:url:)`** Returns `VPNSubscriptionSource?`, bukan `Bool`.
  Chip tidak hanya menambah: ia langsung `refreshSource(id:)` setelahnya.
  Dulu (saat diuji pertama) sumber baru tertinggal berstatus **"Menunggu"** —
  user menekan "mulai dari feed ini" dan berakhir dengan pekerjaan yang harus
  ia tekan lagi. Sekarang satu ketukan selesai jadi server.
- **`refreshAll()` berhenti dini kalau tidak ada sumber aktif.** Tanpa itu,
  app baru yang kosong menjalankan satu putaran penuh `resort` +
  `enrichCountries` atas nol node, dan layarnya menampilkan "sedang bekerja"
  padahal tidak ada yang terjadi.

### Yang TIDAK diubah

`waitForHydration()` tetap ada. Akar masalah D66 (refresh jalan sebelum state
dari disk menempel) tidak hilang hanya karena seed-nya dihapus — daftar kosong
yang salah masih bisa menimpa data user kalau penulisan tidak menunggu
hidrasi.

### Perilaku yang dikunci

| Keadaan | Sebelum | Sesudah |
|---|---|---|
| Instalasi baru | 10 feed aktif, tabel server terisi | 0 file di disk, 0 sumber, 0 server |
| Refresh otomatis saat dibuka | mengunduh 10 feed | tidak jalan (tidak ada sumber aktif) |
| Layar Sumber kosong | "Belum ada sumber" (teks saja) | CTA + 10 tawaran satu-klik |
| Tekan tawaran feed | (tidak ada) | 1 ketukan -> tambah + unduh + tampil |
| Tawaran yang sudah dipakai | n/a | disaring dari daftar |

### Verifikasi

- **`… test` 430 tes, 0 kegagalan** (dari 423). Tes baru: `CuratedFeedTests`
  (URL unik, semua https, `defaultSources` kosong), `CleanInstallTests`
  (state awal nol sumber & nol node, `addSource` menolak duplikat/spasi/URL
  kosong, fallback nama-ke-URL, sumber baru tidak pernah dibintang, tawaran
  yang sudah dipakai tersaring).
- `BuiltInSourceTests` (D66) dihapus: akar masalahnya — daftar bawaan dipakai
  sebagai state — sudah tidak ada. `waitForHydration` tetap diuji di tempat
  lain.
- `D61RegressionTests.testNoBuiltInSourceIsPreStarred` ditulis ulang sebagai
  `testNoSourceIsPreStarredOnFreshInstall`, karena tidak ada lagi "sumber
  bawaan" untuk dibintang.
- **Dijalankan sungguhan, bukan hanya tes.** `/Applications/FreePN.app` dihapus,
  `Application Support/FreePN` dihapus, app dipasang ulang:
  - sebelum app dibuka: `Application Support/FreePN` **tidak ada sama sekali**;
  - setelah dibuka 10 detik: folder ada tapi **nol file** — app tidak
    menulis apa pun sampai ada yang benar-benar berubah;
  - satu ketukan pada chip "OpenProxyList": `1 dari 1 sumber daring`,
    `134 server terpakai`, status **Aktif** (bukan "Menunggu"),
    `148 terbaca · 134 dipakai · 2 korup`.
- Angka itu cocok dengan analisis offline feed yang sama di D91 (150 link ->
  148 ke-parse -> 145 setelah dedup; hari ini 134 dipakai + 2 korup), jadi
  hitungan "terbaca / dipakai / korup" sekarang benar-benar penjumlahan yang
  bisa dipertanggungjawabkan.
- `bash scripts/check-localization.sh` -> key EN == ID. Key baru:
  `sources_add_url`, `sources_suggested`.

## D93 — Target ping bisa dipilih, log ping, dan grup proxy manual, 15-Okt-2026

### Permintaan
Tiga hal sekaligus:

1. "utk ping dengan internet saya mau bisa di custom ping nya ke mana pakai menu
   drop down, entah ke google, cloudflare atau gstatic"
2. "saat ping di menu server wajib ada log, soalnya saya cek ping all dengan
   koneksi internet hasil semua akun mati tapi pas saya cek ping dengan tanpa
   aktifkan ping internet mode nyala semua, coba beberapa akun dan bisa internet
   normal"
3. "lalu di menu sorce tambahkan fitur untuk add manual proxy group, dan bisa
   tambahkan akun manual dari situ menggunakan link akun, baik itu trojan vmess
   dll, dan bisa juga manual dengan visual form lengkap"

---

### 1. Target ping yang bisa dipilih

**Masalah:** `AppConstants.testURL` satu konstanta. User yang jaringanannya
memblokir `gstatic` tidak punya pilihan apa pun — seluruh daftar server bisa
terlihat mati hanya karena satu host tidak terjangkau, dan tidak ada cara
membuktikannya selain menebak.

**Perubahan:**
- `PingTarget` (enum, app target — bukan `Shared/`, `L10n` tidak terlihat dari
  sana): `gstatic` (204 tanpa TLS, **default**), `cloudflare` (204), `google`
  (beranda, HTTP polos), dan `custom`.
- Urutan disengaja dari yang paling ringan: endpoint `generate_204` tidak
  mengembalikan body dan tidak butuh TLS, jadi satu handshake lebih murah.
  Memberi user opsi `https://` tanpa mengatakan ini akan menjadi jebakan:
  handshake kedua devour sebagian budget yang sudah ketat.
- `resolvedURL(custom:)` **tidak pernah** mengembalikan URL kosong atau rusak.
  URL yang tidak bisa di-parse ditolak `sing-box`, dan itu berarti SETIAP node
  terbaca "mati" karena tidak ada yang ditembak — pesan paling menyesatkan yang
  bisa muncul di app ini. Kalau custom kosong/rusak, jatuh ke gstatic.
- `AppSettings.pingTarget` + `pingTargetCustomURL`, keduanya decode dengan
  `decodeIfPresent` + `try?` dua lapis (kunci boleh tidak ada **dan** nilainya
  boleh tak dikenal). `settings.json` lama dan file dari versi lain tetap
  terbaca.
- `AppState.currentPingTargetURL` — satu titik kebenaran, jadi ping per baris dan
  Ping All tidak pernah menguji host berbeda dalam satu sesi.
- Dropdown di **Pengaturan → Langganan**, tepat di bawah "Ping cepat", dengan
  kolom URL yang hanya muncul saat mode Custom (dan diberi border merah kalau
  isiannya tidak valid, alih-alih diam-diam memakai gstatic).

### 2. Log ping

**Ini alat diagnosa, dan itu sebabnya ada.** Laporan "ping all bilang semua mati,
tapi ping cepat bilang hidup, dan beberapa yang saya coba jalan" adalah dua
klaim yang sama-sama tidak bisa dibuktikan tanpa catatan. Selama tidak ada
catatan, satu-satunya gerakan adalah mengganti hostname — yang tetap hanya
tebakan.

**Perubahan:**
- `PingLogEntry` — satu baris: waktu, node, protokol, host, **host tujuan yang
  dipakai**, latensi, dan verdict **beserta sebabnya**. Nama/protokol/host
  disalin saat itu juga, bukan diambil lewat index, supaya baris tetap bisa
  dibaca setelah node-nya dihapus.
- `PingRunSummary` — hasil satu putaran: berapa hidup, berapa yang ditolak core,
  berapa yang tidak sempat diuji, dan **penyebab kegagalan -> berapa kali**.
  Ringkasan inilah yang menjawab "300 timeout" ≠ "300 kredensial salah".
- Ring buffer 1.000 baris (`AppState.pingLogLimit`). Dibatasi: satu putaran atas
  20.000 node menulis 20.000 baris, dan log yang muat satu putaran terakhir sudah
  cukup.
- `.skipped` **tidak ditulis sebagai baris** — itu bukan hasil, itu "tidak
  sempat diuji", dan bisa ribuan baris sekali puts (node di luar jendela sesi).
  Yang dicatat hanya jumlahnya di ringkasan.
- `probe.lastRejectedCount` — berapa node yang ditolak core. Tanpa ini, "0 dari
  300 hidup" tidak bisa dibedakan dari "0 dari 12 hidup, sisanya core tolak".
- Baris `.session` untuk peristiwa yang tidak terlihat di verdict per node:
  mulai, selesai, batas waktu habis. "Core gagal start" dan "semua node ditolak"
  keduanya berakhir sebagai "tidak ada yang hidup", dan tanpa baris seperti ini
  keduanya terlihat sama saja dari sisi user.
- UI: tombol "Log ping" di kepala layar Server (nonaktif saat log kosong) →
  sheet dengan headline, **rincian per sebab sebagai chip**, lalu tabel
  (waktu, server, hasil, target), terbaru di atas. Tombol "Bersihkan".
- Log **direset di awal tiap putaran**, bukan ditumpuk: membandingkan dua
  putaran dengan konfigurasi berbeda (mis. target ping yang baru diganti) hanya
  menghasilkan kesimpulan yang salah.

### 3. Grup proxy manual

**Perbedaan dengan sumber biasa itu operasional, bukan kosmetik** — dan itulah
yang membuat field `isManualGroup` perlu ada:

- `url` kosong, jadi `SourceResolver` tidak punya apa-apa untuk dicoba. Tanpa
  flag, refresh akan tetap mencoba, gagal, dan menandai sumber `unavailable` —
  kontennya baik-baik saja tapi terlihat rusak.
- `refreshAll` **melewatinya** (loop hanya mengambil `isEnabled && !isManualGroup`).
- `refreshSource` dipersingkat: tidak ada yang diunduh, hanya angka yang
  dihitung ulang.
- Tombol refresh disembunyikan di baris grup manual; tombolnya membuka sheet.
- `keptCount`/`nodeCount` dihitung dari node yang ada, dan `lastUpdated` ikut
  disentuh — waktu perubahan user, bukan waktu feed fiktif.

**Dua jalur penambahan**, karena keduanya benar-benar dipakai:

- **Dari tautan** — `ManualNodeParser` memakai `ShareLinkParser`, parser yang
  sama dengan feed. Jadi base64, daftar multi-baris, dan tempel 20 link
  sekaligus dari catatan semuanya jalan, dan apa yang berhasil dibaca dari
  tautan manual selalu sama dengan apa yang Feed baca.
- **Form lengkap** — `ManualNodeDraft` untuk kasus link tidak ada sama sekali
  (server dibeli, atau tautannya kedaluwarsa). Semua protokol; kolom TLS/SNI/ALPN/
  insecure hanya untuk protokol yang punya arti; REALITY/flow hanya untuk VLESS;
  obfs/bandwidth hanya untuk Hysteria2. Menampilkan "public key" untuk
  Shadowsocks membuat form terlihat tidak tahu apa isinya.

**Validasi core itu wajib, bukan tambahan biar saja.** Config yang ditolak core
tidak hanya membuat node itu gagal — satu outbound buruk membatasi SELURUH
config probe, jadi satu node yang diketik dengan salah bisa mematikan
pengujian internet untuk ratusan node lain di jendela sesi yang sama (D61).
Divalidasi **bersama** (`prepareProbeConfig` all-or-nothing, bukan satu-satu).

Node yang ditolak karena duplikat (sudah ada di daftar, atau muncul dua kali
di teks yang sama) dibuang dengan pesan jelas — `resort` menghitung per identitas,
jadi masukkan dua kali menghasilkan satu server dan user mengira dapat dua.

Node manual masuk ke daftar global sebagai node biasa, jadi tabel Server, ping,
dan connect **tidak tahu bedanya** dengan node dari feed.

### Tes

**466 tes, 0 kegagalan** (dari 430). Yang baru, 36:

- `PingTargetTests` (9) — ketiga target punya URL valid; `generate_204` sengaja
  HTTP polos; custom kosong/tak dikenal/di-parse-aneh jatuh ke gstatic;
  `settings.json` lama & nilai enum tak dikenal tetap terbaca; round-trip.
- `PingLogTests` (7) — entri `.ok` membawa latensi; tiap `ProbeFailure` bertahan
  di barisnya; `skipped` tidak punya sebab; ringkasan mengelompokkan per sebab
  dengan yang paling sering dulu; log terpotong ke 1.000 dan yang terbaru
  bertahan; `clearPingLog`.
- `ManualGroupTests` (6) — grup punya URL kosong + flag; `sources.json` lama
  decode `false`; flag bertahan lewat encode; `refreshAll` melewati grup manual
  dan tidak menandainya gagal; node manual benar-benar muncul di daftar global
  **dan** terhitung di angka sumber; penghapusan memperbarui angka.
- `ManualNodeBuilderTests` (11) — trojan minimal; host/port/kredensial kosong
  ditolak; cipher SS tak dikenal ditolak; `method:password` digabung kalau
  kredensial tidak menyebut method, dan **tidak** diubah kalau sudah menyebut;
  REALITY tanpa `pbk` tidak ditandai REALITY; ALPN dipecah; nama kosong jatuh
  ke `host:port`; gRPC service name sampai ke `transportPath`; dua `Host:` WS
  berbeda menghasilkan node berbeda; flag kapabilitas per protokol.
- `ManualNodeParserTests` (4) — satu tautan; banyak tautan; blob base64;
  teks kosong & sampah ditolak.

### Verifikasi manual

Build + 466 tes + `check-localization.sh` (EN == ID). Verifikasi GUI tidak
diselesaikan — mesin sedang dipakai, dan menjalankan klik sintetis secara aktif mengganggu. Fungsinya tercakup tes; yang belum diuji dengan mata adalah
tampilan sheet log dan sheet grup manual.

---

## D94 — DNS loopback bikin SELURUH internet mati: regresi D83 yang hilang saat refactor, 15-Okt-2026

Laporan: setelah helper terpasang dan user menekan Connect, **keseluruh internet
mesin mati** — bukan cuma trafik VPN. Restart PC memulihkan jaringan, tapi
menyambung ulang selalu gagal lagi. ClashFX dengan akun yang sama jalan normal,
jadi akunya bukan salah node.

### Bukan split tunneling

Dugaannya (split tunneling) masuk akal: split tunneling adalah satu-satunya
fitur yang mengubah routing per-proses, dan "routing salah" memang bisa
menjatuhkan seluruh trafik. Tapi log core disprove-nya:

```
$ grep -c "DNS query loopback" /var/log/freepn-core-stderr.log
610
$ grep -o "lookup [a-z0-9.-]*:" /var/log/freepn-core-stderr.log | sort -u
lookup svp.byxl.biz.id:
```

610 kegagalan, **semuanya** satu hostname, dan semuanya mengulang kalimat yang
sama:

```
lookup svp.byxl.biz.id: (exchange4: lookup svp.byxl.biz.id:
  (exchange6: DNS query loopback in transport[proxy-dns] | ...))
```

Tidak ada satu pun baris tentang routing, process_name, atau process_path_regex.
Split tunneling tidak pernah ikut masalah ini.

### Penyebab: resolver outbound proxy menunjuk ke dirinya sendiri

`SingBoxConfigBuilder.configJSON` memberi outbound `proxy` resolver
`proxy-dns`. Tapi `proxy-dns` didefinisikan dengan `detour: "proxy"`:

```swift
outbound["domain_resolver"] = "proxy-dns"                                  // outbound proxy
["tag": "proxy-dns", "type": "https", "server": "8.8.8.8", "detour": "proxy"]  // server DNS
```

Maka me-resolve `svp.byxl.biz.id` berarti membangun koneksi ke
`svp.byxl.biz.id`, dan membangun koneksi itu harus lewat outbound `proxy` yang
butuh `svp.byxl.biz.id` ter-resolve dulu. Lingkaran tertutup tanpa jalan keluar.
sing-boxineesaya mendeteksinya dan menolAK setiap percobaan.

### Kenapa seluruh internet, bukan cuma trafik VPN

TUN memakai `strict_route: true` (D-spek: benar, supaya trafik tidak bocor via
en0). Konsekuensinya: default route **sudah diambil alih** di detik TUN
up, sebelum outbound `proxy` pernah berhasil satu kali pun. Selama outbound
itu gagal — dan di sini ia gagal selamanya karena loopnya struktural, bukan
sementara — tidak ada jalur direct yang tersisa. Akibatnya:

- Tiap koneksi gagal dengan error yang sama, 610×, tanpa henti.
- Tidak ada fallback: core tidak pernah tahu ia tidak berguna, jadi tidak
  pernah melepas route.
- Core tetap hidup dan port tetap melayani, jadi UI menampilkan **"sesi
  aktif"** sepanjang blackout.
- Route TUN yang yatim tidak dipulihkan saat app ditutup → butuh restart PC.
- TUN kedua milik tool lain (ClashFX) juga ikut gagal, karena default route
  sudah dikuasai proses yang tidak akan pernah berhasil.

Ini juga menjelaskan kenapa tidak terjadi lewat ClashFX: mihomo me-resolve
hostname server lewat resolver sistem, tidak pernah membuat lingkaran seperti
ini.

### Perbaikan

Satu baris, persis seperti D83:

```swift
outbound["domain_resolver"] = "direct-dns"
```

`dns.final` dan `route.default_domain_resolver` **tetap** `proxy-dns`, jadi
pencarian domain milik user sendiri tetap lewat tunnel dan tidak bocor ke ISP.
Hanya hostname node yang boleh di-resolve lewat resolver sistem — itu memang
kewajiban, bukan pilihan, karena nama hostnya harus diketahui sebelum tunnel
ada.

### Kenapa tes lama tidak menangkapnya

Tiga sebab, semuanya saling menutupi:

1. `sing-box check` **lolos** untuk kedua config. Lingkaran DNS bukan
   kesalahan sintaks, dan `check` tidak pernah menjalankan trafik.
2. `ConfigBuilderTests` hanya menguji resolver di config **probe**
   (`probe-dns`), tidak pernah di config **connect** — tempat regresinya
   tinggal. Probe sudah benar sejak D91, jadi tes itu tetap hijau sepanjang
   umur bug ini.
3. Gejalanya mirip sukses: core hidup, port melayani, UI bilang aktif.

### Bukti

Config lama vs baru, identik kecuali satu baris `domain_resolver`, dijalankan
dengan node `svp.byxl.biz.id` yang sama lalu di-`curl` lewat SOCKS:

| config | `sing-box check` | hasil koneksi |
|---|---|---|
| lama (`proxy-dns`) | OK | `DNS query loopback in transport[proxy-dns]` |
| baru (`direct-dns`) | OK | resolve berhasil → TCP connect → TLS handshake jalan |

(Kegagalan TLS di config baru karena credential dan SNI sengaja dummy pada
uji ini; yang terbukti adalah resolv-nya **selesai** dan koneksi sudah mencapai
lapisan TLS.)

### Tes regresi

`ConfigBuilderTests.testProxyOutboundResolvesNodeHostnameWithoutLoopback` —
memakai `domain_resolver` outbound `proxy` adalah `direct-dns`, `detour`
`proxy-dns` tetap `proxy` (mekanisme anti-bocor tidak boleh ikut dirusak), dan
`dns.final` / `default_domain_resolver` tetap `proxy-dns`.

Diverifikasi dua arah: fix dibalik → test gagal dengan pesan yang menunjuk tepat
ke baris penyebab; fix dikembalikan → **467/467 lulus**.

### Catatan operasional

Selama blackout, cara paling murah sebelum restart: `pkill -f
freepn/config.json`. Itu mematikan core, dan sing-box memulihkan route-nya saat
keluar — jadi jaringan kembali tanpa perlu restart. Tapi selama bug ini ada,
menekan Connect lagi akan menyebabkan blackout lagi, jadi ini hanya workaround,
bukan perbaikan.

---

## D95 — Edit sumber yang ada tapi bocor, dan split tunneling per-domain, 15-Okt-2026

Dua permintaan: (1) "di menu source bisa add manual group dan add akun, tapi
tidak bisa edit akun dari situ" dan (2) "di split tunneling sekarang kan apps,
tambahkan support domain".

Yang menarik: pada (1) user salah duga. Fitur edit sudah ada sejak **D59** —
ada tombol pensil di baris, ada `AddSourceView(editing:)`, ada
`AppState.renameSource`. Yang tidak ada adalah edit yang **berfungsi**. Tiga bug di bawah
menjelaskan hampir semuanya.

## Bagian 1 — Edit sumber: fiturnya ada, isinya bocor

### Bug 1 — Sakelar bintang dibuang diam-diam

`AddSourceView` menampilkan `Toggle` bintang dengan label yang sama persis
dengan form tambah. Saat mode edit, `.onAppear` membacanya ke `@State
isStared`… lalu `renameSource(id:name:url:)` tidak punya parameter untuk itu.

Jadi: user menggeser sakelar, menekan Simpan, tidak terjadi apa-apa. Form-nya
terbuka, kelihatan benar, tombolnya aktif — persis gejala "tidak bisa edit".
Perbaikan: `renameSource(..., isStarred: Bool? = nil)`.

Opsional, bukan `Bool`, karena ada 4 pemanggil lama yang tidak peduli bintang;
`Bool` memaksa semuanya berubah demi satu kasus.

### Bug 2 — Grup manual mustahil di-rename

Ini yang paling parah, dan tidak terlihat dari kode mana pun yang dibaca
sekilas. `Button` Simpan punya `.disabled(!isValidURL(url))`. Grup manual
disimpan dengan `url: ""` → `isValidURL("") == false` → **tombol Simpan
selalu mati**. Satu-satunya jalan untuk mengganti nama grup manual tidak pernah
bisa dipakai.

Kolom URL sekarang disembunyikan untuk grup manual (bukan dinonaktifkan —
kolom yang selalu kosong cuma menambah pertanyaan), dan aturan `.disabled`
bercabang: grup manual butuh nama, sumber biasa butuh URL valid.

### Bug 3 — Edit tanpa penjagaan duplikat

`hasSource(url:ignoring:)` sudah ada dan sudah diuji, tapi form edit tidak
memanggilnya. Hasilnya user bisa menyimpan URL milik sumber lain → dua entri
untuk satu feed, persis D66, lewat pintu yang tidak dijaga. Perbaikannya
satu baris: `state.hasSource(url: url, ignoring: src.id)`. `ignoring:` wajib,
tanpa itu sumber yang sedang diedit selalu dianggap duplikat dirinya sendiri.

## Bagian 2 — Split tunneling per-domain

Empat daftar, bukan satu: `inclusiveApps`/`exclusiveApps` +
`inclusiveDomains`/`exclusiveDomains`. App dan domain **berbagi mode** yang
sama — user memilih "terdaftar = lewat VPN" sekali, lalu mengisinya dengan
keduanya — tapi **bukan satu daftar `[String]`**, karena keduanya berakhir jadi
rule sing-box yang berbeda dan satu daftar tidak bisa mengeluarkan dua rule
tanpa menebak mana yang mana.

### Keputusan 1 — `domain_suffix`, bukan `domain`

Sejak sing-box 1.9, `domain_suffix` tanpa awalan titik cocok dengan
`(domain|.+\.domain)`. Jadi `bank.com` otomatis menutup `bank.com` **dan**
`www.bank.com` — persis yang dimaksud user saat mengetik satu domain. Tidak
perlu dua entri, dan tidak perlu UI "termasuk subdomain?".

### Keputusan 2 — WAJIB rule sniff, dan hanya kalau ada domain

Ini yang tidak terlihat dari dokumentasi saja. Di TUN, macOS sudah
me-resolve nama host-nya sendiri lewat DNS router, jadi yang sampai ke
sing-box hanya **IP mentah**. Tanpa nama host, `domain_suffix` tidak punya
apa pun untuk dicocokkan — config-nya lolos `sing-box check`, core hidup, UI
bilang aktif, dan aturannya **tidak pernah menyala**.

Perbaikannya rule action `{"action": "sniff"}` (bukan `sniff: true` di
inbound — yang itu sudah deprecated dan memicu WARN, dan `check` di project ini
memperlakukan WARN sebagai kegagalan). Dua syarat agar tidak ada yang berubah
untuk user yang tidak memakai fitur ini:

1. **Hanya saat `domains` tidak kosong.** Tanpa domain, tidak ada yang butuh
   sniff dan config byte-per-byte sama seperti sebelumnya. Sniff membaca
   paket pertama setiap koneksi sebelum routing diputuskan — overhead nyata,
   dan tidak boleh diimposisikan pada orang yang tidak mencentang satu pun
   domain.
2. **Setelah rule anti-loop** (`process_name … direct`), supaya trafik FreePN
   sendiri dan koneksi core ke server proxy tidak ikut membaca paket.

### Keputusan 3 — Rule domain selalu terakhir

Rule IP privat dan rule host/IP server proxy harus menang lebih dulu. Kalau
domain didahulukan, domain yang didaftarkan user bisa ikut mencengkeram
koneksi ke server VPN dan membuat routing loop — **persis D94**, yang
mematikan seluruh internet mesin. Urutannya dijaga tes, bukan Disclaimer.

### Keputusan 4 — `replaceActiveDomains` terpisah dari `replaceActive`

`replaceActive` **sengaja** mengosongkan daftar lawannya (`inclusiveApps = []`
saat mode eksklusif). Kalau domain ikut lewat fungsi itu, satu `Save` sudah
menghapus seluruh pengaturan domain tanpa jejak. Dua fungsi, dua pemanggilan.

### Keputusan 5 — Normalisasi ada di builder, bukan di UI

`https://Ads.Example.com/path`, `*.example.com`, `.example.com`, dan
`Example.COM.` semuanya berakhir sebagai `ads.example.com`. Kalau tidak,
mereka jadi empat entri dan empat "aturan sama" yang tidak saling cocok.
Normalisasi terjadi saat user menekan tombol Tambah, **bukan saat Save** —
chip harus menampilkan bentuk yang sama persis dengan yang akan ditulis ke
`split.json`, kalau tidak app terlihat salah pada dirinya sendiri.

`decodeIfPresent` untuk key baru, dan domain rusak di `split.json` dibuang
satu per satu — bukan satu `throw` yang menghapus seluruh pengaturan.

### Keputusan 6 — Entri riwayat domain punya teks sendiri

`describe()` untuk entri domain tidak boleh memakai teks entri app: yang satu
menyebut `process_path_regex` dan "proses anak seperti curl tidak ikut cocok",
yang tidak ada hubungannya sama sekali dengan domain. User akan mencari
matcher yang tidak pernah ditulis dan menyimpulkan split domain-nya rusak.
`Entry.isDomain` membedakan keduanya; `diff` dipanggil DUA KALI dari UI, bukan
satu panggilan gabungan.

### Bug yang saya buat sendiri, dan tertangkap test

`normalizeDomain` menolak `bank.com`. Penyebabnya satu karakter: himpunan
karakter yang diizinkan tidak memuat titik — padahal titik justru satu-satunya
tanda pengenal domain. Gejalanya: setiap domain ditolak, tidak ada satu pun rule
yang muncul, dan `isBypassAll` salah vonis mode inklusif. 7 tes gagal sekaligus
dan menunjuk tepat ke baris itu.

## Verifikasi

- **508/508 tes lulus** (dari 467; +41 tes baru).
- `SingBoxValidationTests` + `SplitDomainValidationTests` menjalankan
  `sing-box check` **sungguhan** untuk config domain eksklusif, inklusif, dan
  40 domain sekaligus: exit 0, **0 WARN**.
- `check-localization.sh` EN == ID.
- 17 tes `SplitChangeLogTests` lama **tidak berubah** — teks entri app masih
  sama persis, dan ada tes baru yang menjaganya agar tetap begitu.
- Regression guard diverifikasi **dua arah**: rule sniff dihapus → tes gagal
  di baris yang tepat; `hasAnyActiveSelection` dikecilkan → 2 tes gagal.
  Sesudah dikembalikan, 508/508 hijau lagi.

### Yang belum diverifikasi dengan mata

Pencocokan domain di TUN **end-to-end** tidak diuji di mesin ini. Membuktikannya
memerlukan menjalankan TUN dengan `auto_route: true`, yang persis yang
menyebabkan blackout internet di D94 dan butuh restart PC. Yang diverifikasi:
sintaks config diterima `sing-box check` tanpa WARN, urutan rule benar, dan
mekanisme sniff sesuai perilaku sing-box yang terdokumentasi.

Kalau user menemukan domain tidak menyala padahal config-nya sudah benar, itu
area pertama yang harus dicurigai — bukan daftar domain-nya.

## Catatan operasional

Untuk user: aturan baru **hanya aktif setelah reconnect**, sama seperti
aturan app. Ini sudah tertulis di panel riwayat (D87).

---

## D96 — Tiga keluhan satu laporan: daftar app hilang, ping berbohong, dan node manual tidak bisa diedit, 15-Okt-2026

Laporan (empat keluhan sekaligus): (1) "split tunneling apps tidak terbaca",
(2) "akun sudah ditambah tapi tidak bisa konek, padahal di ClashFX normal",
(3) "sudah minta fitur edit akun, masih belum bisa", (4) "ping normal semua,
anehnya tidak bisa konek".

Yang membuat ininon-trivial: **(1) adalah regresi yang saya buat sendiri di
D95, beberapa jam sebelumnya.** Dan (4) ternyata bukan bug yang terpisah —
itu terbentuk karena ping cepat memang berbohong, dan itu menjelaskan kenapa
(2) bertahan karena user percaya diri sendiri.

## Bagian 1 — Daftar app hilang total: regresi D95

### Gejala

Split → daftar aplikasi kosong, padahal 114 app di `/Applications` dan 39 di
`/System/Applications`. Scan-nya sendiri benar; tidak ada satu pun baris yang
menyebutkan pemindaian gagal.

### Penyebab

Layar Split adalah `VStack` dengan banyak section **tinggi tetap** (banner,
modeCards, changeLogPanel, filterBar, footer) dan `table` — satu-satunya view
lentur — yang hanya punya `.frame(maxHeight: .infinity)` dan **tidak punya
minimum**.

D95 menambahkan `domainPanel` yansebesar ±134 pt: header dua baris + baris
input + baris pesan. Begitulah total tinggi sibling melewati tinggi window,
`ScrollView` di `table` diremas sampai **0 piksel**. User melihat "tidak ada
aplikasi" — dan tidak ada satu pun pesan yang menyebut tata letaknya, karena
kenyataannya daftar itu ada, cuma tidak punya tinggi.

Yang membuatnya lolos ke build: tidak ada tes layout di project ini, dan tes
tes yang ada semuanya murni-logika. Tidak ada yang mengukur tinggi.

### Perbaikan

1. `domainPanel` jadi **satu baris** (ikon + label + kolom + tombol + jumlah),
   ~134 pt → ~52 pt. Baris kedua (chip domain) baru muncul kalau memang ada
   domain.
2. `table` dapat `.frame(minHeight: 240, ...)`. Ini jaminan, bukan perbaikan
   kosmetik: 240 ≈ 7–8 baris, cukup untuk membuktikan pemindaian bekerja,
   dan tidak bisa diremas lagi oleh section apa pun yang ditambahkan nanti.

## Bagian 2 — Ping cepat berbohong ( Complaint 4, dan penyebab (2))

### Bukti

`settings.json` user: `fastPing = true`. Lalu:

```
telekom.byxl.biz.id   port 443 TCP: succeeded
biznet.byxl.biz.id     port 443 TCP: succeeded
svp.byxl.biz.id       port 443 TCP: succeeded
```

Jadi ketiganya hijau. Tapi probe jujur (saya jalankan sendiri dengan config
yang sama persis, di luar FreePN) melaporkan ketiganya gagal:

```
{"message":"An error occurred in the delay test"}   ×3
```

### Akar masalahnya

Mode ping cepat mengganti pengukuran end-to-end dengan handshake TCP, dan
`ServerPingOutcome.aliveUpperBound` dipetakan menjadi:

```swift
PingResult(webLatencyMs: ms, internetOK: true, approximate: true)
```

`internetOK == true` berarti **"terbukti bisa akses internet"**. Tapi handshake
TCP hanya membuktikan ada yang menjawab di port itu. Selisih itu menjalankan tiga hal sekaligus:

1. **Badge hijau.** `LatencyCell.tint(ms)` memakai logika warna yang sama
   untuk angka `approximate` dan RTT terukur. Satu-satunya pembeda adalah
   sufiks "≤" berwarna abu-abu di ujung baris yang sudah padat — pada skala
   cell itu, satu angka hijau + "≤" abu-abu dibaca sama dengan "93 ms" biasa.
   Membaca "hijau" itu wajar; bukan salah user.
2. **`quickConnectChoice` memilih node itu.** AppState:1119 menyaring
   `internetOK == true` sebagai tier **verified**, lalu mengambil yang tercepat.
   Jadi Quick Connect secara aktif memilih node yang paling cepat tapi tidak
   bisa dipakai.
3. **`topByLatency` menghitungnya sama dengan node terukur.**

Semuanya berasal dari satu klaim yang berlebihan di satu baris.

### Perbaikan

```swift
case .aliveUpperBound(let ms):
    return PingResult(nodeID: nodeID, webLatencyMs: ms, internetOK: nil, approximate: true)
```

`nil` = "belum diverifikasi", dan itu memang statusnya: angka batas atas tetap
disimpan untuk mengurutkan, tapi tidak pernah diklaim sebagai bukti.
`isDeadEnd` tetap `false` — port tertutup itu bukti yang sah, jadi connect ke
node port-terbuka **tidak** diblokir. Yang hilang cuma klaim palsu.

Ditambah dua pengaman tampilan, karena `nil` saja tidak menutup celah baca:

- **Warna**: `approximate` tidak boleh dapat hijau sama sekali. Diturunkan satu
  tingkat (`textSecondary`), jadi "seperti RTT bagus" mustahil terjadi walau
  user mengabaikan semua penanda lain.
- **Latar + ikon + tooltip**: badge dapat latar kusam, ikon berbeda, dan
  `help` yang menjelaskan arti sebenarnya ("handshake TCP membuktikan portnya
  menjawab, bukan bahwa node ini bisa memproksi").

- **`topByLatency`**: tier 0 (terukur) kini menuntut `bestMs != nil && !approximate`.

### Tes lama yang mengarang bug ini

`ValidatorPingTests.testAliveUpperBoundIsFlaggedNotMeasured` pernah meng-asersikan
`internetOK == true` untuk `aliveUpperBound`. Tes itu **mengodekan kekeliruan
yang tepat sedang kita perbaiki** — alasan itu penting: tes hijau tidak berarti
kebenaran kalau yang diuji memang salah. Yang dijaga tes itu (bukan dead end,
ditandai `approximate`) tetap dijaga; hanya klaim `internetOK` yang dikoreksi.

## Bagian 3 — Node manual tidak bisa diedit

`ManualGroupView` tidak punya jalur edit sama sekali — nol `pencil`, nol
`editing`. Yang bisa dilakukan hanya tambah dan hapus. Padahal node manual
adalah **satu-satunya** tempat user memperbaiki node langganan yang rusak.

Ini yang menjawab keluhan (3): "edit akun" yang dimaksud adalah edit **node**, karena
password adalah field node, bukan field sumber. Sumber memang sudah bisa
diedit sejak D95, tapi `sources.json` user berisi hanya satu manual group —
tidak ada akun subscription sama sekali.

### Dua keputusan yang tidak terlihat dari kode

**1. `ManualNodeDraft(node:)` — bolak-balik, bukan form kosong.**

Form kosong yang "terlihat berisi" menghasilkan node tanpa SNI/credential.
Kredensial yang panjang lebih mudah diketik ulang dengan benar daripada
disalin-salin, dan salah ketik satu huruf produces node yang gagal dengan
pesan yang sama sekali tidak menunjuk ke form. `testEveryProtocolSurvivesRoundTrip`
membandingkan draft→node→draft untuk semua protokol.

Detail yang mudah terlewat: `upMbps`/`downMbps` `nil` berarti "pakai default
core", dan itu **bukan** sama dengan `"0"`. Kalau draft menyimpannya `"0"`, user
yang tidak sengaja menyentuh field itu akan mengunci bandwidth node ke nol —
node yang tadinya jalan menjadi tidak jalan, dan penyebabnya tidak terlihat di
mana pun. Ada tesnya.

**2. ID harus dipaksa kembali — dan ternyata `id` itu content-derived.**

Ini tidak terduga saat implementasi. `ProxyNode.dedupID` menghitung ID dari
isi node, jadi **mengubah password atau SNI otomatis mengubah ID**. Tanpa
penanganan, satu perbaikan SNI akan membuang `ping`, `favorites`, dan
`selectedNodeID` milik user — semuanya menunjuk id yang sudah tidak ada.

Jadi `updateManualNode` memaksa ID asli kembali. Yang tetap dijaga: ID itu tidak
boleh bertabrakan dengan node lain, karena dua node dengan ID sama membuat
`first(where:)` ambigu di mana-mana — kalau isi hasil edit sekarang identik
dengan node lain di grup itu, itu memang duplikat dan harus ditolak.

Ping lama **dibuang**, bukan dipertahankan: kredensial atau SNI yang berubah
berarti hasil ukur yang lalu diukur untuk konfigurasi yang berbeda. Memakainya
berarti menampilkan "93 ms" untuk node yang belum pernah diuji.

## Yang sebenarnya terjadi pada connect — bukan bug FreePN

Tiga node user adalah pola CDN fronting: `server: *.byxl.biz.id`, SNI
`opencode.ai`, WebSocket Host tetap `*.byxl.biz.id`. Config yang benar-benar dipakai saat connect:

```
tls: { enabled: true, insecure: false, server_name: "opencode.ai" }
```

Error: `tls: failed to verify certificate: x509: "Cloudflare" certificate is
not standards compliant`.

Saya reproduksi **di luar FreePN sepenuhnya** — config sing-box tulisan tangan,
tanpa TUN, tanpa helper, tanpa rule routing — dan hasilnya sama persis:

```
$ curl --socks5-hostname 127.0.0.1:28295 https://api.ipify.org   → exit 97
ERROR: tls: failed to verify certificate: x509: "Cloudflare" certificate is not standards compliant
```

Jadi node-nya memang tidak bisa dipakai seperti yang dikonfigurasi — SNI-nya
tidak cocok dengan sertifikat yang drowolkan server. ClashFX berjalan karena
ia memakai node/subscribsi yang berbeda, bukan karena FreePN salah.

Yang bisa dilakukan user: **sekarang** bisa diedit (Bagian 3) — ganti SNI,
atau centang `allowInsecure`. Tapi memperbaiki SNI bukan sesuatu yang bisa
ditebak app-nya; kredensialnya dari penyedia.

## Verifikasi

- **529/529 tes lulus** (dari 508; +21 tes baru: 11 `ManualNodeEditTests`,
  10 `FastPingHonestyTests`).
- 1 tes lama diperbarui karena **mengodekan bug yang diperbaiki**, bukan karena
  perilakunya salah.
- `check-localization.sh` EN == ID.
- Release build app + helper sukses.

### Yang belum diverifikasi dengan mata

Tampilan daftar app setelah panel dipipihkan, dan sheet edit node, belum
saya lihat berjalan. Tes tidak mengukur tinggi, dan tidak ada harness view
test di project ini. Kalau daftar app masih terasa sempit, `minHeight` di
`table` adalah satu-satunya angka yang perlu diubah.

---

## D97 — "Sudah ganti SNI tetap tidak konek": diagnose yang tidak achievable, dan log yang tidak pernah dibaca, 15-Okt-2026

Laporan: "saya sudah ganti sni sesuai nama server tetap tidak bisa konek", dengan
log connect lengkap. Sesi sebelumnya (D96) sudah memperbaiki ping yang berbohong dan
menambahkan fitur edit node — jadi dua hal itu **sudah bekerja**: log menunjukkan
`server_name = svp.byxl.biz.id` di config yang benar-benar dipakai, yang berarti
edit node menyimpan dengan benar.

### Yang sebenarnya terjadi pada node itu

Bukti-bukti ini semua di luar FreePN, jadi tidak bisa disalahkan ke routing, TUN,
helper, atau DNS:

```
$ openssl (via python) svp.byxl.biz.id:443
subject = C=US, CN=Cloudflare
issuer  = … CN=Managed CA 301a7081932c7b69c18134bb47e9c80f
SAN     = (tidak ada sama sekali)
jumlah sertifikat di rantai: 1        # tanpa intermediate

SNI=opencode.ai  ->  ConnectionResetError [Errno 54] Connection reset by peer
GET /            ->  404
GET /ws          ->  404
GET /trojan      ->  400   (dengan header WS upgrade — jadi ada sesuatu di sana)
```

Tiga kesimpulan:

1. **Sertifikat tidak punya `subjectAltName`.** Go berhenti memakai CN sejak 1.15,
   jadi `x509: "Cloudflare" certificate is not standards compliant` bukan
   kebetulan — itu tepat apa yang Go bilang untuk sertifikat tanpa SAN. Mengganti
   SNI **tidak akan pernah** memperbaiki ini, karena yang dipresentasikan adalah
   sertifikat fallback Cloudflare, bukan sertifikat untuk nama itu.
2. **Rantai tidak lengkap** — leaf saja, tanpa intermediate. Itu sebab kedua
   (`unable to get local issuer certificate`).
3. **`/trojan` menjawab 400**, dan dengan `insecure: true` TLS-nya **lolos**,
   tapi handshake trojan/WS tidak pernah mendapat balasan — log debug berhenti
   di `outbound connection to api.ipify.org:443` tanpa error apa pun. Worker-nya
   tidak melayani path itu.

Jadi node tersebut memang tidak bisa dipakai seperti yang dikonfigurasi.
Perbaikannya (SNI benar atau `allowInsecure`) bergantung pada
**Workeryang quedado diploy**, bukan pada app. FreePN tidak bisa mengoreksinya —
dan tidak seharusnya menebaknya.

### Bagian yang memang salah: app tidak pernah membaca log core

Ini bug nyata, dan justru yang membuat diagnosisnya melingkar: tidak ada
informasi baru yang muncul di setiap percobaan.

Kasus di atas adalah: **core hidup** (`startCore: ok=true`), tapi tidak ada trafik
keluar. `ConnectionManager` mendeteksinya lewat `ExitIPChecker.viaCore` dan
menampilkan `error_node_dead`:

> "Penyebabnya bisa server mati, kredensial/usannya salah, atau jalur keluar dari
> node itu diblokir."

Tiga tebakan. Padahal **di detik yang sama** `/var/log/freepn-core-stderr.log`
sudah menulis sebabnya persis:

```
ERROR … tls: failed to verify certificate: x509: "Cloudflare" certificate is not standards compliant
```

Kenapa tidak pernah dipakai? `HelperService.coreStatus` hanya mengirim ekor log
**kalau core sudah berhenti**:

```swift
if runner.isRunning { reply(true, "running") }        // <- log dibuang
else { reply(false, runner.logTail()) }
```

Justru kasus yang paling perlu penjelasan-lah yang paling sering diabaikan,
karena sing-box tidak pernah keluar dari sana.

Dampak untuk user: tidak ada informasi baru setiap percobaan. SNI diganti → gagal
dengan pesan sama → ganti lagi → sama. Tanpa alasan yang bisa ditindaklanjuti,
satu-satunya jalan adalah membaca `/var/log` di Terminal.

### Perbaikan

1. **`coreStatus` selalu mengirim ekor log**, walau core hidup. Nilai `Bool` tidak
   berubah, dan semua pemanggil membaca nilai kedua hanya saat core mati — jadi
   tidak ada perilaku lain yang bergeser. Tidak menambah perintah XPC baru:
   menambah perintah baru berarti menambah permukaan helper root yang harus
   diaudit, untuk data yang sudah dikirim.

2. **`CoreFailureReason.from(_:)`** — murni, nonisolated, bisa diuji. Memilih satu
   baris yang paling menunjuk aksi dari ekor log, membersihkan prefix
   `ERROR[0000] [id 52ms]`, membuang kode ANSI, dan memotong yang kepanjangan.
   Kalau log tidak memberi apa-apa, ia mengembalikan `nil` dan pesan lama tetap
   dipakai — jadi ini tidak pernah membuat keadaan lebih buruk.

3. Pesan jadi dua bagian: heading baru + penyebab asli dari sing-box.

### Dua bug di dalam perbaikannya sendiri, tertangkap tes

**Pola ANSI ter-double-escape.** `\"\\\\u{1B}\\\\[[0-9;]*[a-zA-Z]\"` tidak
menghasilkan karakter ESC — yang masuk ke ICU regex adalah teks `\u{1B}`. Polanya
tidak pernah cocok, kode warna lolos ke layar, dan tes yang seharusnya menangkap
itu **tidak menangkap** karena asersinya salah (`!contains("[")` — padahal
`outbound/trojan[proxy]` memang mengandung `[`, jadi asersi itu mustahil benar).

**Deteksi ERROR dilakukan setelah `strip`.** Prefix `ERROR` sudah hilang saat
penilaian kelayakan, sehingga tidak ada baris yang pernah dianggap error dan pesan
generik selalu kembali tepat di kasus yang paling butuh penjelasan. Diperbaiki:
nilai kelayakan dinilai pada baris **mentah**, dibersihkan setelahnya.

Keduanya adalah kelas bug yang sama: log yang bentuknya benar tapi isinya salah dibaca,
dan tes yang hijau karena menguji hal yang salah.

### Verifikasi

- **537/537 tes lulus** (+8 `CoreFailureReasonTests`).
- Diuji dengan baris log **nyata** dari sesi user, bukan contoh karangan.
- `check-localization.sh` EN == ID.

### Yang tetap perlu diketahui user

Features yang sudah ada sekarang (D96) adalah alat yang tepat untuk kasus ini:
ubah SNI, atau nyalakan `allowInsecure` untuk node yang sertifikatnya memang
tidak valid. Tapi kalau handshake WS-nya tidak dijawab, tidak ada setelan di sisi
client yang akan membuatnya hidup — itu sisi server.

---

## D98 — Koreksi D97: node itu hidup, dan saya yang menyimpulkan terlalu cepat, 15-Okt-2026

D97 berakhir dengan kesimpulan: "node tersebut memang tidak bisa dipakai seperti yang
dikonfigurasi… tidak ada setelan di sisi client yang akan membuatnya hidup".

**Itu salah.** Useredition dengan bukti: "server tidak mati, dan bisa digunakan,
soalnya baru saya buat dan sudah tes". Dan memang benar — config yang berfungsi
sudah ada di mesin ini, di `~/.config/clashfx/clash-trojan-warp-only.yaml`.

### Yang saya lakukan salah

Saya menguji node itu dengan konfigurasi yang saya karang sendiri, lalu menyimpulkan
server-nya mati. Yang tidak saya lakukan adalah **membaca konfigurasi yang sudah
dibuktikan bekerja oleh user**. Padahal file itu ada di disk, 80 baris proxy,
tiga di antaranya persis node yang sedang saya vonis mati.

Membandingkan dua sumber yang sudah ada selalu lebih murah daripada menguji
kombinasi yang saya tebak.

### Bukti setelah membandingkan

Tiga node di config ClashFX — bedanya dari FreePN hanya di **satu** field:

```yaml
'skip-cert-verify': true
```

FreePN: `allowInsecure: false` di ketiga node. Itulah seluruhnya.

| uji | hasil |
|---|---|
| config ClashFX apa adanya | **BERHASIL** → `64.235.43.131` |
| node FreePN + `allowInsecure: true` | **BERHASIL** → `64.235.43.131` |

Passwordnya sendiri sudah benar semua di FreePN — user memperbaikinya lewat fitur
edit node D96. `fingerprint: chrome` tersimpan di data node tapi tidak pernah
emitted: `outboundJSON` hanya menambah `utls` di dalam `if tls.isReality`, dan
`isReality` butuh `realityPublicKey` non-kosong. Jadi config yang FreePN kirim
identik dengan config yang berhasil, begitu `allowInsecure` dinyalakan.

### Yang sebenarnya bisa dipelajari

1. **"Sertifikat tanpa SAN" bukan berarti server mati.** Go memang menolaknya,
   tapi di balik CDN-fronting itu **normal** — Cloudflare menyajikan sertifikat
   fallback kalau nama itu tidak punya sertifikat edge. Verifikasi dimatikan
   (`skip-cert-verify`) adalah cara kerja yang disengaja untuk pola ini, bukan
   tanda server mati. Saya membaca error verifikasi sertifikat sebagai bukti
   kebenaran server, padahal ia bukti **konfigurasi**, bukan kesehatan server.
2. **Saya punya file yang sudah membuktikannya dan tidak membukanya.** Tool yang
   ada di mesin adalah sumber jawaban yang lebih baik daripada hipotesis baru.
3. **D97 sendiri tetap bernilai.** App memang tidak pernah membaca log core saat
   core hidup, dan pesan generiknya memang tidak bisa ditindaklanjuti. Itu
   masalah nyata yang tidak bergantung pada node ini benar atau mati. Satu-satunya
   yang perlu dikoreksi: D97 menyimpulkan penyebabnya, padahal yang perlu
   exibição hanyalah cara mendapatkannya.

Yang tersisa dari perkiraan itu: yang perlu ditampilkan adalah penyebab dari log,
bukan kesimpulan dari saya.
