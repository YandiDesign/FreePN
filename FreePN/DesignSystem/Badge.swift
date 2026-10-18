import SwiftUI

/// Badge protokol kapsul berteks (jangan andalkan warna saja).
public struct ProtocolBadge: View {
    public var proto: NodeProtocol
    public init(_ proto: NodeProtocol) { self.proto = proto }

    public var body: some View {
        Text(proto.badgeTitle)
            .font(Theme.overline)
            .foregroundColor(Palette.abyss)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule(style: .continuous).fill(color))
            .accessibilityLabel(proto.badgeTitle)
    }

    /// Warna kapsul protokol sesuai desain: VMess biru, Trojan merah,
    /// SS ungu, VLESS tosca, HY2 oranye. HTTP/SOCKS netral — keduanya proxy
    /// tanpa enkripsi transport, jadi tidak boleh berwarna seolah-olah sekelas
    /// VLESS/Trojan.
    public var color: Color {
        switch proto {
        case .trojan: return Palette.protoTrojan
        case .vmess: return Palette.protoVMess
        case .shadowsocks: return Palette.protoSS
        case .vless: return Palette.protoVLESS
        case .hysteria2: return Palette.protoHY2
        case .http, .socks: return Palette.protoPlain
        }
    }
}

/// Pil status kecil: titik + teks (mis. "AKTIF" / "TIDAK TERSEDIA").
public struct StatusPill: View {
    private var text: LocalizedStringKey
    private var tint: Color
    private var filled: Bool

    public init(_ text: LocalizedStringKey, tint: Color, filled: Bool = true) {
        self.text = text
        self.tint = tint
        self.filled = filled
    }

    public var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
            Text(text)
                .font(Theme.overline)
                .foregroundColor(tint)
                // Kapsul tidak boleh melar jadi dua baris ("Unavailable" ->
                // "Unavailabl e") saat kolom tabel sedang sempit.
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(tint.opacity(filled ? 0.16 : 0.08))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(tint.opacity(filled ? 0.45 : 0.22), lineWidth: 1)
        )
    }
}

/// Chip filter (Semua / VMess / Trojan / SS …). Dipakai di Servers, Split,
/// dan daftar server di layar Sambung — satu komponen, tiga pemakai.
public struct FilterChip: View {
    private var title: Text
    private var selected: Bool
    private var action: () -> Void

    public init(_ title: LocalizedStringKey, selected: Bool, action: @escaping () -> Void) {
        self.title = Text(title)
        self.selected = selected
        self.action = action
    }

    /// Varian untuk teks yang BUKAN kunci lokalisasi — nama protokol
    /// ("VMess", "Trojan") adalah nama sendiri, bukan kalimat. `Text(verbatim:)`
    /// supaya tidak ikut dicari di tabel terjemahan.
    ///
    /// Label eksplisit `title:` supaya tidak bentrok dengan init di atas saat
    /// ada string literal polos.
    public init(title: String, selected: Bool, action: @escaping () -> Void) {
        self.title = Text(verbatim: title)
        self.selected = selected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            title
                .font(Theme.font(.callout))
                .foregroundColor(selected ? Palette.abyss : Palette.textSecondary)
                // Chip tidak boleh membelah jadi dua baris ("VMess" -> "V Me
                // ss") dan tidak boleh dikompres HStack: label protokol
                // pendek dan selalu harus terbaca utuh.
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 15)
                .padding(.vertical, 7)
                .background(
                    Capsule(style: .continuous)
                        .fill(selected ? AnyShapeStyle(Palette.mint)
                              : AnyShapeStyle(Palette.navyDeep.opacity(0.6)))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(selected ? Color.white.opacity(0.32) : Palette.border,
                                      lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .animation(.easeOut(duration: 0.15), value: selected)
    }
}

/// Bintang favorit. Isian emas kalau aktif (bukan kuning sistem, supaya
/// nyambung dengan palet).
public struct FavoriteStar: View {
    private var active: Bool
    private var size: CGFloat
    private var action: () -> Void

    public init(active: Bool, size: CGFloat = 15, action: @escaping () -> Void) {
        self.active = active
        self.size = size
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: active ? "star.fill" : "star")
                .font(.system(size: size, weight: .medium))
                .foregroundColor(active ? Palette.warning : Palette.textTertiary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(active ? "active_favorite" : "inactive_favorite")
    }
}

/// Sel latensi: ikon sinyal + angka milidetik, diwarnai menurut bandwidth
/// (hijau cepat, biru sedang, oranye lambat).
public struct LatencyCell: View {
    private var ms: Int?
    private var dead: Bool
    /// Angka ini batas atas (probe UDP Hysteria2 di mode ping cepat), bukan
    /// RTT terukur. Ditandai "≤" supaya tidak dibaca sebagai latensi asli —
    /// menampilkan angka polosnya akan berdusta soal apa yang terukur.
    private var approximate: Bool

