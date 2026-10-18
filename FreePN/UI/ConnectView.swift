import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Layar utama: tombol daya besar, log koneksi live, trafik,
/// ringkasan sumber, dan pratinjau server terbaik.
struct ConnectView: View {
    @EnvironmentObject var state: AppState
    /// Dipakai kartu "Subscription Sources" untuk melompat ke layar Sumber.
    /// Dioper dari `ContentView` supaya navigasi tetap satu arah (sidebar →
    /// layar), bukan lewat notifikasi.
    @Binding var selection: String?

    @State private var logText = ""
    @State private var logLines: [String] = []
    @State private var logUpdated = Date()
    @State private var logTimer: Timer? = nil
    @State private var logNotice = ""
    /// D83: status buka-tutup menu. dulu pakai `Menu` bawaan macOS.
    @State private var showOverflow = false
    /// Baris yang sedang di-hover, supaya panel punya sorotan seperti menu
    /// sungguhan (menu NSMenu lama juga punya, dan itu yang bikin transplantasi
    /// ke SwiftUI terasa pas — bukan sekadar daftar tombol).
    @State private var hoveredOverflowItem: String?

    /// Waktu ringkas untuk header panel. `Date.description(with: .current)`
    /// terlalu panjang ("2026-10-10 15:06:20.123 +0700") — di panel sempit
    /// string itu mendorong bagian kanan bar header keluar layar (bug "bar kanan
    /// hilang saat log dibuka"). Format pendek + truncation kedua-duanya.
    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .medium
        return f
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                banners
                topRow
                statsRow
                availableServersCard
                logPanel
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { reloadLog(); startLogTimer() }
        .onDisappear { stopLogTimer() }
    }

    // MARK: - Kepala halaman

    private var header: some View {
        ScreenHeader(greeting, subtitle: "connect_subtitle") {
            HStack(spacing: 10) {
                Button {
                    Task { await state.refreshAll() }
                } label: {
                    Label("action_refresh", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(GhostButtonStyle())
                .disabled(state.isRefreshing)

                overflowMenu
            }
        }
    }

    /// Menu `…` di kanan atas: aksi yang berlaku untuk seluruh data, bukan
    /// untuk satu kartu.
    ///
    /// D83 — SEBELUMNYA `Menu { } label: { }` dengan `.menuStyle(.borderlessButton)`.
    /// Di macOS itu ME-NYAWAKAN NSMenu sistem apa adanya: tinggi baris ~22pt,
    /// system font, warna bawaan, dan tidak nyambung dengan kartu dark navy
    /// di sekitarnya. Persis yang dikeluhkan user: "hanya menu kecil bawaan
    /// menu mac".
    ///
    /// Sekarang panelnya digambar sendiri dari komponen yang sama dengan sisa
    /// aplikasi. `.popover` dipakai — bukan `.overlay` buatan sendiri —
    /// karena `.popover` sudah memberi perilaku yang mahal untuk ditulis ulang:
    /// tutup saat klik di luar, tutup saat Esc, dan posisikan mengikuti tepi
    /// jendela.
    private var overflowMenu: some View {
        Button {
            showOverflow.toggle()
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16 * Theme.uiScale, weight: .bold))
                .foregroundColor(showOverflow ? Palette.mint : Palette.textSecondary)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Palette.navyDeep.opacity(showOverflow ? 1.0 : 0.65)))
                .overlay(Circle().strokeBorder(
                    showOverflow ? Palette.mint.opacity(0.65) : Palette.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(Text("action_more"))
        .popover(isPresented: $showOverflow, arrowEdge: .bottom) {
            overflowPanel
        }
    }

    /// Isi panel `…`.
    ///
    /// Lebarnya 300pt (menu NSMenu lama ~180pt) dan tinggi barisnya 46pt
    /// (NSMenu ~22pt) — dua ukuran yang membuat daftar ini terbaca sebagai
    /// bagian dari aplikasi, bukan popup milik sistem.
    private var overflowPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            overflowSection("menu_section_actions")
            overflowItem(id: "refresh", icon: "arrow.triangle.2.circlepath",
                         tint: Palette.info, title: "menu_refresh_all",
                         subtitle: "menu_refresh_all_sub") {
                Task { await state.refreshAll() }
            }
            overflowItem(id: "ping", icon: "speedometer",
                         tint: Palette.mint, title: "menu_ping_all",
                         subtitle: "menu_ping_all_sub",
                         disabled: state.nodes.isEmpty) {
                Task { await state.pingAll() }
            }

            overflowDivider

            overflowSection("menu_section_navigation")
            overflowItem(id: "servers", icon: "server.rack",
                         tint: Palette.mint, title: "nav_servers",
                         subtitle: "menu_servers_sub") {
                selection = "servers"
            }
            overflowItem(id: "sources", icon: "cloud",
                         tint: Palette.info, title: "nav_sources",
                         subtitle: "menu_sources_sub") {
                selection = "sources"
            }
        }
        .padding(.vertical, 6)
        .frame(width: 300)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Palette.card)
                .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 1)
        )
    }

    /// Judul kelompok, gaya overline yang sama dengan kartu lain.
    private func overflowSection(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(Theme.overline)
            .foregroundColor(Palette.textTertiary)
            .textCase(.uppercase)
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var overflowDivider: some View {
        Rectangle()
            .fill(Palette.border.opacity(0.7))
            .frame(height: 1)
            .padding(.vertical, 6)
            .padding(.horizontal, 14)
    }

    /// Satu baris menu: ikon berkilau + judul + keterangan.
    ///
    /// Keterangan ditambahkan karena di menu 300pt ada ruang, dan "Perbarui
    /// semua" vs "Uji ping semua" jauh lebih mudah dibedakan sekilas kalau
    /// masing-masing menjelaskan efeknya.
    private func overflowItem(id: String, icon: String, tint: Color,
                              title: LocalizedStringKey, subtitle: LocalizedStringKey,
                              disabled: Bool = false,
                              action: @escaping () -> Void) -> some View {
        let hovered = hoveredOverflowItem == id && !disabled
        return Button {
            guard !disabled else { return }
            action()
            showOverflow = false
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 13 * Theme.uiScale, weight: .semibold))
                    .foregroundColor(disabled ? Palette.textTertiary : tint)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill((disabled ? Palette.textTertiary : tint).opacity(hovered ? 0.28 : 0.16)))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder((disabled ? Palette.textTertiary : tint).opacity(hovered ? 0.5 : 0.25),
                                      lineWidth: 1))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Theme.font(.callout, design: .rounded).weight(.semibold))
                        .foregroundColor(disabled ? Palette.textTertiary : Palette.textPrimary)
                    Text(subtitle)
                        .font(Theme.font(.caption))
                        .foregroundColor(Palette.textTertiary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .frame(height: 46)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(hovered ? Palette.navyDeep : .clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { inside in
            // `onHover` hanya jalan di macOS — dan ini memang app macOS.
            hoveredOverflowItem = inside ? id : (hoveredOverflowItem == id ? nil : hoveredOverflowItem)
        }
    }

    /// Greeting penyambut sesuai jam. Desain menampilkan "Good evening", tapi
    /// menampilkan sapaan yang benar sepanjang hari lebih wajar daripada satu
    /// teks beku yang bisa jadi salah enam jam dalam sehari.
    private var greeting: LocalizedStringKey {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: return "greeting_morning"
        case 12..<18: return "greeting_afternoon"
        default: return "greeting_evening"
        }
    }

    /// Tiga penanda kualitas di bawah peta.
    ///
    /// SENGAJA ditulis sebagai `LocalizedStringKey`, bukan `String`: `Text`
    /// dengan nilai `String` runtime dirender VERBATIM — tidak pernah mencari
    /// ke tabel terjemahan — jadi key mentah seperti `card_tag_fast` akan
    /// tampil apa adanya di layar.
    private static let qualityTags: [LocalizedStringKey] =
        ["card_tag_fast", "card_tag_stable", "card_tag_reliable"]

    private var qualityTagRow: some View {
        HStack(spacing: 9) {
            ForEach(Array(Self.qualityTags.enumerated()), id: \.offset) { i, tag in
                Text(tag)
                    .font(Theme.scaled(10))
                    .foregroundColor(Palette.textTertiary)
                    .lineLimit(1)
                if i < Self.qualityTags.count - 1 {
                    Circle().fill(Palette.textTertiary).frame(width: 2, height: 2)
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Banner

    @ViewBuilder
    private var banners: some View {
        VStack(spacing: 10) {
            errorBanner
            healthBanner
            if SingBoxConfigBuilder.isBypassAll(split: state.split) {
                noticeRow(symbol: "exclamationmark.triangle.fill",
                          tint: Palette.warning,
                          text: Text("warn_inclusive_empty"))
            }
        }
    }

    private func noticeRow(symbol: String, tint: Color, text: some View) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: symbol).foregroundColor(tint)
            text.font(Theme.font(.callout)).foregroundColor(Palette.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tint.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(tint.opacity(0.35), lineWidth: 1)
        )
    }

    // MARK: - Dua kolom atas

    /// D88 — kolom kiri: Daya. Kolom kanan: log koneksi live, lalu peta besar.
    ///
    /// Slot di atas peta sebelumnya ditempati strip "Server Direkomendasikan".
    /// Sekarang slot itu menampilkan koneksi yang SEDANG lewat tunnel
    /// (domain + app + laju) — informasi yang hanya ada saat VPN hidup dan
    /// jauh lebih berguna daripada satu saran server statis.
    ///
    /// Peta adalah elemen paling menonjol di layar ini, dan itu memang
    /// TUJUANNYA: pertanyaan paling sering dari user adalah "saya sedang
    /// tunnel lewat negara mana?".
    ///
    /// Kenapa peta tidak dibuat "baris penuh" selebar jendela: proyeksi
    /// Robinson punya rasio sekitar 1.9:1. Peta setinggi 240pt yang
    /// selebar 1160pt hanya akan memakai ~460pt dari lebar itu — angkanya
    /// jadi kecil di tengah ruang kosong. Peta 2:1 di kolom kanan jauh
    /// lebih besar dan pin-nya tetap terbaca.
    private var topRow: some View {
        HStack(alignment: .top, spacing: 14) {
            powerCard.frame(width: 260)
            VStack(alignment: .leading, spacing: 14) {
                ConnectionsCard(connection: state.connection)
                    .frame(maxWidth: .infinity)
                mapCard
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Trafik + Sumber Subscription, lagi penuh di bawah baris atas.
    private var statsRow: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Kartu trafik observe `ConnectionManager` sendiri (lihat
            // `TrafficCard`) supaya angka tiap 2 detik tidak menggambar ulang
            // peta/tabel/log di atasnya.
            TrafficCard(connection: state.connection, mixedPort: state.connection.mixedPort)
                .frame(maxWidth: .infinity)
            sourcesCard.frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Peta dunia — elemen dominan layar ini.
    ///
    /// Peta menandi server yang SEDANG DIPAKAI, jadi sumbernya
    /// `activeNode`: tersambung -> node yang membawa trafik (pin denyut);
    /// belum sambung -> node terpilih (pin diam); tidak ada -> tanpa pin.
    private var mapCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                CardHeader("map", "card_server_location")
                if let n = activeNode {
                    // Negara dicetak di header supaya peta tidak pernah jadi
                    // satu-satunya cara user tahu tunnel-nya di mana.
                    // `countryLabel` (bukan `displayName` telanjang) supaya
                    // kode negara yang tak dikenal jatuh ke nama node —
                    // header tidak pernah menampilkan "ZZ".
                    Text(countryLabel(n))
                        .font(Theme.scaled(13, weight: .semibold))
                        .foregroundColor(Palette.mint)
                        .lineLimit(1)
                }
            }
            ServerWorldMap(node: activeNode,
                           isConnected: state.connection.status == .connected)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .padding(16)
        .frame(maxHeight: .infinity)
        .freepnCard()
    }

    private var powerCard: some View {
        VStack(spacing: 12) {
            PowerRing(status: state.connection.status) { connectPressed() }
                .padding(.top, 4)

            VStack(spacing: 3) {
                Text(statusText)
                    .font(Theme.scaled(19, weight: .semibold))
                    .foregroundColor(Palette.textPrimary)
                    // D82: `lineLimit(1)` + tinggi terkunci. Tanpa itu,
                    // "Disconnected" dan "Connecting…" bisa ocupa jumlah
                    // baris berbeda (tergantung lebar font/scale) dan
                    // menggeser seluruh isi di bawahnya.
                    .lineLimit(1)
                    .frame(height: Self.statusTitleHeight)
                Text(statusDetail)
                    .font(Theme.font(.callout))
                    .foregroundColor(Palette.textTertiary)
                    .multilineTextAlignment(.center)
                    // Panjang tiap status BERBEDA: "Your internet is not
                    // protected" vs "Setting up the tunnel…" vs "Your traffic
                    // goes through the VPN". Di lebar kartu yang sempit,
                    // yang panjang membungkus ke dua baris dan yang pendek
                    // tidak — jadi tombol bergeser saat status berubah.
                    // Tinggi dua baris dikunci supaya semua status berisi
                    // tinggi sama.
                    .lineLimit(2)
                    .frame(height: Self.statusDetailHeight)
            }

            // D82: area durasi + IP keluar.
            //
            // Sebelumnya blok ini hanya ada saat `.connected` — dan karena
            // posisinya DI ATAS tombol, setiap sambung berhasil mendorong
            // tombol ke bawah, lalu setiap putus menariknya ke atas lagi.
            // Itulah "kadang naik turun"-nya: bukan animasi, tapi reflow.
            //
            // Sekarang ruangnya SELALU ada; isinya berubah, tinggi tidak.
            connectedInfo

            Button(action: connectPressed) {
                Label { Text(connectLabel) } icon: { Image(systemName: "power") }
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(state.connection.status == .connecting || state.connection.status == .disconnecting)
            .keyboardShortcut(.defaultAction)

            // Sambung otomatis bila core mati tiba-tiba (watchdog). Checkbox
            // yang sama dengan Pengaturan — dua-duanya menulis flag yang
            // sama (`settings.autoReconnect` → `connection.autoReconnect`).
            Toggle(isOn: Binding(
                get: { state.settings.autoReconnect },
                set: { v in
                    state.settings.autoReconnect = v
                    state.connection.autoReconnect = v
                    state.persist(onlySettings: true)
                }
            )) {
                Text("auto_reconnect_short")
                    .font(Theme.font(.callout))
                    .foregroundColor(Palette.textSecondary)
            }
            .toggleStyle(.checkbox)

            if let n = activeNode {
                nodeStrip(n)
            } else {
                emptyState
            }

            // D88: peta TIDAK lagi di kartu ini. Peta pindah ke `mapCard`
            // sendiri supaya bisa jadi elemen dominan layar, bukan sekadar
            // gambar kecil di bawah tombol. Kartu Daya sekarang setinggi
            // isinya saja.

            // Sisa tinggi ke bawah supaya kartu Daya tetap dasar rata dengan
            // kolom peta di sebelahnya.
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .freepnCard(padding: 0)
    }

    /// Area info "sedang tersambung": durasi + IP keluar.
    ///
    /// D82 — ruang di sini SELALU book's, apa pun statusnya. Isinya boleh
    /// hilang, luarnya tidak.
    ///
    /// Kenapa tidak pakai `if`: blok ini duduk di antara status dan tombol.
    /// Kalau hanya ada saat `.connected`, setiap sambung berhasil menambah
    /// tinggi di atas tombol sehingga tombol melorot ke bawah, dan setiap
    /// putus sebaliknya menariknya ke atas. Perubahan status pun
    private var connectedInfo: some View {
        let connected = state.connection.status == .connected
        return VStack(spacing: 3) {
            if connected, let since = state.connection.connectedSince {
                Text(since, style: .timer)
                    .font(Theme.font(.callout, design: .monospaced))
                    .monospacedDigit()
                    .foregroundColor(Palette.mint)
            }

            // IP exit VPN, langsung di bawah durasi sambung — ini angka yang
            // dicari user untuk memastikan dia benar-benar berada di negara
            // server, jadi tempatnya seingat itu, bukan tersembunyi di kartu
            // Trafik. `lastExitIP` diisi otomatis Core selepas connect
            // (ConnectionManager.setConnected), jadi tidak perlu fetch manual.
            if connected, let ip = state.connection.lastExitIP, !ip.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "network")
                        .font(.system(size: 9 * Theme.uiScale))
                    Text(ip)
                        .font(Theme.font(.caption, design: .monospaced))
                        .lineLimit(1)
                }
                .foregroundColor(Palette.textSecondary)
            }
        }
        .frame(height: Self.connectedInfoHeight)
        .animation(.easeOut(duration: 0.18), value: connected)
    }

    // MARK: - Tinggi terkunci (D82)

    // Angka-angka ini mengikat tinggi bagian yang isinya berubah-ubah
    // menurut status. Tujuannya BUKAN estetika, tapi satu hal saja:
    // tombol Sambung/Putus dan Quick Connect harus diam di tempat yang
    // sama saat status berubah.
    //
    // D83: dikunci dari UKURAN FONT SEBENARNYA, bukan angka tetap. Versi
    // pertama memakai literal (24 / 32 / 35) dan itu rusak: `Theme.uiScale`
    // bisa diubah user lewat Pengaturan, jadi di 125% satu baris callout
    // sudah lebih tinggi dari 32pt dan teks detail TERPOTONG jadi
    // "Internet Anda tidak terlindu…". Angka tetap hanya benar di 100%.
    //
    // `Theme.pointSize` sudah mengalikan uiScale, jadi semua tinggi ikut
    // diskalakan otomatis. Faktor 1.3 adalah tinggi baris tipikal font sistem.
    static let lineFactor: CGFloat = 1.3
    // `internal`, bukan `private`: tinggi ini bisa diuji secara
    // NUMERIK dengan mengubah `Theme.uiScale`, dan itu jauh lebih
    // kuat daripada memindai source (lihat D83).
    static var statusTitleHeight: CGFloat {
        19 * Theme.uiScale * lineFactor
    }
    static var statusDetailHeight: CGFloat {
        Theme.pointSize(.callout) * lineFactor * 2      // dua baris dikunci
    }
    static var connectedInfoHeight: CGFloat {
        // baris durasi + jarak 3 + baris IP
        Theme.pointSize(.callout) * lineFactor + 3 + Theme.pointSize(.caption) * lineFactor
    }

    /// Kartu ringkas node yang sedang dipakai / terpilih.
    private func nodeStrip(_ n: ProxyNode) -> some View {
        HStack(spacing: 10) {
            Text(CountryInfer.flagEmoji(for: n.countryCode))
                .font(.system(size: 20))
            VStack(alignment: .leading, spacing: 2) {
                Text(n.name)
                    .font(Theme.font(.subheadline))
                    .foregroundColor(Palette.textPrimary)
                    .lineLimit(1)
                // Ikuti toggle yang sama dengan kolom IP di menu Server —
                // node yang sama tidak boleh tampil beda di dua layar.
                Text(n.endpoint(includePort: state.settings.showNodePort))
                    .font(Theme.font(.caption))
                    .foregroundColor(Palette.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            ProtocolBadge(n.proto)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Palette.navyDeep.opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 1)
        )
    }

    // MARK: - Kartu statistik (Traffik + Sumber)

    private var sourcesCard: some View {
        NavigableCard(action: { selection = "sources" }) {
            IconTile("server.rack", size: 32)
            VStack(alignment: .leading, spacing: 2) {
                SingleLineLabel(Text("card_subscription_sources"))
                SingleLineLabel(Text(L10n.formatted("card_sources_summary", sourcesOnline, state.sources.count)),
                                tint: Palette.textSecondary)
                    .font(Theme.font(.caption))
                SingleLineLabel(Text(lastRefreshText), tint: Palette.textTertiary)
                    .font(Theme.font(.caption2))
            }
            Spacer(minLength: 0)
        }
    }

    /// Sumber yang Condition fetch terakhirnya berhasil (bukan Unavailable).
    private var sourcesOnline: Int {
        state.sources.filter { $0.status == .ok }.count
    }

    private var lastRefreshText: String {
        let dates = state.sources.compactMap(\.lastUpdated)
        guard let newest = dates.max() else {
            return NSLocalizedString("card_never_refreshed", comment: "")
        }
        return L10n.formatted("card_refreshed_ago",
                              RelativeDate.string(for: newest, language: state.settings.language))
    }

    // MARK: - Pratinjau server

    private var availableServersCard: some View {
        TableCard {
            HStack(spacing: 12) {
                Image(systemName: "server.rack")
                    .font(.system(size: 14 * Theme.uiScale, weight: .medium))
                    .foregroundColor(Palette.mint)
                Text("card_available_servers")
                    .font(Theme.cardTitle)
                    .foregroundColor(Palette.textPrimary)

                SearchField("search_placeholder", text: $state.searchText)
                    .frame(maxWidth: 210)

                protoChips
                Spacer(minLength: 0)

                Button { selection = "servers" } label: {
                    HStack(spacing: 5) {
                        Text("action_see_all_servers")
                        Image(systemName: "chevron.right")
                    }
                }
                .buttonStyle(.plain)
                .font(Theme.font(.caption))
                .foregroundColor(Palette.mint)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        } content: {
            serverList(previewNodes, compact: true)
        }
    }

    /// Tabel server. `compact` dipakai pratinjau di layar Sambung: kolom
    /// IP disembunyikan supaya lima baris muat tanpa menggulir.
    @ViewBuilder
    private func serverList(_ nodes: [ProxyNode], compact: Bool) -> some View {
        if nodes.isEmpty {
            VStack(spacing: 10) {
                if state.isRefreshing {
                    ProgressView()
                    Text("refreshing_sources")
                        .font(Theme.font(.callout))
                        .foregroundColor(Palette.textTertiary)
                } else {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 20))
                        .foregroundColor(Palette.textTertiary)
                    Text("empty_no_servers")
                        .font(Theme.font(.callout))
                        .foregroundColor(Palette.textTertiary)
                    Text("empty_hint_sources")
                        .font(Theme.font(.caption))
                        .foregroundColor(Palette.textTertiary)
                        .multilineTextAlignment(.center)
                    Button("action_refresh") { Task { await state.refreshAll() } }
                        .buttonStyle(SecondaryButtonStyle(active: true))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
        } else {
            let best = Self.bestLatency(in: nodes, ping: state.ping)
            VStack(spacing: 0) {
                serverHeaderRow(compact: compact)
                Hairline().padding(.horizontal, 14)
                ForEach(nodes) { n in
                    TableRowView(selected: state.selectedNodeID == n.id) {
                        serverRow(n, best: best, compact: compact)
                    }
                }
            }
        }
    }

    private func serverHeaderRow(compact: Bool) -> some View {
        HStack(spacing: 10) {
            ColumnLabel("col_country_name").frame(width: compact ? 150 : 140, alignment: .leading)
            ColumnLabel("col_proto").frame(width: 84, alignment: .leading)
            ColumnLabel("col_latency").frame(width: 96, alignment: .leading)
            ColumnLabel("col_load").frame(width: 100, alignment: .leading)
            ColumnLabel("col_favorite").frame(width: 58)
            Spacer(minLength: 30)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func serverRow(_ n: ProxyNode, best: Int?, compact: Bool) -> some View {
        Button { state.connect(node: n) } label: {
            HStack(spacing: 10) {
                ServerIdentity(node: n, source: state.sourceName(for: n.sourceID))
                    .frame(width: compact ? 150 : 140, alignment: .leading)
                ProtocolBadge(n.proto).frame(width: 84, alignment: .leading)
                LatencyCell(ms: state.ping[n.id]?.webLatencyMs,
                            dead: state.ping[n.id]?.isDeadEnd == true,
                            approximate: state.ping[n.id]?.approximate == true)
                    .frame(width: 96, alignment: .leading)
                LoadBar(fraction: Self.load(ms: state.ping[n.id]?.webLatencyMs, best: best),
                        measured: state.ping[n.id]?.webLatencyMs != nil)
                    .frame(width: 100, alignment: .leading)
                FavoriteStar(active: state.favorites.contains(n.id)) { toggleFav(n) }
                    .frame(width: 58)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11 * Theme.uiScale, weight: .semibold))
                    .foregroundColor(Palette.textTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { state.connect(node: n) } label: {
                Label("action_connect", systemImage: "power")
            }
            Button { Task { await state.pingOne(n) } } label: {
                Label("action_ping", systemImage: "speedometer")
            }
            Button { toggleFav(n) } label: {
                Label(state.favorites.contains(n.id) ? "action_unfavorite" : "action_favorite",
                      systemImage: state.favorites.contains(n.id) ? "star.slash" : "star")
            }
            if state.favorites.contains(n.id) {
                Button { selection = "servers" } label: {
                    Label("action_see_all_servers", systemImage: "server.rack")
                }
            }
        }
    }

    private var protoChips: some View {
        HStack(spacing: 7) {
            FilterChip("filter_all", selected: state.protoFilter == nil) {
                state.protoFilter = nil
            }
            ForEach(NodeProtocol.allCases, id: \.self) { p in
                FilterChip(title: p.badgeTitle, selected: state.protoFilter == p) {
                    state.protoFilter = (state.protoFilter == p) ? nil : p
                }
            }
        }
    }

    // MARK: - Data turunan

    /// Node yang sedang dipakai: sedang terhubung, kalau tidak node terpilih.
    var activeNode: ProxyNode? {
        Self.mapNode(connected: state.connection.lastNode, selected: state.selectedNode)
    }

    /// Node yang boleh dipetakan.
    ///
    /// Murni (tidak membaca `AppState`) supaya bisa diuji: kontrak yang
    /// dijaga adalah "terhubung menang atas sekadar terpilih".
    nonisolated static func mapNode(connected: ProxyNode?,
                                    selected: ProxyNode?) -> ProxyNode? {
        connected ?? selected
    }

    /// Lima server tercepat dari daftar yang sedang difilter.
    ///
    /// Datanya sudah dihitung sekali di `AppState` (turun dari `filteredNodes`)
    /// — sebelumnya `sorted()` penuh 16.000 node DI DALAM `body`, yang
    /// dievaluasi ulang tiap 2 detik selama terhubung (D61).
    var previewNodes: [ProxyNode] { state.previewNodes }

    /// Urut berdasarkan latensi terukur, dalam tiga tingkat.
    ///
    /// 1. Sudah diuji dan punya latensi — paling cepat dulu.
    /// 2. Belum pernah diuji — masih mungkin bagus, belum ada buktinya.
    /// 3. Terbukti tidak punya internet — selalu paling akhir.
    ///
    /// Tingkat 3 sengaja terpisah dari tingkat 2: keduanya punya `bestMs == nil`,
    /// jadi kalau hanya dibandingkan per angka, keduanya seri dan
    /// urutannya jatuh ke nama — server mati bisa muncul mendahului server
    /// yang belum pernah diuji. Itu kebalikan dari cara app memilih node.
    /// Versi PENUH dari `AppState.topByLatency` — mengurutkan seluruh daftar.
    ///
    /// Hanya dipakai test. Jalur produksi memakai `topByLatency`, yang tidak
    /// melakukan sort penuh karena yang dibutuhkan cuma 5 elemen teratas.
    /// Keduanya harus sepakat soal urutan — `testByLatencyMatchesTopByLatency`
    /// yang mengunci itu.
    static func byLatency(_ nodes: [ProxyNode], ping: [String: PingResult]) -> [ProxyNode] {
        AppState.topByLatency(nodes, ping: ping, count: Int.max)
    }

    /// Latensi terbaik di antara sekumpulan node — pembagi kolom Load.
    static func bestLatency(in nodes: [ProxyNode], ping: [String: PingResult]) -> Int? {
        nodes.compactMap { ping[$0.id]?.bestMs }.min()
    }

    /// Beban relatif: seberapa jauh latensi node ini dari yang tercepat.
    ///
    /// BUKAN metrik beban penyedia server — feed gratis tidak
    /// menyediakannya. Yang ditunjukkan adalah "node ini jauh lebih lambat
    /// daripada yang terbaik milikmu", dan tooltip menyatakan itu terus terang.
    static func load(ms: Int?, best: Int?) -> Double {
        guard let ms = ms, let best = best, best > 0 else { return 0 }
        return min(1, Double(ms - best) / Double(max(1, best * 2)))
    }

    func countryLabel(_ n: ProxyNode) -> String {
        CountryInfer.displayName(for: n.countryCode) ?? n.name
    }

    func toggleFav(_ n: ProxyNode) {
        if state.favorites.contains(n.id) { state.favorites.remove(n.id) }
        else { state.favorites.insert(n.id) }
        state.persist(onlyFavorites: true)
    }

    // MARK: - Log koneksi lengkap

    /// Panel log: SENGAJA selalu terlihat (tanpa DisclosureGroup). Log adalah
    /// alat diagnosis utama — kalau harus diklik dulu, orang tidak akan
    /// bothered membuka saat status membeku.
    ///
    /// Panel tetap ringan:
    /// - dirender per-baris di `LazyVStack` (hanya ~20 baris terlihat yang
    ///   dimaterialisasi, bukan 200),
    /// - `.textSelection(.enabled)` satu kali di container, bukan di tiap baris
    ///   (200 selection area adalah penyebab utama "app berat" versi lama),
    /// - `reloadLog()` melewati update saat isi tidak berubah sama sekali.
    private var logPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            logHeaderBar
            ScrollViewReader { proxy in
                ScrollView {
                    if logLines.isEmpty {
                        Text("log_empty")
                            .font(Theme.font(.callout, design: .monospaced))
                            .foregroundColor(Palette.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            ForEach(logLines.indices, id: \.self) { i in
                                Text(logLines[i])
                                    .font(Theme.font(.caption, design: .monospaced))
                                    .foregroundColor(Palette.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(i)
                            }
                        }
                        .textSelection(.enabled)
                    }
                }
                .onAppear { scrollToBottom(proxy) }
                // Ikuti log baru: jumlah baris berubah -> taruh baris terakhir di bawah.
                .onChange(of: logLines.count) { _ in scrollToBottom(proxy) }
            }
            .frame(minHeight: 150, idealHeight: 210, maxHeight: 300)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Palette.well)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: 1)
            )
        }
        .padding(14)
        .freepnCard(padding: 0)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard let last = logLines.indices.last else { return }
        proxy.scrollTo(last, anchor: .bottom)
    }

    private var logHeaderBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 11 * Theme.uiScale))
                .foregroundColor(Palette.mint)
            Text("card_log")
                .font(Theme.cardTitle)
                .foregroundColor(Palette.textPrimary)
            Spacer(minLength: 12)
            Button("log_refresh") { reloadLog() }.buttonStyle(.plain)
                .foregroundColor(Palette.mint)
            Button("log_copy") { copyLog() }.buttonStyle(.plain)
                .foregroundColor(Palette.mint)
            Button("log_save") { saveLog() }.buttonStyle(.plain)
                .foregroundColor(Palette.mint)
            if !logNotice.isEmpty {
                Text(logNotice)
                    .font(Theme.font(.caption)).foregroundColor(Palette.textTertiary)
                    .lineLimit(1).truncationMode(.tail)
            }
            Text("\(L10n.string("log_time")): \(Self.stamp.string(from: logUpdated))")
                .font(Theme.font(.caption)).foregroundColor(Palette.textTertiary)
                .lineLimit(1).truncationMode(.middle)
                // Paling boleh gepes: bagian kanan tidak boleh mendorong
                // tombol di kiri keluar panel.
                .layoutPriority(-1)
        }
        .font(Theme.font(.caption))
        .padding(.horizontal, 14)
    }

    /// Header sesi. SENGAJA tanpa timestamp "sekarang": kalau header memuat
    /// `Date()`, string berubah tiap 2 detik walau log diam — SwiftUI lalu
    /// menginvalidasi penuh daftar baris tiap refresh. Waktu ditampilkan
    /// terpisah di `logUpdated` (cuma berubah saat isi benar-benar berubah),
    /// dan tetap ikut ditulis ke berkas saat Copy/ Save lewat `logDocument`.
    private func logHeader() -> String {
        let c = state.connection
        let node = c.lastNode ?? state.selectedNode
        let mode = "DaemonTUN"
        var lines = [
            "\(L10n.string("log_status")): \(c.status.rawValue)\(c.usingLocalCore ? " (local)" : "")",
            "\(L10n.string("log_node")): \(node.map { "\($0.name) (\($0.host):\($0.port))" } ?? "-")",
            "\(L10n.string("log_mode")): \(mode) / \(state.split.mode.rawValue)",
            "\(L10n.string("log_ports")): clash=\(c.clashPort) mixed=\(c.mixedPort)",
            "\(L10n.string("log_exitip")): \(c.lastExitIP ?? "-")",
        ]
        // Riwayat perubahan split ikut di sini, bukan cuma di Split Tunneling:
        // ini satu-satunya tempat yang ikut tersimpan saat user menyalin log
        // untuk melaporkan "kenapa app saya tidak lewat VPN".
        //
        // Tanpa timestamp per baris: `logHeader()` dipanggil tiap 5 detik, dan
        // menambahkan `Date()` per entri akan mengubah string pada tick mana
        // pun dan memicu invalidasi ulang seluruh daftar baris log.
        let recent = state.splitChanges.suffix(5).reversed()
        if !recent.isEmpty {
            lines.append("")
            lines.append("===== \(L10n.string("splitlog_title")) (\(recent.count)/\(state.splitChanges.count)) =====")
            for entry in recent {
                lines.append(contentsOf: SplitChangeLog.describe(entry))
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Isi siap ekspor: tetap membawa waktu walau UI tidak bergantung padanya.
    private var logDocument: String {
        "\(L10n.string("log_time")): \(logUpdated.description(with: .current))\n\(logText)"
    }

    /// Deteksi perubahan: kalau snapshot identik dengan yang tampil, JANGAN
    /// sentuh `@State` — tanpa itu tiap timer tick memicu re-render penuh.
    ///
    /// Pembacaan file terjadi DI LUAR main actor. `ConnectionLog.snapshot`
    /// membuka dua file log dan membaca mundur dari EOF; kalau itu jalan
    /// sinkron di sini, tiap 5 detik UI menahan thread utama selama waktu
    /// I/O itu (sampai ratusan ms saat helper sedang ramai menulis).
    private func reloadLog() {
        let header = logHeader()
        let current = logText
        Task {
            let fresh = await Task.detached(priority: .utility) {
                ConnectionLog.snapshot(header: header)
            }.value
            guard fresh != current else { return }
            await MainActor.run {
                logUpdated = Date()
                logText = fresh
                logLines = fresh.components(separatedBy: .newlines)
            }
        }
    }

    /// Versi sinkron yang dulu dipakai — dipertahankan hanya agar perilakunya
    /// bisa diuji tanpa concurrency test.
    func reloadLogSynchronously() {
        let fresh = ConnectionLog.snapshot(header: logHeader())
        guard fresh != logText else { return }
        logUpdated = Date()
        logText = fresh
        logLines = fresh.components(separatedBy: .newlines)
    }

    private func startLogTimer() {
        stopLogTimer()
        let t = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            reloadLog()
        }
        // `.common` supaya timer tetap jalan saat window sedang di-drag atau
        // scroll — mode `.default` dijeda persis saat itu (D61).
        RunLoop.main.add(t, forMode: .common)
        logTimer = t
    }

    private func stopLogTimer() {
        logTimer?.invalidate()
        logTimer = nil
    }

    private func copyLog() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(logDocument, forType: .string)
        logNotice = NSLocalizedString("log_copied", comment: "")
    }

    private func saveLog() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "freepn-connection.log"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try logDocument.write(to: url, atomically: true, encoding: .utf8)
            logNotice = "\(NSLocalizedString("log_saved", comment: "")): \(url.lastPathComponent)"
        } catch {
            logNotice = error.localizedDescription
        }
    }

    // MARK: - Status & aksi

    private var statusText: String {
        switch state.connection.status {
        case .disconnected: return NSLocalizedString("status_disconnected", comment: "")
        case .connecting: return NSLocalizedString("status_connecting", comment: "")
        case .connected: return NSLocalizedString("status_connected", comment: "")
        case .disconnecting: return NSLocalizedString("status_disconnecting", comment: "")
        case .error: return NSLocalizedString("status_error", comment: "")
        }
    }

    /// Baris kedua di bawah status: menjelaskan apa arti status itu.
    private var statusDetail: String {
        switch state.connection.status {
        case .connected:
            return NSLocalizedString("connect_detail_protected", comment: "")
        case .connecting, .disconnecting:
            return NSLocalizedString("connect_detail_working", comment: "")
        case .error:
            return NSLocalizedString("connect_detail_error", comment: "")
        case .disconnected:
            return NSLocalizedString("connect_detail_unprotected", comment: "")
        }
    }

    private var connectLabel: String {
        state.connection.status == .connected
            ? NSLocalizedString("action_disconnect", comment: "")
            : NSLocalizedString("action_connect", comment: "")
    }

    private var errorBanner: some View {
        Group {
            if state.connection.status == .error && !state.connection.errorMessage.isEmpty {
                noticeRow(symbol: "exclamationmark.triangle.fill",
                          tint: Palette.danger,
                          text: Text(state.connection.errorMessage).textSelection(.enabled))
            }
        }
    }

    /// Banner izin: muncul saat app dibuka bila ada izin belum beres.
    /// Detail + cara betulkan ada di Settings → Permissions & Health.
    private var healthBanner: some View {
        Group {
            if state.health.isChecking {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7)
                    Text("health_check").font(Theme.font(.callout)).foregroundColor(Palette.textSecondary)
                    Spacer(minLength: 0)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .freepnCard(padding: 12)
            } else if state.health.hasFailure {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.shield.fill").foregroundColor(Palette.danger)
                        Text("health_issues").font(Theme.font(.callout)).foregroundColor(Palette.danger)
                        Spacer(minLength: 0)
                    }
                    ForEach(state.health.items.filter { $0.level == .fail }) { it in
                        Text(it.title).font(Theme.font(.caption)).foregroundColor(Palette.textSecondary)
                    }
                    HStack(spacing: 12) {
                        if state.health.items.contains(where: { $0.id == "helper" && $0.level != .ok }) {
                            HelperInstallButton()
                        }
                        Button("health_recheck") { state.checkHealth() }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .freepnCard(padding: 12)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            if state.isRefreshing {
                ProgressView()
                Text("refreshing_sources")
                    .foregroundColor(Palette.textTertiary)
                    .font(Theme.font(.callout))
            } else {
                Text("empty_no_servers")
                    .foregroundColor(Palette.textTertiary)
                    .multilineTextAlignment(.center)
                Button("action_refresh") { Task { await state.refreshAll() } }
                    .buttonStyle(SecondaryButtonStyle(active: true))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
    }

    private func connectPressed() {
        if state.isConnected { state.disconnect() }
        else if let n = activeNode ?? state.quickConnectNode() { state.connect(node: n) }
    }

    // MARK: Format angka
}

/// Kartu Trafik + IP keluar, dipisah jadi view sendiri (D61).
///
/// Kenapa dipisah: angka trafik berubah SETIAP 2 detik selama terhubung. Kalau
/// kartu ini tetap jadi computed property di `ConnectView` (yang observe
/// `AppState`), setiap 2 detik SELURUH dashboard ikut digambar ulang — peta
/// dunia, tabel pratinjau server, panel log, semuanya — padahal tidak satu pun
/// menampilkan byte. Dengan `@ObservedObject` di sini, hanya kartu ini yang
/// dibangun ulang saat angka berubah.
///
/// `ByteCountFormatter` juga dipindah ke sini sebagai `static let`: API class
/// `string(fromByteCount:countStyle:)` membangun formatter internal SETIAP
/// pemanggilan, dan ini dipanggil dua kali per redraw kartu.
struct TrafficCard: View {
    @ObservedObject var connection: ConnectionManager
    /// Port mixed inbound — dipakai saat user menekan "Periksa" manual.
    let mixedPort: Int

    @State private var exitIP: String? = nil
    @State private var checkingIP = false

    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .binary
        return f
    }()

    /// Laju trafik dengan satuan yang menyesuaikan besarannya.
    ///
    /// D74: sebelumnya `"\(Int(bytesPerSecond / 1024)) KB/s"` — label selalu KB,
    /// apa pun besarnya. Setelah D73 (total benar) laju akhirnya benar, dan
    /// sekarang jelas terlihat: unduh 8 MB/s tampil "8192 KB/s", angka yang
    /// membuat user harus menghitung sendiri di kepalanya.
    ///
    /// SATUAN: KiB/MiB (1024), bukan KB/MB (1000) — sengaja, supaya konsisten
    /// dengan `byteFormatter` yang `countStyle = .binary` di bawah. Memakai
    /// "KB" untuk 1024 byte adalah pembulatan yang menyesatkan; kalau labelnya
    /// "KiB" maka tidak ada yang perlu ditebak.
    ///
    /// Batas atas 999 dipilih agar bagian desimalnya tidak pernah muncul:
    /// angka laju berubah tiap 2 detik, dan "12,3 MiB/s" yang lebarnya berganti
    /// ganti-ganti membuat kolom ikut bergoyang. Batas 999 menjaga lebar label
    /// stabil (3 digit) di semua satuan.
    nonisolated static func rate(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond.isFinite, bytesPerSecond > 0 else { return "0 KiB/s" }
        let units = ["KiB/s", "MiB/s", "GiB/s", "TiB/s", "PiB/s", "EiB/s"]
        var value = bytesPerSecond / 1024.0      // mulai dari KiB
        var i = 0
        while value >= 1000, i < units.count - 1 {
            value /= 1024
            i += 1
        }
        // `Int(value)` TRAP kalau `value` di luar rentang Int — jadi data rusak
        // dari core (atau laju astronomis) bisa membuat proses mati, bukan
        // sekadar salah tampil. Clamp dulu: nilai dibatasi ke 999 agar label
        // tidak pernah jadi "1048576 TiB/s".
        let clamped = min(value, 999.0)
        let rounded = clamped < 1 ? 1 : Int(clamped)
        return "\(rounded) \(units[i])"
    }

    static func bytes(_ n: Int64) -> String {
        byteFormatter.string(fromByteCount: n)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: "chart.xyaxis.line")
                    .font(.system(size: 12 * Theme.uiScale, weight: .semibold))
                    .foregroundColor(Palette.mint)
                Text("card_traffic")
                    .font(Theme.cardTitle)
                    .foregroundColor(Palette.textPrimary)
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                MetricTile(symbol: "arrow.down", label: "card_download",
                           value: Self.rate(connection.downRate),
                           footnote: L10n.formatted("card_total", Self.bytes(connection.downBytes)),
                           tint: Palette.mint)
                MetricTile(symbol: "arrow.up", label: "card_upload",
                           value: Self.rate(connection.upRate),
                           footnote: L10n.formatted("card_total", Self.bytes(connection.upBytes)),
                           tint: Palette.info)
            }

            // D76: `.animation(_:value:)` yang dulu ada di Sparkline dihapus —
            // ia-lah penyebab "berhenti lalu melompat". Sekarang gerakan
            // sepenuhnya dari `TimelineView` + sumbu-x berbasis waktu, jadi
            // kartu ini TIDAK lagi digambar ulang tiap 2 detik hanya karena
            // sampel baru: sparkline menggambar dirinya sendiri per frame,
            // sedangkan tile angka hanya berubah saat laju benar-benar berubah.
            //
            // D78: KEDUA arah digambar di SATU plot (D77 sempat memisahkannya
            // menjadi dua grafik setengah lebar). Satu plot penuh lebih mudah
            // dibaca — dan karena kedua garis memakai SKALA Y yang sama,
            // perbandingan besar keduanya jadi terlihat langsung.
            Sparkline(series: connection.downHistory, tint: Palette.mint,
                      secondary: connection.upHistory, secondaryTint: Palette.info)
                .frame(height: 42)
                .opacity(connection.downHistory.isEmpty && connection.upHistory.isEmpty ? 0 : 1)

            Hairline()
            exitIPRow
        }
        .padding(14)
        .freepnCard()
    }

    private var exitIPRow: some View {
        HStack(spacing: 7) {
            Image(systemName: "network")
                .font(.system(size: 10 * Theme.uiScale))
                .foregroundColor(Palette.textTertiary)
            Text("exit_ip")
                .font(Theme.font(.caption))
                .foregroundColor(Palette.textTertiary)
            Spacer(minLength: 0)
            if checkingIP {
                ProgressView().scaleEffect(0.6).controlSize(.small)
            } else {
                Text(connection.lastExitIP ?? exitIP ?? "—")
                    .font(Theme.font(.caption, design: .monospaced))
                    .foregroundColor(Palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button("action_check") {
                    checkingIP = true; exitIP = nil
                    Task {
                        let ip = await ExitIPChecker.viaCore(port: mixedPort)
                        checkingIP = false; exitIP = ip ?? "?"
                    }
                }
                .buttonStyle(.plain)
                .font(Theme.font(.caption))
                .foregroundColor(Palette.mint)
                .disabled(checkingIP)
            }
        }
        .onAppear {
            // Sinkronkan tampilan manual dengan hasil auto-check.
            if exitIP == nil { exitIP = connection.lastExitIP }
        }
    }
}

