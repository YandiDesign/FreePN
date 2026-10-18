import Foundation

/// Tebak kode negara dari emoji bendera / kode di nama node.
public enum CountryInfer {
    public static func infer(from name: String) -> String? {
        // 1. Kode dalam kurung: [US], (US).
        for re in bracketedRegexes {
            if let m = re.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
               let r = Range(m.range(at: 1), in: name) {
                let code = String(name[r]).uppercased()
                if names[code] != nil { return code }
            }
        }
        // 2. Emoji bendera: dua regional indicator -> kode negara.
        //
        // Slide window langsung di atas `unicodeScalars`, tanpa
        // `Array(name.unicodeScalars)` — alokasi array semua scalar dari nama
        // ini dijalankan sekali per node saat parsing (D61).
        var prev: UInt32? = nil
        for scalar in name.unicodeScalars {
            let v = scalar.value
            // WAJIB(range check dulu, baru konversi): `p - 0x1F1E6` pada
            // skalar biasa (mis. huruf ASCII 'A' = 0x41) UNDERFLOW UInt32 →
            // crash `arithmetic overflow`.
            if let p = prev,
               (0x1F1E6...0x1F1FF).contains(p), (0x1F1E6...0x1F1FF).contains(v),
               let c1 = UnicodeScalar(UInt32(65 + (p - 0x1F1E6))),
               let c2 = UnicodeScalar(UInt32(65 + (v - 0x1F1E6))) {
                return "\(Character(c1))\(Character(c2))"
            }
            prev = v
        }
        // 3. Nama negara non-Latin. Feed gratis terbesar menamai server dalam
        //    bahasa Mandarin (美国 001, 德国, 新加坡, 日本…). Tanpa langkah ini
        //    semua node dari feed itu berbendera 🌐.
        //
        //    Dilewati total untuk nama ASCII murni: 58× `String.contains` per
        //    node adalah pekerjaan sia-sia untuk nama seperti
        //    "US-Los Angeles 01" (kategori terbesar di feed gratis).
        if hasCJK(name) {
            for (zh, code) in chineseNamesSortedByLength where name.contains(zh) { return code }
        }
        // 4. Kode ISO telanjang (US, CA, RU) di batas kata.
        //    Divalidasi ke tabel `names` supaya tidak menebak: tanpa itu
        //    "IT" di dalam kata lain akan dibaca Italia, dan hampir semua
        //    dua huruf akan dianggap kode.
        if let m = bareCodeRegex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
           let r = Range(m.range(at: 1), in: name) {
            let code = String(name[r])
            if names[code] != nil { return code }
        }
        return nil
    }

    // MARK: - Regex & tabel (dibangun SEKALI)

    /// Regex dipakai `infer` untuk SETIAP node saat parsing feed. Sempat
    /// dikompilasi di dalam fungsi itu: ~90.000 kompilasi regex untuk feed
    /// 30.000 node. Sekarang dibangun sekali saat program dimuat (D61).
    private static let bracketedRegexes: [NSRegularExpression] = [
        "\\[([A-Za-z]{2})\\]",
        "\\(([A-Za-z]{2})\\)",
    ].map { try! NSRegularExpression(pattern: $0) }

    private static let bareCodeRegex: NSRegularExpression =
        try! NSRegularExpression(pattern: "(?<![A-Za-z])([A-Z]{2})(?![A-Za-z])")

    /// Nama Mandarin diurutkan PANJANG KE PENDEK.
    ///
    /// Urutan itu wajib benar, bukan sekadar preferensi: `印度尼西亚`
    /// (Indonesia) mengandung `印度` (India). Dengan urutan tabel aslinya,
    /// `印度` diperiksa lebih dulu dan node Indonesia diberi bendera India.
    private static let chineseNamesSortedByLength: [(String, String)] =
        chineseNames.sorted { $0.0.count > $1.0.count }

    /// Apakah `s` punya satu pun karakter CJK? Menghemat seluruh loop
    /// Mandarin untuk nama ASCII.
    private static func hasCJK(_ s: String) -> Bool {
        for v in s.unicodeScalars where (0x4E00...0x9FFF).contains(v.value)
            || (0x3400...0x4DBF).contains(v.value) {
            return true
        }
        return false
    }

