import SwiftUI

/// Token warna FreePN.
///
/// SenGAJA satu palet gelap, bukan turunan dari warna sistem: desain adalah
/// laut malam (navy) dengan aksen mint. Warna diturunkan dari warna dasar
/// lewat `mix`, bukan ditulis hex terpisah, supaya tetap serasi kalau satu
/// warna dasar berubah.
public enum Palette {
    // MARK: - Dasar
    /// Latar jendela paling dalam (tepi).
    public static let abyss = Color(red: 0.016, green: 0.043, blue: 0.086)
    /// Latar panel utama.
    public static let navy = Color(red: 0.035, green: 0.086, blue: 0.157)
    public static let navyDeep = Color(red: 0.024, green: 0.063, blue: 0.122)

    // MARK: - Permukaan
    /// Isi kartu.
    public static let card = Color(red: 0.055, green: 0.125, blue: 0.208)
    /// Permukaan terangkat (header kartu, baris terpilih).
    public static let cardRaised = Color(red: 0.075, green: 0.169, blue: 0.267)
    /// Isi kolom/lekukan di dalam kartu.
    public static let well = Color(red: 0.031, green: 0.078, blue: 0.149)

    // MARK: - Garis
    /// Garis tepi kartu.
    public static let border = Color(red: 0.118, green: 0.239, blue: 0.376)
    /// Garis tipis untuk pemisah baris.
    public static let hairline = Color(red: 0.118, green: 0.239, blue: 0.376).opacity(0.55)

    // MARK: - Aksen
    /// Hijau mint utama (tombol, cincin power, status aktif).
    public static let mint = Color(red: 0.204, green: 0.882, blue: 0.706)
    public static let mintBright = Color(red: 0.310, green: 0.890, blue: 0.753)
    public static let mintDim = Color(red: 0.106, green: 0.459, blue: 0.400)

    // MARK: - Status
    public static let success = Color(red: 0.204, green: 0.827, blue: 0.600)
    public static let warning = Color(red: 0.961, green: 0.647, blue: 0.137)
    public static let danger = Color(red: 0.949, green: 0.333, blue: 0.353)
    public static let info = Color(red: 0.290, green: 0.549, blue: 0.965)

    // MARK: - Teks
    public static let textPrimary = Color(red: 0.925, green: 0.961, blue: 0.996)
    public static let textSecondary = Color(red: 0.612, green: 0.702, blue: 0.808)
    public static let textTertiary = Color(red: 0.400, green: 0.494, blue: 0.612)

    // MARK: - Protokol (sesuai kapsul di desain)
    public static let protoVMess = info
    public static let protoTrojan = Color(red: 0.937, green: 0.325, blue: 0.373)
    public static let protoSS = Color(red: 0.639, green: 0.365, blue: 0.937)
    public static let protoVLESS = Color(red: 0.180, green: 0.741, blue: 0.722)
    public static let protoHY2 = Color(red: 0.965, green: 0.549, blue: 0.208)
    /// HTTP CONNECT & SOCKS5 — proxy sederhana, bukan VPN modern. Dipakai warna
    /// netral jadi kapsulnya tidak dibaca sebagai "protokol utama" padahal
    /// tidak ada transport terenkripsi.
    public static let protoPlain = Color(red: 0.478, green: 0.557, blue: 0.667)
}

/// Gradien & latar global.
public enum Backdrop {
    /// Latar aplikasi: navy dalam + dua cahaya mint/biru di sudut.
    public static var gradient: some View {
        ZStack {
            LinearGradient(colors: [Palette.navyDeep, Palette.abyss],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Palette.mint.opacity(0.16), .clear],
                           center: .topLeading, startRadius: 0, endRadius: 620)
            RadialGradient(colors: [Palette.info.opacity(0.14), .clear],
                           center: .bottomTrailing, startRadius: 0, endRadius: 700)
        }
    }
}

public enum Theme {
    public static let cardRadius: CGFloat = 16
    public static let grid: CGFloat = 8

    /// Lebar sidebar tetap (lihat `FreePNApp`).
    public static let sidebarWidth: CGFloat = 236