/// Identitas server di tabel: bendera + nama negara + asal feed.
struct ServerIdentity: View {
    let node: ProxyNode
    let source: String

    var body: some View {
        HStack(spacing: 9) {
            Text(CountryInfer.flagEmoji(for: node.countryCode))
                .font(.system(size: 17))
            VStack(alignment: .leading, spacing: 1) {
                Text(CountryInfer.displayName(for: node.countryCode) ?? node.name)
                    .font(Theme.font(.subheadline))
                    .foregroundColor(Palette.textPrimary)
                    .lineLimit(1)
                Text(source)
                    .font(Theme.font(.caption2))
                    .foregroundColor(Palette.textTertiary)
                    .lineLimit(1)
            }
        }
    }
}

/// Peta dunia titik-titik (DotMap, vendored) dengan pin di lokasi server.
///
/// Dibuat sekali dan dipakai bersama: `DottedMap` menghitung ulang kisi
/// setiap kali setting berubah, jadi membangun ulang peta tiap render akan
/// membakar CPU di layar yang paling sering digulir.
@MainActor
private enum DotMapCache {
    static var map: DottedMap?
    static var loaded = false

    static func world() -> DottedMap? {
        if !loaded {
            loaded = true
            // Robinson: proyeksi yang enak dibaca untuk peta dunia di
            // lebar pendek (kartu), dan tidak mesmerum kan Kutub Utara seperti
            // Mercator.
            //
            // Ketinggian 26 titik itu terlalu rendah untuk Indonesia. Indonesia
            // itu kepulauan yang tersebar di ~17° bujur, dan pada 26 baris
            // worldwide Titik-titiknya jatuh di antara sampel grid — hasilnya
            // Indonesia praktis tidak tergambar sama sekali (user melaporkan
            // "peta Indonesia-nya kosong"). Ini BUKAN batas data: Indonesia
            // ada utuh di countries.geo.json (sudah diverifikasi).
            //
            // 46 memberi cukup density untuk kepulauan tanpa membuat kartu ini
            // berat: `DottedMap` dihitung SEKALI lalu dipakai bersama (lihat
            // cache di atas), jadi biaya hanya di opening, bukan per render.
            // Radius dot diperkecil supaya titik tidak saling menyatu
            // jadi gumpalan padat di kota-kota besar.
            map = try? DottedMap(settings: MapSettings(height: 46,
                                                       grid: .diagonal,
                                                       projection: Projection(name: .robinson)))
        }
        return map
    }
}