    public init(ms: Int?, dead: Bool = false, approximate: Bool = false) {
        self.ms = ms
        self.dead = dead
        self.approximate = approximate
    }

    public var body: some View {
        if let ms = ms {
            HStack(spacing: 5) {
                Image(systemName: approximate ? "bolt.horizontal.circle" : "chart.bar.fill")
                    .font(.system(size: 10 * Theme.uiScale, weight: .semibold))
                    .foregroundColor(tint(ms))
                // .formatted(): ribuan pakai pemisah non-breaking — "1.313"
                // jauh lebih mudah dibaca daripada "1313" pada tabel 16.000
                // baris, tanpa mengubah keterbacaan "93".
                Text(ms.formatted())
                    .font(Theme.font(.callout, design: .monospaced))
                    .foregroundColor(tint(ms))
                    .monospacedDigit()
                    .lineLimit(1)
                Text(approximate ? "latency_upper_bound" : "ms")
                    .font(Theme.font(.caption2))
                    .foregroundColor(Palette.textTertiary)
                    .lineLimit(1)
            }
            // D96: penanda "≤" saja TIDAK cukup. Ia abu-abu, kecil, dan di
            // ujung baris yang sudah padat — pada skala cell ini satu angka
            // hijau + "≤" abu-abu dibaca persis sama dengan RTT terukur, dan
            // itulah yang membuat user percaya node-nya sehat padahal hanya
            // portnya yang terbuka. Latar kusam membuat perbedaan itu tidak
            // bergantung pada apakah user sedang memperhatikan.
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(approximate ? Palette.well : Color.clear)
            )
            .help(approximate
                  ? L10n.string("latency_approx_help")
                  : L10n.string("latency_measured_help"))
        } else if dead {
            HStack(spacing: 5) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 10 * Theme.uiScale, weight: .semibold))
                Text("no_internet_short")
                    .font(Theme.font(.caption))
                    .lineLimit(1)
            }
            .foregroundColor(Palette.danger)
        } else {
            Text("—").foregroundColor(Palette.textTertiary)
        }
    }

    /// Warna angka. Hijau berarti "terukur dan bagus" — jadi angka yang
    /// HANYA batas atas handshake TCP tidak boleh dapat hijau sama sekali
    /// (D96). Warnanya diturunkan satu tingkat supaya "seperti RTT bagus"
    /// tidak mungkin terjadi walau user mengabaikan semua penanda lain.
    private func tint(_ ms: Int) -> Color {
        if approximate {
            return ms <= 400 ? Palette.textSecondary : Palette.warning
        }
        if ms < 150 { return Palette.success }
        if ms <= 400 { return Palette.textPrimary }
        return Palette.warning
    }
}

/// Beban relatif sebuah server, dihitung dari latensi relatif terhadap
/// server tercepat yang sudah diuji.
///
/// PENTING: ini BUKAN metrik beban yang dilaporkan penyedia server — feed
/// gratis tidak menyediakan angka itu. Yang ditampilkan adalah "server ini
/// jauh lebih lambat daripada yang terbaik milikmu", dan tooltip menyatakan
/// itu terus terang supaya tidak dibaca sebagai "server sedang sibuk".
///
/// Kalau belum ada pengukuran sama sekali, tidak ada yang ditampilkan —
// "0%" akan terbaca sebagai hasil ukur, padahal artinya "tidak diketahui".
public struct LoadBar: View {
    private var fraction: Double
    private var measured: Bool

    public init(fraction: Double, measured: Bool = true) {
        self.fraction = max(0, min(1, fraction))
        self.measured = measured
    }

    public var body: some View {
        if !measured {
            Text("—").foregroundColor(Palette.textTertiary)
                .frame(width: 92, alignment: .leading)
        } else {
            HStack(spacing: 8) {
                Text("\(Int((fraction * 100).rounded()))%")
                    .font(Theme.font(.caption, design: .monospaced))
                    .foregroundColor(Palette.textSecondary)
                    .monospacedDigit()
                    .frame(width: 34, alignment: .trailing)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Palette.well)
                        Capsule()
                            .fill(LinearGradient(colors: [tint.opacity(0.85), tint],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(4, geo.size.width * fraction))
                    }
                }
                .frame(height: 6)
            }
            // Lebar ini harus cocok dengan slot kolom Beban di ServersView.
            .frame(width: 92)
        }
    }

    private var tint: Color {
        switch fraction {
        case ..<0.34: return Palette.success
        case ..<0.67: return Palette.mint
        default: return Palette.warning
        }
    }
}

/// Kolom label tabel (Country / Protocol / Latency …).
public struct ColumnLabel: View {
    private var title: LocalizedStringKey
    private var align: Alignment

    public init(_ title: LocalizedStringKey, align: Alignment = .leading) {
        self.title = title
        self.align = align
    }