    /// Lebar minimum jendela.
    ///
    /// Dua angka yang mengikat, dan keduanya naik karena redesign:
    ///
    /// 1. **Tabel Server** (D29/D52): jumlah lebar kolom tetap (bintang 34 +
    ///    negara 136 + sumber 104 + nama fleksibel + tipe 80 + latensi 92 +
    ///    beban 98 + aksi 58 = 602) harus menyisakan ruang layak untuk kolom
    ///    Nama di sidebar 236. Di bawah batas ini header kolom seperti
    ///    "Sumber"/"Tipe" akan terpotong — persis bug "Bend…" yang sudah pernah
    ///    terjadi (D29).
    /// 2. **Dashboard Sambung**: dua kolom (daya 260 + rekomendasi + peta)
    ///    dan tabel trafik harus muat di lebar isi.
    /// 3. **Tabel Sumber** (D60): kolom tetapnya telah bertambah — bintang 34 +
    ///    sumber 230 + status 120 + keterangan ≥220 + diperbarui 120 +
    ///    aktif 46 + aksi 98 = 868. Ditambah padding kartu & layar (28 + 44),
    ///    jendela minimum 1160 tidak lagi cukup: bar aksi tepi kanan
    ///    terdorong mepet dan sidebar ikut terasa terpotong.
    ///
    /// 1160 → 1240 (tinggi 700 → 760) hanya menaikkan batas bawah; tidak ada
    /// kolom tabel yang menyempit, jadi D29 tetap terpenuhi.
    public static let minWindowWidth: CGFloat = 1240
    public static let minWindowHeight: CGFloat = 760

    /// Ruang untuk tombol jendela (merah/kuning/hijau) di atas sidebar.
    public static let trafficLightInset: CGFloat = 28

    /// Skala UI global: 1.0 = normal, 1.1 = +10%, seterusnya.
    /// Ditulis dari `AppState` (baca `settings.uiScalePercent`), dibaca
    /// `Theme.font(...)` di seluruh view. Nilai SENGAJA statis: semua text
    /// style di app melewati fungsi yang sama, jadi satu angka ini cukup untuk
    /// menskalakan seluruh UI sekaligus.
    public static var uiScale: CGFloat = 1.0

    /// Font semantik yang mengikuti skala UI.
    ///
    /// Kenapa bukan `\.dynamicTypeSize`: di macOS environment itu sama sekali
    /// tidak mengubah ukuran teks (terbuka di app — nilai `.xLarge` terpasang,
    /// teks di layar tetap seukuran semula, piksel identik). `\.controlSize`
    /// juga hanya menyentuh sebagian kontrol. Jadi ukuran teks dihitung sendiri:
    /// ukuran baku dari sistem × skala UI.
    public static func font(_ style: Font.TextStyle, design: Font.Design? = nil) -> Font {
        .system(size: pointSize(style), weight: weight(style), design: design)
    }

    /// Ukuran akhir sebuah text style setelah dikali skala UI (1.0 = normal).
    /// Dipisah agar bisa diuji langsung — `Font` sendiri tidak bisa dibandingkan.
    public static func pointSize(_ style: Font.TextStyle) -> CGFloat {
        baseSize(style) * uiScale
    }

    private static func weight(_ style: Font.TextStyle) -> Font.Weight? {
        style == .headline ? .semibold : nil
    }

    /// Ukuran baku dari teks Apple untuk text style tsb (ikut setelan sistem
    /// bila user mengubahnya di Accessibility). SwiftUI tidak membuka API ini,
    /// jadi dipetakan manual.
    ///
    /// Di-cache. `NSFont.preferredFont(forTextStyle:)` melakukan lookup ke
    /// Text Services pada setiap pemanggilan, dan `Theme.font(...)` dipanggil
    /// untuk SETIAP teks di SETIAP body evaluation — tanpa cache itu setiap
    /// frame pays lookup untuk tiap teks (D61).
    ///
    /// Cache tidak perlu lock karena `preferredFont` hanya dibaca di main
    /// actor (dipanggil dari `body`).
    private static func baseSize(_ style: Font.TextStyle) -> CGFloat {
        if let hit = baseSizeCache[style] { return hit }
        let size = NSFont.preferredFont(forTextStyle: nsStyle(style)).pointSize
        baseSizeCache[style] = size
        return size
    }