/// Peta dunia dengan pin lokasi server terpilih.
struct ServerWorldMap: View {
    let node: ProxyNode?

    /// Apakah `node` benar-benar sedang dipakai tunnel, bukan cuma node yang
    /// sedang terpilih di UI.
    ///
    /// D84: sebelumnya tidak ada parameter ini dan `isActive` di-hardcode
    /// `true`, dengan komentar yang mengklaim `node` "hanya non-nil saat ada
    /// server aktif". Klaim itu salah: peta pernah diberi `recommendedNode`,
    /// yang jatuh ke `filteredNodes.first` walau tidak ada sambungan
    /// apa pun — jadi pin berdenyut di server yang tidak pernah dipakai.
    /// Sekarang denyut berarti "tunnel hidup", bukan sekadar "ada node".
    var isConnected: Bool = false

    /// Pin dihitung SEKALI per node, bukan di setiap `body` evaluation.
    ///
    /// `.task(id:)` (bukan `onAppear`) supaya terikat pada umur view dan ikut
    /// ter-cancel kalau layar ditutup. Nilai `pins` disimpan di `@State` supaya
    /// `DotMapView` — yang membandingkan `pins` lewat `ForEach` — tidak melihat
    /// array baru yang isinya sama tiap redraw (D61).
    @State private var pins: [MapPin] = []