    public var body: some View {
        Text(title)
            .font(Theme.columnLabel)
            .foregroundColor(Palette.textTertiary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: align)
    }
}

/// Kartu angka besar + keterangan kecil.
public struct MetricTile: View {
    private var symbol: String
    private var label: LocalizedStringKey
    private var value: String
    private var footnote: String?
    private var tint: Color

    public init(symbol: String, label: LocalizedStringKey,
                value: String, footnote: String? = nil,
                tint: Color = Palette.mint) {
        self.symbol = symbol
        self.label = label
        self.value = value
        self.footnote = footnote
        self.tint = tint
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 10 * Theme.uiScale, weight: .semibold))
                    .foregroundColor(tint)
                Text(label)
                    .font(Theme.font(.caption2))
                    .foregroundColor(Palette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Text(value)
                .font(Theme.font(.title3, design: .rounded))
                .foregroundColor(Palette.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let footnote = footnote {
                Text(footnote)
                    .font(Theme.font(.caption2))
                    .foregroundColor(Palette.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Palette.navyDeep.opacity(0.65))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Palette.border.opacity(0.7), lineWidth: 1)
        )
    }
}

/// Grafik garis mini untuk riwayat laju trafik.
///
/// D76 — ditulis ulang penuh. Yang sebelumnya salah bukan soal
/// optimasi, tapi soal desain.
///
/// APA YANG SEBELUMNYA MENYEBABKAN "BERHENTI LALU MELOMPAT":
/// view ini menerima `[Double]` dan memasang `.animation(.easeOut(1.4),
/// value: samples)`. Tiap sampel baru (setiap 2 detik) MEMULAI animasi baru
/// yang mengubah SELURUH path selama 1,4 detik — lalu diam 0,6 detik
/// menunggu sampel berikutnya. Pola itu bukan "grafik bergerak", tapi "grafik
/// mengaduk lalu berhenti" berulang. Setiap animasi juga membangun ulang path
/// dari nol, sehingga interpolasi bawaan semuanya terbuang.
///
/// APA YANG SEKARANG:
/// - Satu socket permanen memberi sampel **1 Hz** (diverifikasi: sing-box
///   1.12.1 mengirim `/traffic` tepat tiap 1,000 detik, tanpa knob config).
/// - `TimelineView(.animation)` menggambar ulang di refresh rate display, jadi
///   gerakan dihitung ulang ~60×/detik dari waktu nyata, bukan dari animasi
///   yang dijadwalkan SwiftUI.
/// - Sumbu X berbasis **waktu**: setiap sampel punya cap waktu, jadi garis
///   menggeser sendiri secara kontinu. Tidak ada yang perlu dianimasikan.
/// - Interpolasi vertikal di antara dua sampel nyata, plus easing singkat saat
///   sampel terbaru tiba — tanpa menebak nilai yang belum terukur.
///
/// Catatan jujur soal target "100–250 ms sampling": sumber data (`/traffic`)
/// hanya 1 Hz dan itu BUKAN knob yang bisa diubah. Polling 4–10×
/// lebih cepat tidak menambah data — ia hanya membaca angka yang sama lebih
/// sering. Yang bisa dicapai adalah 1 Hz akurat + interpolasi 60 fps, dan itu
/// yang dikerjakan di sini.
public struct Sparkline: View {
    private let series: TrafficSeries
    /// Seri kedua yang digambar di plot yang sama (D78). `nil` = grafik tunggal.
    private let secondary: TrafficSeries?
    private let tint: Color
    private let secondaryTint: Color

    /// Jendela waktu yang terlihat, dalam detik.
    ///
    /// 60 detik pada sumber 1 Hz = ±60 titik. Cukup untuk melihat pola
    /// unduhan tanpa membuat kurva terlalu rapat.
    public static let window: TimeInterval = 60

    /// Lama sampel terbaru "naik" ke posisi finals-nya, dalam detik.
    ///
    /// Tanpa ini, y dari sampel terbaru melompat 1×/detik dan itu terlihat
    /// sebagai gunshot kecil di ujung garis. Nilainya pendek supaya tidak
    /// terasa lambat: efeknya "menyelesaikan" gerakan, bukan menunda data.
    private static let settleIn: TimeInterval = 0.22

    /// Ruang kosong di kiri jendela: supaya garis lama tidak langsung hilang
    /// begitu keluar, tapi juga tidak menumpuk di tepi.
    private static let leftPad: TimeInterval = 1.5

    public init(series: TrafficSeries, tint: Color = Palette.mint,
                secondary: TrafficSeries? = nil, secondaryTint: Color = Palette.info) {
        self.series = series
        self.tint = tint
        self.secondary = secondary
        self.secondaryTint = secondaryTint
    }

/// Skala Y yang sudah diredam (D79) — peak-hold: cepat naik, pelan turun.
    ///
    /// Sengaja TIDAK `private(set)`-hanya: `reset()` dipakai saat sesi
    /// direset supaya grafik tidak mewarisi skala lama.
    @State private var yScale = TrafficYScale()