    /// Nama negara Mandarin -> ISO alpha-2.
    ///
    /// Dibatasi pada negara yang benar-benar muncul di feed gratis; menambah
    /// padanan yang tidak pernah dipakai hanya memperbesar tabel tanpa
    /// memperbaiki apa pun.
    static let chineseNames: [(String, String)] = [
        ("美国", "US"), ("加拿大", "CA"), ("英国", "UK"), ("德国", "DE"),
        ("法国", "FR"), ("荷兰", "NL"), ("比利时", "BE"), ("瑞士", "CH"),
        ("瑞典", "SE"), ("挪威", "NO"), ("丹麦", "DK"), ("芬兰", "FI"),
        ("波兰", "PL"), ("捷克", "CZ"), ("奥地利", "AT"), ("爱尔兰", "IE"),
        ("俄罗斯", "RU"), ("乌克兰", "UA"), ("立陶宛", "LT"), ("拉脱维亚", "LV"),
        ("爱沙尼亚", "EE"), ("罗马尼亚", "RO"), ("匈牙利", "HU"), ("希腊", "GR"),
        ("葡萄牙", "PT"), ("西班牙", "ES"), ("意大利", "IT"), ("土耳其", "TR"),
        ("中国", "CN"), ("香港", "HK"), ("澳门", "MO"), ("台湾", "TW"),
        ("日本", "JP"), ("韩国", "KR"), ("新加坡", "SG"), ("马来西亚", "MY"),
        ("泰国", "TH"), ("越南", "VN"), ("菲律宾", "PH"), ("印尼", "ID"),
        ("印度", "IN"), ("印度尼西亚", "ID"), ("巴基斯坦", "PK"), ("孟加拉", "BD"),
        ("斯里兰卡", "LK"), ("哈萨克斯坦", "KZ"), ("以色列", "IL"), ("伊朗", "IR"),
        ("沙特", "SA"), ("阿联酋", "AE"),
        ("澳大利亚", "AU"), ("澳洲", "AU"), ("新西兰", "NZ"),
        ("巴西", "BR"), ("阿根廷", "AR"), ("智利", "CL"), ("墨西哥", "MX"),
        ("南非", "ZA"), ("埃及", "EG"), ("尼日利亚", "NG"), ("肯尼亚", "KE")
    ]

    /// Bendera ISO alpha-2 sebagai emoji.
    ///
    /// Kolom Country di menu Server memakai ini — bendera lebih cepat dibaca
    /// daripada nama negara, dan di tabel 16.000 baris nama memakan ruang
    /// yang jauh lebih mahal daripada dua glyph.
    ///
    /// Kode yang tidak ada di `names` menghasilkan 🌐, bukan regional indicator
    /// apa adanya: 🇿🇿 untuk "ZZ" dirender sebagai huruf "ZZ", yang terlihat
    /// seperti bendera sungguhan padahal tidak ada negara seperti itu.
    public static func flagEmoji(for countryCode: String?) -> String {
        guard let cc = countryCode?.uppercased(), cc.count == 2,
              names[cc] != nil else { return "🌐" }
        let base: UInt32 = 0x1F1E6
        var s = ""
        for ch in cc.unicodeScalars {
            if let v = UnicodeScalar(base + ch.value - 65) { s += String(v) }
        }
        return s.isEmpty ? "🌐" : s
    }

    /// Nama negara yang bisa dibaca orang, dari kode ISO dua huruf.
    ///
    /// Dipakai sebagai tooltip kolom "Country / City" di Server dan kartu
    /// rekomendasi di Sambung. Bendera dibaca cepat, tapi tidak bisa dicari
    /// dan tidak bisa disalin; nama bisa.
    ///
    /// Murni & nonisolated supaya bisa diuji. Kode yang tidak ada di daftar
    /// dikembalikan apa adanya (bukan `nil`): user lebih baik melihat "JP"
    /// daripada kolom kosong.
    public static func displayName(for countryCode: String?) -> String? {
        guard let cc = countryCode?.uppercased(), cc.count == 2 else { return nil }
        return names[cc] ?? cc
    }

    /// Daftar nama negara. Sengaja terbatas pada negara yang benar-benar
    /// muncul di feed VPN gratis — menambah 240 entri untuk negara tanpa
    /// server hanya memperbesar binary tanpa ada gunanya.
    static let names: [String: String] = [
        "SG": "Singapore", "JP": "Japan", "KR": "South Korea", "HK": "Hong Kong",
        "TW": "Taiwan", "CN": "China", "US": "United States", "CA": "Canada",
        "GB": "United Kingdom", "UK": "United Kingdom", "DE": "Germany",
        "FR": "France", "NL": "Netherlands", "RU": "Russia", "IN": "India",
        "ID": "Indonesia", "MY": "Malaysia", "TH": "Thailand", "VN": "Vietnam",
        "PH": "Philippines", "AU": "Australia", "NZ": "New Zealand",
        "BR": "Brazil", "AR": "Argentina", "CL": "Chile", "MX": "Mexico",
        "TR": "Turkey", "AE": "UAE", "SA": "Saudi Arabia", "IL": "Israel",
        "SE": "Sweden", "NO": "Norway", "FI": "Finland", "DK": "Denmark",
        "CH": "Switzerland", "AT": "Austria", "BE": "Belgium", "IE": "Ireland",
        "PL": "Poland", "CZ": "Czechia", "RO": "Romania", "UA": "Ukraine",
        "IT": "Italy", "ES": "Spain", "PT": "Portugal", "GR": "Greece",
        "ZA": "South Africa", "EG": "Egypt", "NG": "Nigeria", "KE": "Kenya",
        "PK": "Pakistan", "BD": "Bangladesh", "LK": "Sri Lanka", "KZ": "Kazakhstan",
        "MO": "Macau", "IR": "Iran", "IQ": "Iraq"
    ]