    var body: some View {
        Group {
            if let map = DotMapCache.world() {
                DotMapView(
                    map: map,
                    dotShape: .circle,
                    dotRadius: 0.14,
                    dotColor: Palette.mint.opacity(0.34),
                    backgroundColor: .clear,
                    pins: pins,
                    showsLabels: false
                )
            } else {
                // GeoJSON belum termuat — jangan tampilkan apa-apa yang
                // menyesatkan (peta kosong atau tempat yang salah).
                EmptyView()
            }
        }
        .allowsHitTesting(false)
        .task(id: "\(node?.id ?? "-")|\(isConnected)") {
            pins = Self.pins(for: node, isConnected: isConnected)
        }
    }

    /// Satu pin untuk lokasi server, dari GeoIP (offline).
    ///
    /// Prioritas: koordinat kota dari `GeoIP` (kalau host-nya IP literal) →
    /// centroid negara → tidak ada pin. Tidak ada panggilan jaringan.
    ///
    /// Radius pin dalam SATUAN PETA, bukan poin. Karena `MapPinView`
    /// mengalikan dengan skala peta, pin otomatis ikut membesar saat peta
    /// membesar — yang persis dibutuhkan setelah peta jadi elemen dominan
    /// layar (D88). 0.42 (nilai lama, saat peta cuma 224pt) menghasilkan
    /// pin ~10pt di peta 630pt: jauh terlalu kecil untuk jadi jawaban
    /// pertanyaan "saya sedang di negara mana?".
    nonisolated static let pinRadius = 0.72