    public var body: some View {
        // `.animation` = jadwal refresh-rate display (60 Hz di layar modern).
        // Closure-nya jalan tiap frame; di dalamnya hanya aritmetika ringan
        // over ≤ 128 sampel per seri, tanpa alokasi besar.
        TimelineView(.animation) { ctx in
            GeometryReader { geo in
                let now = ctx.date.timeIntervalSince1970
                // Puncak mentah dari jendela bergeser -> SANGAT berdenyut.
                // D79: diredam peak-hold dulu sebelum dipakai sebagai skala,
                // kalau tidak seluruh garis melompat vertikal tiap detik.
                let observed = max(Self.visiblePeak(series, now: now),
                                   secondary.map { Self.visiblePeak($0, now: now) } ?? 0)
                let peak = yScale.update(observed: observed, now: now)
                let (primary, second) = Self.points(series, secondary,
                                                     now: now, size: geo.size,
                                                     peak: peak)
                ZStack(alignment: .bottom) {
                    // Isi digambar lebih dulu agar garis berada di atasnya.
                    if primary.count > 1 {
                        filledPath(primary, height: geo.size.height)
                            .fill(LinearGradient(colors: [tint.opacity(0.28), tint.opacity(0.02)],
                                                 startPoint: .top, endPoint: .bottom))
                        smoothPath(primary)
                            .stroke(tint, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                    }
                    // Seri kedua: GARIS SAJA tanpa isi. Dua gradient yang
                    // bertumpuk membuat warna saling menutup dan grafik jadi
                    // kabut; satu garis biru di atas area hijau jauh lebih
                    // terbaca, dan tetap jelas itu arah upload.
                    if second.count > 1 {
                        smoothPath(second)
                            .stroke(secondaryTint, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                    }
                }
                // D80: dengan skala log, nilai sesaat bisa berada DI ATAS
                // puncak plot saat peak-hold masih menyusul ke bawah. Tanpa
                // `.clipped()` garis dan isinya akan bocor keluar kotak dan
                // menimpa kartu di atasnya.
                .clipped()
            }
        }
    }

/// Titik untuk SATU seri, dinormalisasi ke puncaknya sendiri.
    /// Dipakai test dan call site yang hanya butuh satu garis.
    static func points(_ series: TrafficSeries, now: TimeInterval,
                       size: CGSize, peak: Double? = nil) -> [CGPoint] {
        project(series, peak: peak, now: now, size: size)
    }

    /// Titik untuk DUA seri di satu plot — grafik gabungan D78.
    ///
    /// KEDUA seri memakai **satu skala Y yang sama** (puncak = max dari
    /// keduanya). Ini pilihan yang disengaja: kalau tiap garis dinormalisasi
    /// ke puncaknya sendiri, upload yang 20× lebih kecil dari download akan
    /// tergambar sama tinggi — dua kurva yang terlihat sebanding padahal sama
    /// sekali tidak. Skala bersama membuat "upload selalu jauh lebih kecil"
    /// terlihat apa adanya, dan itu informasi yang berguna.
    ///
    /// `secondary` tidak punya nilai default dengan sengaja: tanpa itu, call
    /// `points(s, now:size:)` jadi ambigu antara dua overload ini dan Swift
    /// menolaknya dengan pesan yang tidak membantu.
    static func points(_ series: TrafficSeries, _ secondary: TrafficSeries?,
                       now: TimeInterval, size: CGSize,
                       peak: Double? = nil) -> ([CGPoint], [CGPoint]) {
        guard let secondary else {
            return (project(series, peak: peak, now: now, size: size), [])
        }
        // Tanpa `peak` paksa: dua seri berbagi puncak gabungan mentah (dipakai test).
        // Dengan `peak`: dari TrafficYScale, yang sudah meredam denyutnya (dipakai view).
        let shared = peak ?? max(visiblePeak(series, now: now),
                                 visiblePeak(secondary, now: now), 1)
        return (project(series, peak: shared, now: now, size: size),
                project(secondary, peak: shared, now: now, size: size))
    }

/// Jendela untuk MENGAMBIL SKALA — sengaja jauh lebih pendek dari
    /// `window` (yang dipakai menggambar).
    ///
    /// D80: kalau skala diambil dari jendela 60 detik yang sama dengan gambar,
    /// satu burst sesaat (koneksi/TLS di awal speed test) menahan skala sampai
    /// burst itu KELUAR dari jendela — 60 detik. Selama itu trafik yang sedang
    /// berjalan tergambar gepeng di dasar dan grafik terlihat rusak, padahal
    /// datanya benar.
    ///
    /// Pisahkan keduanya: gambar tetap panjang (bentuk kurva enak dibaca),
    /// skala cepat mengikuti kondisi terbaru. Setelah burst lewat, grafik
    /// kembali menunjukkan trafik nyata dalam hitungan detik.
    static let scaleWindow: TimeInterval = 12

    /// Puncak seri dalam rentang tertentu.
    ///
    /// Ini input mentah untuk `TrafficYScale` — bukan skala final. Yang
    /// mentahlah yang "berdenyut"; peak-hold yang meredakannya.
    static func visiblePeak(_ s: TrafficSeries, now: TimeInterval,
                            window: TimeInterval? = nil) -> Double {
        guard s.count > 0 else { return 0 }
        var start = s.firstIndex(atOrAfter: now - (window ?? Self.scaleWindow))
        if start > 0 { start -= 1 }
        guard start < s.count else { return s.peak(from: 0) }
        return s.peak(from: start)
    }

    /// Proyeksi inti. `forcedPeak` = skala Y paksa (dipakai supaya dua seri
    /// berbagi sumbu, dan supaya `TrafficYScale` yang sudah meredam bisa
    /// dipakai); `nil` = pakai puncak seri sendiri.
    private static func project(_ series: TrafficSeries, peak forcedPeak: Double?,
                                now: TimeInterval, size: CGSize) -> [CGPoint] {
        guard size.width > 0, size.height > 0, series.count > 0 else { return [] }

        let window = Self.window
        let cutoff = now - window
        var start = series.firstIndex(atOrAfter: cutoff)
        // Satu sampel sebelum garis dimulai ikut digambar: tanpa itu kurva
        // mulai dari tengah layar dan tepi kirinya terlihat "terpotong" tiap detik.
        if start > 0 { start -= 1 }
        guard start < series.count else { return [] }

        // Puncak dihitung dari nilai RAW (bukan yang sedang di-ease), supaya
        // skala grafik tidak ikut bergerak-bergerak selama easing.
        //
        // D79: kalau `forcedPeak` diberikan, itu dipakai APA ADANYA. Versi
        // sebelumnya menulis `max(forcedPeak, series.peak(...))`, yang membuat
        // redaman jadi tidak berguna: begitu `TrafficYScale` mulai melepas
        // skala ke bawah, nilai mentah di sini langsung menyalakannya lagi
        // setiap frame, jadi kurva terus naik-turun persis seperti yang
        // dikeluhkan.
        let peak = max(forcedPeak ?? series.peak(from: start), 1)
        let newest = series.count - 1

        var pts: [CGPoint] = []
        pts.reserveCapacity(series.count - start + 2)
        // `-infinity`, bukan `-1`: titik pertama boleh punya x NEGATIF (lihat
        // catatan di bawah). Dengan awalan -1, titik itu justru terbuang.
        var lastX: CGFloat = -.infinity

        // D81 — sampel PERTAMA boleh berada sedikit di LUAR jendela, dengan
        // x-nya negatif, lalu dipotong `.clipped()`.
        //
        // Kenapa perlu: `start` sudah diarahkan satu sampel ke belakang
        // supaya kurva tidak terpotong di tepi kiri — tapi versi lama langsung
        // membuangnya lagi lewat `guard age < window`. Akibatnya jalur yang
        // digambar TIDAK PERNAH mencapai x = 0, dan antara x = 0 dan titik
        // paling kiri selalu ada celah. Lebar celah itu 0..(satu spasi sampel,
        // ~5px) dan kembar sekali per detik: ujung kanan terlihat halus,
        // ujung kiri terlihat "hilang per detik".
        //
        // Hanya SATU sampel yang boleh di luar jendela. Kalau jeda datanya
        // besar (misal setelah lama idle), sampel itu bisa jauh lebih tua —
        // dan menyambungkannya akan menggambar garis panjang yang tidak
        // pernah terjadi. Karena itu batasnya `edgeSlack` (10% jendela).
        let edgeSlack = window * 0.1

        for i in start..<series.count {
            let t = series.time(at: i)
            let age = now - t
            if age >= window {
                // Hanya sampel PERTAMA boleh di luar jendela. Setelah itu
                // semua sampel makin tua, jadi berhenti. Dan walau yang
                // pertama, jangan terlalu jauh: kalau jeda datanya besar,
                // sampel itu terlalu tua untuk dijahit secara jujur.
                if i > start || age >= window + edgeSlack { break }
            }
            let x = size.width * (1 - CGFloat(age / window))
            guard x > lastX else { continue }   // jaga urutan naik, buang duplikat

            var v = series.value(at: i)
            if i == newest, newest > start, age < Self.settleIn {
                // EASE-IN: sampel terbaru "datang" dari nilai sebelumnya.
                // Nilainya blend dari DUA NILAI NYATA, bukan tebakan.
                let prev = series.value(at: newest - 1)
                let f = max(0, age) / Self.settleIn
                v = prev + (v - prev) * f
            }
            // PETA LOGARITMA (D80).
            //
            // Sumbu linear tidak bisa menampilkan trafik yang melintasi 4
            // dekade: begitu ada satu burst, semua nilai normal berikutnya
            // tergambar gepeng di dasar. Di sini dasar plot = `peak/1000`
            // (3 dekade, lihat `TrafficYScale.decades`) dan puncak plot =
            // `peak`, jadi bentuk kurva tetap terbaca di skala apa pun.
            //
            // Nilai di bawah dasar dijepit ke dasar, BUKAN diekstrapolasi:
            // menampilkan bentuk yang tidak ada lebih menipu daripada
            // menamparkannya datar.
            let decades = TrafficYScale.decades
            let floor = peak / pow(10, decades)
            let frac = max(0, min(1,
                (log10(max(v, floor)) - log10(floor)) / decades))
            let y = size.height * (1 - CGFloat(frac) * 0.92)
            pts.append(CGPoint(x: x, y: y))
            lastX = x
        }

        // Ujung kanan DITAHAN di tepi dengan nilai terakhir.
        //
        // Tanpa ini ujung garis mundur ~lebar-satu-sampel setiap detik lalu
        // melompat maju begitu sampel berikutnya mendarat — persis denyut
        // "berhenti lalu melompat" yang dilaporkan. Segment datar pendek ini
        // jujur: di detik pecahan itu memang tidak ada data baru.
        if let last = pts.last, lastX < size.width {
            pts.append(CGPoint(x: size.width, y: last.y))
        }
        return pts
    }

    /// Catmull-Rom -> bezier dengan faktor 1/6.
    ///
    /// Garis menyentuh SETIAP titik data dan tidak pernah melembung melewati
    /// nilai di antara dua titik — penting untuk trafik: kurva tidak boleh
    /// menunjukkan lonjakan yang tidak pernah terjadi.
    private func smoothPath(_ pts: [CGPoint]) -> Path {
        var path = Path()
        guard let first = pts.first else { return path }
        path.move(to: first)
        guard pts.count > 2 else {
            if let last = pts.last { path.addLine(to: last) }
            return path
        }
        for i in 0..<(pts.count - 1) {
            let p0 = pts[max(i - 1, 0)]
            let p1 = pts[i]
            let p2 = pts[i + 1]
            let p3 = pts[min(i + 2, pts.count - 1)]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        return path
    }

    /// Area di bawah garis: kurva yang sama, ditutup ke tepi bawah.
    private func filledPath(_ pts: [CGPoint], height: CGFloat) -> Path {
        var path = smoothPath(pts)
        if let last = pts.last {
            path.addLine(to: CGPoint(x: last.x, y: height))
            path.addLine(to: CGPoint(x: pts[0].x, y: height))
            path.closeSubpath()
        }
        return path
    }
}

/// Kotak pencarian dengan ikon, gaya sama di semua layar.
public struct SearchField: View {
    private var placeholder: LocalizedStringKey
    @Binding private var text: String

    public init(_ placeholder: LocalizedStringKey, text: Binding<String>) {
        self.placeholder = placeholder
        self._text = text
    }

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12 * Theme.uiScale, weight: .medium))
                .foregroundColor(Palette.textTertiary)
            TextField("", text: $text, prompt: Text(placeholder).foregroundColor(Palette.textTertiary))
                .textFieldStyle(.plain)
                .foregroundColor(Palette.textPrimary)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Palette.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Palette.well)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 1)
        )
    }
}