    private static var baseSizeCache: [Font.TextStyle: CGFloat] = [:]

    /// Buang cache ukuran font. Wajib dipanggil setelah user mengubah
    ///pengaturan teks di System Settings saat app sedang berjalan — kalau tidak,
    /// ukuran lama akan tetap terpakai sampai app ditutup.
    public static func invalidateFontSizeCache() {
        baseSizeCache.removeAll()
    }

    private static func nsStyle(_ style: Font.TextStyle) -> NSFont.TextStyle {
        switch style {
        case .largeTitle: return .largeTitle
        case .title: return .title1
        case .title2: return .title2
        case .title3: return .title3
        case .headline: return .headline
        case .body: return .body
        case .callout: return .callout
        case .subheadline: return .subheadline
        case .footnote: return .footnote
        case .caption: return .caption1
        case .caption2: return .caption2
        @unknown default: return .body
        }
    }

    // MARK: - Ketik kustom
    //
    // `Font.TextStyle` hanya punya 10 anak dan tidak punya "display" atau
    // "overline". Judul layar & label kapsul butuh ukuran/weight yang tidak
    // ada di sana, jadi lewat `Theme.scaled(_:_:)` — tetap ikut UI scale.

    /// Ukuran tetap (piksel) yang ikut skala UI. Dipakai untuk judul layar,
    /// angka besar, dan label kecil yang tidak ada padanannya di TextStyle.
    public static func scaled(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size * uiScale, weight: weight)
    }

    /// Judul layar: besar, tebal, putih.
    public static var screenTitle: Font { scaled(30, weight: .bold) }
    /// Subjudul layar: warna kebiruan, ringan.
    public static var screenSubtitle: Font { scaled(14.5, weight: .medium) }
    /// Judul kartu.
    public static var cardTitle: Font { scaled(15, weight: .semibold) }
    /// Label kapsul mungil (mis. "AKTIF", "TROJAN").
    public static var overline: Font { scaled(10.5, weight: .bold) }
    /// Angka besar (mis. MAC address, laju unduhan).
    public static var metric: Font { scaled(26, weight: .semibold) }
    /// Label tabel.
    public static var columnLabel: Font { scaled(12, weight: .semibold) }

    /// Latar bar selang-seling untuk List panjang (Sumber, daftar app Split).
    /// Di palet baru baris bergaris sudah ditangani `FreePNTable`, jadi ini
    /// hanya untuk List yang belum dipindah — tetap ada supaya tidak ada
    /// referensi yang menggantung.
    public static var stripedRow: Color {
        Palette.cardRaised.opacity(0.45)
    }

    /// Teks yang harus menonjol: warna utama palet (bukan `.primary` sistem,
    /// yang berubah-ubah saat mode tampilan berubah).
    public static var strongText: Color { Palette.textPrimary }
    /// Teks sekunder.
    public static var secondaryText: Color { Palette.textSecondary }
}

// MARK: - Komponen dasar

/// Permukaan kartu: isian navy, garis tepi 1pt, radius `Theme.cardRadius`.
/// Semua kartu di aplikasi dibangun dari modifier ini supaya gradasi, radius,
/// dan garis tepinya benar-benar sama di enam layar.
public struct FreePNCard: ViewModifier {
    private var radius: CGFloat
    private var fill: Color
    private var padding: CGFloat
    private var elevated: Bool

    public init(radius: CGFloat = Theme.cardRadius,
                fill: Color = Palette.card,
                padding: CGFloat = 16,
                elevated: Bool = false) {
        self.radius = radius
        self.fill = fill
        self.padding = padding
        self.elevated = elevated
    }

    public func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: 1)
            )
            .overlay(alignment: .top) {
                // Cahaya tipis di tepi atas: efek "kaca" yang hinted di desain.
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(elevated ? 0.10 : 0.06),
                                  lineWidth: 1)
                    .mask(
                        LinearGradient(colors: [.black, .clear],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: radius * 2)
                    )
            }
            .shadow(color: Color.black.opacity(0.28), radius: 14, y: 6)
    }
}