    /// Titik tengah (lat/lng) tiap negara, untuk menaruh pin di peta.
    ///
    /// SENGaja lokal dan statis: DotMap punya `IPLocationService` yang
    /// memanggil ipwho.is / ipinfo.io, tapi memakainya berarti mengirim IP
    /// publik user ke pihak ketiga — tidak pantas untuk app yang slogannya
    /// "Your privacy matters". Node hanya membawa kode negara, jadi centroid
    /// tabel ini cukup untuk menandai lokasi server.
    ///
    /// Nilai ±1–2 derajat dari pusat geografis. Untuk satu pin di peta dunia
    /// seukuran kartu, presisi beberapa derajat sama sekali tidak terlihat —
    /// dan yang penting pinnya ada, bukan tepat sampai kilometer.
    ///
    /// Murni & nonisolated supaya bisa diuji. Kode yang tidak ada di tabel
    /// mengembalikan `nil` (bukan asal titik): peta tanpa pin lebih jujur
    /// daripada pin di tempat keliru.
    public static func centroid(for countryCode: String?) -> (lat: Double, lng: Double)? {
        guard let cc = countryCode?.uppercased(), let c = centroids[cc] else { return nil }
        return c
    }

    static let centroids: [String: (lat: Double, lng: Double)] = [
        "SG": (1.35, 103.82), "JP": (36.20, 138.25), "KR": (36.50, 127.88),
        "HK": (22.32, 114.17), "TW": (23.70, 120.96), "CN": (35.86, 104.20),
        "US": (37.09, -95.71), "CA": (56.13, -106.35), "GB": (55.38, -3.44),
        "UK": (55.38, -3.44), "DE": (51.17, 10.45), "FR": (46.23, 2.21),
        "NL": (52.13, 5.29), "RU": (61.52, 105.32), "IN": (20.59, 78.96),
        "ID": (-0.79, 113.92), "MY": (4.21, 101.98), "TH": (15.87, 100.99),
        "VN": (14.06, 108.28), "PH": (12.88, 121.77), "AU": (-25.27, 133.78),
        "NZ": (-40.90, 174.89), "BR": (-14.24, -51.93), "AR": (-38.42, -63.62),
        "CL": (-35.68, -71.54), "MX": (23.63, -102.55), "TR": (38.96, 35.24),
        "AE": (23.42, 53.85), "SA": (23.89, 45.08), "IL": (31.05, 34.85),
        "SE": (60.13, 18.64), "NO": (60.47, 8.47), "FI": (61.92, 25.75),
        "DK": (56.26, 9.50), "CH": (46.82, 8.23), "AT": (47.52, 14.55),
        "BE": (50.50, 4.47), "IE": (53.14, -7.69), "PL": (51.92, 19.15),
        "CZ": (49.82, 15.47), "RO": (45.94, 24.97), "UA": (48.38, 31.17),
        "IT": (41.87, 12.57), "ES": (40.46, -3.75), "PT": (39.40, -8.22),
        "GR": (39.07, 21.82), "ZA": (-30.56, 22.94), "EG": (26.82, 30.80),
        "NG": (9.08, 8.68), "KE": (-0.02, 37.91), "PK": (30.38, 69.35),
        "BD": (23.68, 90.36), "LK": (7.87, 80.77), "KZ": (48.02, 66.92),
        "MO": (22.20, 113.54), "IR": (32.43, 53.69), "IQ": (33.22, 43.68)
    ]

    // MARK: - Resolusi lengkap (dipakai parser)

    /// Negara sebuah node, dari nama dulu lalu dari host.
    ///
    /// Urutan disengaja: **nama dulu**. Nama itu murah (sudah ada di string),
    /// dan sering benar (feed menandai negara dengan emoji bendera atau kode).
    /// GeoIP baru jalan kalau nama tidak memberi jawaban — dan justru
    /// banyak kasus itulah yang perlu, karena nama node generik seperti
    /// "By EbraSha ⌨️" tidak menyebut lokasi sama sekali.
    ///
    /// SINKRON dan murni: dipanggil dari parser yang sudah jalan di
    /// background, jadi tidak boleh suspend.
    public static func resolveSync(name: String, host: String) -> String? {
        if let fromName = infer(from: name) { return fromName }
        return GeoIP.countryCode(for: host)
    }

    /// Versi async yang juga mencoba DNS untuk host domain. Dipakai di jalur
    /// yang boleh menunggu (mis.prilayout kartu rekomendasi).
    public static func resolve(name: String, host: String) async -> String? {
        if let fromName = infer(from: name) { return fromName }
        if GeoIP.isIPv4Literal(host) { return GeoIP.countryCode(forIPv4: host) }
        guard let ip = await GeoIPResolver.resolveHostIPv4Public(host) else { return nil }
        return GeoIP.countryCode(forIPv4: ip)
    }
}