/// Sakelar bergaya redesign (hijau, bukan biru sistem).
public struct MintToggle: View {
    @Binding private var isOn: Bool
    public init(isOn: Binding<Bool>) { self._isOn = isOn }

    public var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Capsule(style: .continuous)
                .fill(isOn ? Palette.mint : Palette.well)
                .frame(width: 42, height: 24)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle()
                        .fill(isOn ? Palette.abyss : Palette.textSecondary)
                        .frame(width: 18, height: 18)
                        .padding(.horizontal, 3)
                }
                .overlay(Capsule(style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.18), value: isOn)
    }
}

/// Lingkaran tombol daya besar: cincin berdenyut + glyph di tengah.
///
/// Bentuk denyutnya adalah **terang-redup (opacity)**, bukan rotasi — lihat
/// catatan D72 di `body`. Cincin hanya berdenyut saat `connecting`/
/// `disconnecting`; saat tersambung ia menyala hijau solid, saat terputus gelap.
public struct PowerRing: View {
    private var status: ConnectionStatus
    private var action: () -> Void

    /// Detak "terang-redup" untuk cincin.
    ///
    /// D72: MENGGANTIKAN rotasi. `Bool` yang di-flip sekali; animasi
    /// `repeatForever(autoreverses: true)` membuat opacity naik-turun
    /// selamanya, jadi tidak ada callback atau timer yang perlu dirawat.
    ///
    /// Kenapa bukan rotasi seperti D67/D71: cincin berputar terlihat "bekerja"
    /// tapi tidak memberi informasi baru — yang ditanyakan user adalah "apakah
    /// sedang connect", dan denyut terang-redup menjawabnya tanpa menuntut
    /// mata mengikuti gerakan. Layar yang diam juga tidak lagi bergerak.
    ///
    /// Pola sudut yang hanya naik (D67) sengaja dibuang: begitu rotasi hilang,
    /// kilatan-balik yang D67 perbaiki tidak mungkin terjadi. Opacity BERBOLEH
    /// naik-turun — di situlah justru efeknya.
    @State private var pulse = false