public extension View {
    func freepnCard(radius: CGFloat = Theme.cardRadius,
                    fill: Color = Palette.card,
                    padding: CGFloat = 16,
                    elevated: Bool = false) -> some View {
        modifier(FreePNCard(radius: radius, fill: fill, padding: padding, elevated: elevated))
    }

    /// Latar aplikasi. Dipakai sekali, di paling atas pohon.
    func freepnBackdrop() -> some View {
        background(Backdrop.gradient.ignoresSafeArea())
    }
}

// MARK: - Judul layar

/// Kepala halaman: judul besar + subjudul di kiri, tombol aksi di kanan.
///
/// Dipakai keenam layar supaya "Good evening / Servers / Settings" terasa
/// satu keluarga, bukan enam header yang kebetulan mirip.
public struct ScreenHeader<Trailing: View>: View {
    private let title: LocalizedStringKey
    private let subtitle: LocalizedStringKey
    @ViewBuilder private let trailing: Trailing

    public init(_ title: LocalizedStringKey,
                subtitle: LocalizedStringKey,
                @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Theme.screenTitle)
                    .foregroundColor(Palette.textPrimary)
                Text(subtitle)
                    .font(Theme.screenSubtitle)
                    .foregroundColor(Palette.textTertiary)
            }
            Spacer(minLength: 12)
            trailing
        }
    }
}

public extension ScreenHeader where Trailing == EmptyView {
    init(_ title: LocalizedStringKey, subtitle: LocalizedStringKey) {
        self.init(title, subtitle: subtitle, trailing: { EmptyView() })
    }
}

// MARK: - Tombol

/// Tombol utama: gradien mint, teks gelap. Untuk satu aksi utama per kartu.
public struct PrimaryButtonStyle: ButtonStyle {
    private var tint: Color
    private var horizontal: CGFloat

    public init(tint: Color = Palette.mint, horizontal: CGFloat = 18) {
        self.tint = tint
        self.horizontal = horizontal
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.font(.headline))
            .foregroundColor(Palette.abyss)
            .padding(.horizontal, horizontal)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(LinearGradient(colors: [Palette.mintBright, tint],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Tombol sekunder: navy pekat dengan garis mint, teks mint.
public struct SecondaryButtonStyle: ButtonStyle {
    private var active: Bool
    public init(active: Bool = false) { self.active = active }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.font(.callout, design: .rounded))
            .foregroundColor(active ? Palette.abyss : Palette.mint)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(active ? AnyShapeStyle(Palette.mint) : AnyShapeStyle(Palette.navyDeep.opacity(0.7)))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(active ? Color.white.opacity(0.3) : Palette.mint.opacity(0.55),
                                  lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

/// Tombol netral (outline) untuk aksi sekunder di header.
public struct GhostButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.font(.callout))
            .foregroundColor(Palette.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(Palette.navyDeep.opacity(configuration.isPressed ? 0.9 : 0.55))
            )
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

/// Tombol bulat berisi simbol — "Refresh" dan "…" di kanan atas.
public struct RoundIconButtonStyle: ButtonStyle {
    private var active: Bool
    public init(active: Bool = false) { self.active = active }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.font(.callout))
            .foregroundColor(active ? Palette.abyss : Palette.textSecondary)
            .frame(width: 34, height: 34)
            .background(
                Circle().fill(active ? AnyShapeStyle(Palette.mint)
                              : AnyShapeStyle(Palette.navyDeep.opacity(0.65)))
            )
            .overlay(Circle().strokeBorder(active ? Color.white.opacity(0.3) : Palette.border,
                                           lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Kotak bulat berisi simbol — dipakai untuk ikon sel tabel (mis. logo sumber).
public struct IconTile: View {
    private var symbol: String
    private var size: CGFloat
    private var tint: Color

    public init(_ symbol: String, size: CGFloat = 30, tint: Color = Palette.mint) {
        self.symbol = symbol
        self.size = size
        self.tint = tint
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
            .fill(Palette.navyDeep.opacity(0.8))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                    .strokeBorder(tint.opacity(0.35), lineWidth: 1)
            )
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.46, weight: .medium))
                    .foregroundColor(tint)
            )
            .frame(width: size, height: size)
    }
}

/// Logo FreePN. Falls back ke glyph SF Symbol bila asset belum ter-build.
public struct BrandMark: View {
    private var size: CGFloat
    public init(size: CGFloat = 34) { self.size = size }