    /// Murni & nonisolated supaya bisa diuji tanpa merender peta.
    ///
    /// - Parameters:
    ///   - node: server yang sedang DIPAKAI (terhubung), atau — kalau belum
    ///     ada sambungan — node yang sedang dipilih user. Kalau `nil`, peta
    ///     sengaja dibiarkan kosong daripada menunjuk server tebakan.
    ///   - isConnected: hanya `true` saat tunnel benar-benar hidup. Node yang
    ///     cuma "terpilih" tetap dapat pin, tapi TANPA denyut.
    nonisolated static func pins(for node: ProxyNode?,
                                isConnected: Bool = false) -> [MapPin] {
        guard let node = node else { return [] }
        // ID pin TETAP dari `node.id`, bukan koordinat dan bukan UUID baru:
        // SwiftUI mengidentifikasi baris `ForEach` lewat `id`, jadi id baru
        // tiap render berarti view pin dihancurkan & dibuat ulang — dan
        // `@State pulsing`-nya kembali ke `false`, sehingga animasi denyut
        // yang `repeatForever` RESTART dari nol setiap kali body digambar
        // ulang (D61).
        let pinID = node.id
        let label = CountryInfer.displayName(for: node.countryCode)
        if GeoIP.isIPv4Literal(node.host),
           let hit = GeoIP.lookup(node.host),
           let lat = hit.latitude, let lng = hit.longitude {
            return [MapPin(id: pinID, lat: lat, lng: lng, color: Palette.mint,
                           radius: Self.pinRadius, label: label, isActive: isConnected)]
        }
        // 1b. Host domain: koordinat kota dari hasil resolusi DNS yang sudah
        // di-cache pengayaan negara. Tanpa ini domain jatuh ke centroid —
        // benar secara negara, tapi jaraknya bisa ratusan kilometer.
        if let c = GeoIPResolver.cachedCoordinates(for: node.host) {
            return [MapPin(id: pinID, lat: c.lat, lng: c.lng, color: Palette.mint,
                           radius: Self.pinRadius, label: label, isActive: isConnected)]
        }
        // 2. Centroid negara, kalau kode negaranya ada.
        if let c = CountryInfer.centroid(for: node.countryCode) {
            return [MapPin(id: pinID, lat: c.lat, lng: c.lng, color: Palette.mint,
                           radius: Self.pinRadius, label: label, isActive: isConnected)]
        }
        return []
    }
}