import SwiftUI

@main
struct FreePNApp: App {
    init() {
        // D49: HARUS sebelum sweep TCP pertama. App yang dibuka dari
        // Finder mewarisi `launchctl limit maxfiles` soft = 256, sedangkan
        // sweep dengan hundreds koneksi hidup membakar ~480 FD. Lewati ini dan
        // `NWConnection.start()` gagal -> node yang hidup ditandai mati
        // (7,3% terbaca hidup, bukan 45,1%). Batas keras macOS `unlimited`,
        // jadi proses boleh menaikkan soft limit sendiri tanpa root.
        AppConstants.raiseFileDescriptorLimit()
    }

    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(state)
                // Skala UI: `.id` memaksa SELURUH pohon view dibangun ulang saat
                // skala berubah, karena `Theme.uiScale` dibaca ketika body
                // dihitung — termasuk SidebarView yang tidak mengamati
                // AppState sendiri.
                .id(state.settings.uiScalePercent)
                .frame(minWidth: Theme.minWindowWidth, minHeight: Theme.minWindowHeight)
                // Palet gelap adalah keputusan desain, bukan pilihan sistem:
                // warna kustom (kartu, garis, chip) hanya dirancang untuk
                // latar navy. Mode terang akan merusak kontras warna-warna itu,
                // jadi satu-satunya cara jujur adalah memaksa gelap.
                .preferredColorScheme(.dark)
                .onAppear {
                    state.connection.startPathMonitor()
                    if state.hasOnboarded { state.startAutoRefreshIfNeeded() }
                    // Cek izin saat app dibuka: yang belum beres langsung terlihat.
                    state.checkHealth()
                }
        }
        // Titlebar disembunyikan: kepala halaman (judul besar + Refresh) dibuat
        // sendiri di dalam konten, dan sidebar punya kepala sendiri. Tanpa ini
        // akan ada dua bar judul bertumpuk.
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            // Pindah layar tanpa harus Tab sampai ke sidebar. Sidebar sengaja
            // tidak bisa difokus (lihat `navButton` — cincin fokus macOS),
            // jadi tanpa pintasan ini navigasi papan ketik untuk sidebar
            // hilang begitu cincin fokus dimatikan.
            CommandMenu("Navigate") {
                ForEach(Array(navItems.enumerated()), id: \.element.id) { idx, item in
                    Button {
                        state.navigation = item.id
                    } label: {
                        Text(LocalizedStringKey(item.titleKey))
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(idx + 1)")), modifiers: .command)
                }
            }
            // `CommandMenu` dan `Button` di dalam `.commands` TIDAK ikut
            // lokalisasi otomatis SwiftUI (hanya `Text`/view yang biasanya).
            // Jadi judulnya harus lewat `L10n.string` secara eksplisit —
            // sebelumnya "Servers" / "Refresh" / "PingAll" ditulis literal
            // dan tetap bahasa Inggris walau app sudah Bahasa Indonesia.
            CommandMenu(L10n.string("nav_servers")) {
                Button(L10n.string("action_refresh")) { Task { await state.refreshAll() } }
                    .keyboardShortcut("r", modifiers: .command)
                Button(L10n.string("ping_all_action")) { Task { await state.pingAll() } }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
            }
        }

        MenuBarExtra(menuTitle, systemImage: menuIcon) {
            MenuBarView()
                .environmentObject(state)
                .id(state.settings.uiScalePercent)
        }
    }

    private var menuTitle: String {
        switch state.connection.status {
        case .connected: return NSLocalizedString("menubar_connected", comment: "")
        case .connecting, .disconnecting: return NSLocalizedString("menubar_working", comment: "")
        default: return "FreePN"
        }
    }
    private var menuIcon: String {
        switch state.connection.status {
        case .connected: return "shield.fill"
        case .connecting, .disconnecting: return "shield.lefthalf.filled"
        default: return "shield"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var state: AppState
    private var selection: Binding<String?> {
        Binding(get: { state.navigation }, set: { state.navigation = $0 ?? "connect" })
    }
    /// Mengambil kembali fokus pertama-responder dari tombol pertama saat
    /// jendela dibuka.
    ///
    /// PENYEBAB (D60b): SwiftUI di macOS "beri fokus" ke tombol pertama yang
    /// bisa difokus (tombol Segarkan di header Sambung), lalu macOS
    /// menggambar cincin fokus abu-abu di atas outline mint tombol itu.
    /// Sekali tampil, cincin tidak hilang sampai user mennekannya atau pindah
    /// tab — persis bug "tombol segarkan ada outline abu".
    ///
    /// PERBAIKAN: sesudah jendela terpasang, tarik fokus kembali ke window
    /// (`makeFirstResponder(nil)`). Berbeda dengan `.focusable(false)`, cara
    /// ini tidak mencabut kemampuan Tab ke setiap tombol — milik D59 tetap
    /// utuh — hanya tidak lagi ada tombol yang otomatis jadi first responder
    /// saat window tampil pertama kali. `DispatchQueue.main.async` karena
    /// NSWindow resmi first-responder-nya belum terpasang di dalam body.
    var body: some View {
        Group {
            if !state.hasOnboarded {
                OnboardingView()
            } else {
                // Sidebar digambar sendiri, bukan `NavigationSplitView`:
                // desain meminta kepala bermerek (logo + nama + tagline),
                // butir nav berbentuk pil mint, dan kartu "open source" di kaki — yang
                // tidak bisa dicapai lewat `List` sidebar bawaan.
                HStack(spacing: 0) {
                    SidebarView(selection: selection)
                        .frame(width: Theme.sidebarWidth)
                    Rectangle()
                        .fill(Palette.border)
                        .frame(width: 1)
                    detail
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .freepnBackdrop()
        .background(WindowFocusCleaner())
    }

    @ViewBuilder
    private var detail: some View {
        switch state.navigation {
        case "servers": ServersView()
        case "sources": SourcesView()
        case "split": SplitTunnelView()
        case "mac": MacSpoofView()
        case "settings": SettingsView()
        default: ConnectView(selection: selection)
        }
    }
}

/// NSView sekali-pakai: saat window sudah tampil, tarik fokus kembali ke
/// window — tidak ada tombol yang otomatis jadi first responder saat app
/// dibuka, jadi tidak ada cincin fokus abu-abu di tombol "Segarkan".
///
/// Kenapa begitu rumit: SwiftUI tidak membuka API "jangan beri fokus
/// awal". Parenting lewat `.background()` menjamin view ini ada di dalam
/// window yang sama. `makeFirstResponder(nil)` dijalankan pada runloop
/// berikutnya karena first responder baru terpasang setelah view hierarchy
/// siap.
struct WindowFocusCleaner: View {
    var body: some View {
        GeometryReader { geo in
            Color.clear
                .frame(width: 0, height: 0)
                .background(FocusResetAnchor())
        }
    }
}

struct FocusResetAnchor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { [weak v] in
            guard let w = v?.window else { return }
            w.makeFirstResponder(nil)
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Sidebar

/// Satu entri navigasi. Di level file, bukan di dalam `SidebarView`, karena
/// `CommandMenu` di `.commands` juga butuh urutan yang sama persis — kalau
/// tidak, ⌘1 bisa membuka layar yang berbeda dari tombol pertama di sidebar.
struct NavItem: Identifiable {
    let id: String
    let symbol: String
    let titleKey: String
}

let navItems: [NavItem] = [
    NavItem(id: "connect", symbol: "power", titleKey: "nav_connect"),
    NavItem(id: "servers", symbol: "server.rack", titleKey: "nav_servers"),
    NavItem(id: "sources", symbol: "cloud", titleKey: "nav_sources"),
    NavItem(id: "split", symbol: "arrow.triangle.branch", titleKey: "nav_split"),
    NavItem(id: "mac", symbol: "cpu", titleKey: "nav_mac"),
    NavItem(id: "settings", symbol: "gearshape", titleKey: "nav_settings"),
]

struct SidebarView: View {
    @Binding var selection: String?

    private var items: [NavItem] { navItems }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brandHeader
            VStack(spacing: 4) {
                ForEach(items) { item in
                    navButton(item)
                }
            }
            .padding(.horizontal, 10)
            // Cincin fokus macOS memakai warna aksen. Tanpa `.tint`, pil
            // navigasi yang aktif dapat cincin putih yang menonjol di atas
            // latar gelap.
            .tint(Palette.mint)
            Spacer(minLength: 12)
            openSourceCard
        }
        .padding(.top, Theme.trafficLightInset)
        .padding(.bottom, 14)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            LinearGradient(colors: [Palette.navy.opacity(0.95), Palette.abyss.opacity(0.92)],
                           startPoint: .top, endPoint: .bottom)
        )
    }

    private var brandHeader: some View {
        HStack(spacing: 11) {
            BrandMark(size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text("FreePN")
                    .font(Theme.scaled(19, weight: .bold))
                    .foregroundColor(Palette.textPrimary)
                Text("app_tagline")
                    .font(Theme.scaled(10.5))
                    .foregroundColor(Palette.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 20)
    }

    private func navButton(_ item: NavItem) -> some View {
        let active = selection == item.id
        return Button {
            selection = item.id
        } label: {
            HStack(spacing: 11) {
                Image(systemName: item.symbol)
                    .font(.system(size: 15 * Theme.uiScale, weight: .medium))
                    .frame(width: 20)
                Text(LocalizedStringKey(item.titleKey))
                    .font(Theme.font(.callout))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundColor(active ? Palette.textPrimary : Palette.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(active ? Palette.mint.opacity(0.16) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(active ? Palette.mint.opacity(0.55) : Color.clear,
                                  lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Cincin fokus macOS muncul di item PERTAMA yang bisa difokus saat
        // jendela dibuka — di sini selalu "Connect", meski layar aktif
        // adalah Settings. Warnanya abu-abu, bukan mint, dan membingungkan:
        // terlihat seperti ada dua keadaan aktif sekaligus.
        //
        // `.focusEffectDisabled()` hanya ada sejak macOS 14, sedangkan
        // project ini dibangun dengan Xcode 14.3.1 (SDK macOS 13), jadi
        // satu-satunya cara yang tersedia adalah `.focusable(false)`.
        // Navigasi papan ketik tidak hilang: ada ⌘1…⌘6 di menu Navigate.
        .focusable(false)
    }

    private var openSourceCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 15 * Theme.uiScale, weight: .medium))
                .foregroundColor(Palette.mint)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Palette.mint.opacity(0.14)))
            VStack(alignment: .leading, spacing: 1) {
                Text("brand_open_source")
                    .font(Theme.scaled(11, weight: .semibold))
                    .foregroundColor(Palette.textPrimary)
                Text("brand_privacy_matters")
                    .font(Theme.scaled(10))
                    .foregroundColor(Palette.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Palette.navyDeep.opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Palette.border.opacity(0.8), lineWidth: 1)
        )
        .padding(.horizontal, 14)
    }
}