    public var body: some View {
        Image("BrandMark")
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
    }
}

// MARK: - Kolom nilai

/// Baris label–nilai di dalam kartu pengaturan/ringkasan: label di kiri,
/// kendali di kanan, judul dan keterangan ditumpuk.
public struct SettingRow<Control: View>: View {
    private let title: LocalizedStringKey
    private let detail: LocalizedStringKey
    @ViewBuilder private let control: Control

    public init(_ title: LocalizedStringKey,
                detail: LocalizedStringKey,
                @ViewBuilder control: () -> Control) {
        self.title = title
        self.detail = detail
        self.control = control()
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.font(.callout))
                    .foregroundColor(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(Theme.font(.caption))
                    .foregroundColor(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Label mendapat sisa ruang; kendali punya lebar tetap. Tanpa
            // ini HStack membagi rata dan judul panjang jadi terpotong elipsis
            // ("Auto-refresh subscri…").
            .frame(maxWidth: .infinity, alignment: .leading)
            control
                .frame(maxWidth: 190, alignment: .trailing)
        }
        .padding(.vertical, 7)
    }
}

public extension SettingRow where Control == EmptyView {
    init(_ title: LocalizedStringKey, detail: LocalizedStringKey) {
        self.init(title, detail: detail, control: { EmptyView() })
    }
}

/// Pemisah satu piksel antar baris di dalam kartu.
public struct Hairline: View {
    public init() {}
    public var body: some View {
        Rectangle()
            .fill(Palette.hairline)
            .frame(height: 1)
    }
}

/// Dropdown bergaya redesign (label + chevron, menu native untuk perilakunya).
///
/// Kenapa bukan `Picker` + `.pickerStyle(.menu)`: pada macOS 13 popup bawaan
/// masih menggambar isian terang sistem, sehingga muncul kotak abu-abu terang
/// di tengah kartu gelap — satu-satunya kontrol yang tidak menyatu dengan
/// palat. Menu menyimpan perilaku native (satu klik, keyboard, VoiceOver)
/// sementara seluruhpenampilannya digambar sendiri.
///
/// Label dikembalikan sebagai `Text` supaya pemanggil bebas memakai kunci
/// lokalisasi (`LocalizedStringKey`) maupun teks verbatim.
public struct DropdownMenu<Value: Hashable>: View {
    private let options: [Value]
    private let label: (Value) -> Text
    @Binding private var selection: Value

    public init(options: [Value],
                label: @escaping (Value) -> Text,
                selection: Binding<Value>) {
        self.options = options
        self.label = label
        self._selection = selection
    }

    public var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button {
                    selection = option
                } label: {
                    HStack {
                        label(option)
                        if option == selection {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 7) {
                label(selection)
                    .font(Theme.font(.callout))
                    .foregroundColor(Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9 * Theme.uiScale, weight: .bold))
                    .foregroundColor(Palette.textTertiary)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Palette.well)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(maxWidth: 190, alignment: .trailing)
    }
}

/// Judul kartu dengan ikon di kiri.
///
/// Judul dipaksa satu baris: kolom kartu di dashboard sempit, dan judul dua
/// baris ("Recommend / ed Server") terlihat rusak. Kalau tidak muat, teks
/// diperkecil dulu sebelum boleh terpotong.
public struct CardHeader: View {
    private let symbol: String
    private let title: LocalizedStringKey
    public init(_ symbol: String, _ title: LocalizedStringKey) {
        self.symbol = symbol
        self.title = title
    }

    public var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13 * Theme.uiScale, weight: .semibold))
                .foregroundColor(Palette.mint)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Palette.mint.opacity(0.12)))
            Text(title)
                .font(Theme.cardTitle)
                .foregroundColor(Palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}