    public init(status: ConnectionStatus, action: @escaping () -> Void) {
        self.status = status
        self.action = action
    }

    /// Opacity cincin: denyut saat bekerja, PENUH saat diam.
    ///
    /// Penuh (bukan redup) saat tidak bekerja supaya tombol terputus tetap
    /// terbaca jelas sebagai "tekan untuk sambung", bukan terkecil hilang.
    nonisolated static func ringOpacity(working: Bool, pulse: Bool) -> Double {
        guard working else { return 1.0 }
        return pulse ? 1.0 : 0.35
    }

    public var body: some View {
        let working = (status == .connecting || status == .disconnecting)
        let live = status == .connected
        let tint = ringTint

        Button(action: action) {
            ZStack {
                // Halo luar.
                //
                // URUTAN WAJIB: `.blur()` SEBELUM `.frame()`. Kalau dibalik,
                // SwiftUI menyisihkan 196x196 lalu blur melebar jadi 224x224
                // — jauh di luar batas yang dipesan. Lapisan yang meluber itu
                // sesekali dirender bergeser (cincin + glow turun ke bawah),
                // dan karena cincin utama ada di ZStack yang sama, ia ikut
                // bergeser. Mengurutkan dengan benar membuat bleed pas di
                // dalam frame: 168 + 2 x 14 = 196.
                Circle()
                    .fill(tint.opacity(live ? 0.20 : 0.10))
                    .frame(width: 168, height: 168)
                    .blur(radius: 14)
                    .frame(width: 196, height: 196)

                // Cincin utama.
                //
                // D72: TIDAK ADA rotasi lagi. Yang tersisa adalah denyut
                // opacity terang-redup saat bekerja.
                //
                // Sejarahnya penting karena menjelaskan kenapa tidak ada
                // `rotationEffect` di sini sama sekali:
                //  - D67: `rotationEffect(working ? 360 : 0)` — saat `working`
                //    jadi false, nilainya turun 360° dan cincin terpuntir
                //    BALIK. Kilatan berputar tiap kali status berubah.
                //  - D67 (kedua): `phase` naik tanpa henti — kilatan hilang,
                //    tapi cincin berputar terus-menerus di semua status.
                //  - D71: spinner hanya saat bekerja — benar, tapi cincin
                //    berputar tetap tidak memberi informasi apa pun.
                //  - D72 (sekarang): rotasi dihapus total. Tanpa sudut yang
                //    berubah, kilatan-balik tidak mungkin terjadi; dan menyisakan
                //    kode rotasi yang mati hanya untuk "dijaga" hanya menambah
                //    permukaan bug tanpa fungsi.
                Circle()
                    .strokeBorder(
                        AngularGradient(
                            colors: [tint.opacity(0.25), tint, tint.opacity(0.85), tint.opacity(0.25)],
                            center: .center
                        ),
                        lineWidth: 7
                    )
                    .frame(width: 168, height: 168)
                    .opacity(Self.ringOpacity(working: working, pulse: pulse))
                    // `autoreverses: true` + `repeatForever` = denyut bolak-balik
                    // tanpa akhir. Animasi `nil` saat diam: opacity langsung
                    // penuh, tidak menyisakan denyut yang setengah jalan.
                    .animation(working
                               ? .easeInOut(duration: 1.1).repeatForever(autoreverses: true)
                               : nil, value: pulse)
                    .onAppear { pulse = working }
                    .onChange(of: working) { pulse = $0 }

                // Cincin dalam (aksen garis tipis).
                Circle()
                    .strokeBorder(Palette.border.opacity(0.8), lineWidth: 1)
                    .frame(width: 146, height: 146)

                Circle()
                    .fill(LinearGradient(colors: [Palette.navyDeep, Palette.well],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 132, height: 132)

                // SF Symbol "power" sudah orientasi benar (garis di atas) —
                // JANGAN diputar, kalau tidak ikonnya tampil terbalik.
                Image(systemName: "power")
                    .font(.system(size: 46, weight: .light))
                    .foregroundColor(live ? Palette.textPrimary : tint)
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(working)
        .accessibilityLabel(Text("action_connect"))
    }

    private var ringTint: Color {
        switch status {
        case .connected: return Palette.mint
        case .connecting, .disconnecting: return Palette.warning
        case .error: return Palette.danger
        case .disconnected: return Palette.mintDim
        }
    }
}

/// Cincin dekoratif untuk kartu MAC Address (ikon chip di tengah).
public struct HaloIcon: View {
    private var symbol: String
    public init(_ symbol: String) { self.symbol = symbol }

    public var body: some View {
        ZStack {
            // Sama seperti `PowerRing`: blur SEBELUM frame. 122 + 2 x 14 = 150,
            // jadi bleed-nya pas di dalam frame dan tidak pernah meluber.
            Circle().fill(Palette.mint.opacity(0.18))
                .frame(width: 122, height: 122)
                .blur(radius: 14)
                .frame(width: 150, height: 150)
            Circle()
                .strokeBorder(LinearGradient(colors: [Palette.mint.opacity(0.3), Palette.mint, Palette.mint.opacity(0.4)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing),
                              lineWidth: 7)
                .frame(width: 132, height: 132)
            Circle().strokeBorder(Palette.border.opacity(0.7), lineWidth: 1).frame(width: 116, height: 116)
            Circle()
                .fill(LinearGradient(colors: [Palette.navyDeep, Palette.well],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 106, height: 106)
            Image(systemName: symbol)
                .font(.system(size: 42, weight: .light))
                .foregroundColor(Palette.textPrimary)
        }
    }
}
/// Tombol Sambung per node dengan umpan balik keadaan: panah -> spinner ->
/// centang.
///
/// SATU komponen untuk SEMUA layar (tabel Server DAN kartu "Server
/// Direkomendasikan" di menu Sambung). Sebelumnya tiap layar punya
/// versinya sendiri, dan kartu rekomendasi tertinggal: tekan tombolnya
/// tidak ada spinner, tidak ada centang, dan tidak ada pengaman klik ganda —
/// persis keluhan "tidak ada icon loading dan ceklis".
///
/// Dibuat di DesignSystem (bukan di view) karena perbedaan itu tadi
///muncul dari menyalin logika, bukan dari api desain yang memang beda.
public struct NodeConnectButton: View {
    private var status: ConnectionStatus
    private var size: CGFloat
    private var action: () -> Void

    /// - Parameter size: diameter tombol. Kartu "Server Direkomendasikan"
    ///   pakai default (30) karena kartunya lapang, sedangkan baris tabel
    ///   Server memakai nilai lebih kecil: tabel punya 16.000 baris, tombol
    ///   sebesar itu bikin kolom Aksi terasa ramai dan mengganggu
    ///   bacaan tabel. Target klik tetap di atas 24pt rekomendasi Apple
    ///   karena diameter 26 ditambah ruang kosong di sel.
    public init(status: ConnectionStatus, size: CGFloat = 30,
                action: @escaping () -> Void) {
        self.status = status
        self.size = size
        self.action = action
    }

    private var busy: Bool { status == .connecting || status == .disconnecting }

    private var tint: Color {
        if status == .connected { return Palette.success }
        if busy { return Palette.mint }
        return Palette.textSecondary
    }

    /// `size` WAJIB diterapkan pada ZStack, bukan hanya pada glyph:
    /// `Circle()` tidak punya ukuran intrinsik, jadi tanpa frame di sini
    /// lingkarannya melar memenuhi ruang yang ditawarkan — di kartu
    /// "Server Direkomendasikan" (yang tidak punya pembatas lebar seperti
    /// kolom tabel) tombolnya jadi sebesar kartu itu sendiri.
    public var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Palette.navyDeep.opacity(0.65))
                if status == .connected {
                    Circle().fill(Palette.success.opacity(0.14))
                }
                glyph
                    .foregroundColor(tint)
            }
            // Frame di ZStack (bukan di glyph) supaya background, ikon, dan
            // pinggiran ikut kecil — tidak ada lagi yang bisa melebar sendiri.
            .frame(width: size, height: size)
            .overlay(Circle().strokeBorder(status == .connected
                                           ? Palette.success.opacity(0.55)
                                           : Palette.border, lineWidth: 1))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        // Cegah klik ganda: tiap percobaan baru me-reboot core, jadi
        // menumpuk percobaan hanya menambah kebisingan.
        .disabled(busy)
        .opacity(busy ? 0.85 : 1)
        .help(Text(Self.help(status)))
    }

    @ViewBuilder
    private var glyph: some View {
        switch status {
        case .connecting, .disconnecting:
            ProgressView()
                .controlSize(.small)
                .scaleEffect(size / 48)
        case .connected:
            Image(systemName: "checkmark")
                .font(.system(size: size * 0.40, weight: .bold))
        case .disconnected, .error:
            Image(systemName: "chevron.right")
                .font(.system(size: size * 0.40, weight: .semibold))
        }
    }

    static func help(_ status: ConnectionStatus) -> LocalizedStringKey {
        switch status {
        case .connecting: return "status_connecting"
        case .disconnecting: return "status_disconnecting"
        case .connected: return "action_disconnect"
        case .disconnected, .error: return "action_connect"
        }
    }
}
