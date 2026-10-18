import Foundation

public enum AppLanguage: String, Codable, CaseIterable {
    case system, id, en
}

/// Skala UI dalam persen: 100 = normal, naik kelipatan 10 sampai 150.
/// Diterjemahkan jadi `Theme.uiScale` (1.0 … 1.5) yang dipakai `Theme.font`.
public enum AppUIScale {
    public static let range = 100...150
    public static let step = 10
    public static let `default` = 100

    /// Persen → faktor skala (100 → 1.0, 150 → 1.5).
    public static func factor(_ percent: Int) -> Double {
        Double(clamp(percent)) / 100.0
    }

    public static func clamp(_ percent: Int) -> Int {
        let stepped = Int((Double(percent) / Double(step)).rounded()) * step
        return min(range.upperBound, max(range.lowerBound, stepped))
    }
}

public struct AppSettings: Codable {
    public var language: AppLanguage
    public var launchAtLogin: Bool
    public var autoRefreshHours: Int // 0=mati, 1/3/6/12
    public var autoReconnect: Bool
    public var showPublicIP: Bool
    public var autoSortAfterPing: Bool
    public var hideDeadNodes: Bool
    /// Kolom IP di menu Server: `false` → `1.2.3.4`, `true` → `1.2.3.4:443`.
    /// Default ON karena sebagian host dipakai lebih dari satu port, jadi
    /// IP saja tidak selalu cukup untuk membedakan node.
    public var showNodePort: Bool
    public var randomMACOnConnect: Bool
    public var restoreMACOnDisconnect: Bool
    /// Mesin split: false = daemon TUN (ad-hoc OK), true = System Extension
    /// Transparent Proxy untuk VPN per-app (butuh Personal Team signing).
    /// Skala UI persen (100…150, langkah 10).
    public var uiScalePercent: Int
    /// Konkurensi menyesuaikan beban CPU mesin secara otomatis.
    public var adaptiveConcurrency: Bool
    /// Jatah CPU untuk FreePN dalam persen (25 / 50 / 75 / 100).
    public var cpuSharePercent: Int
    /// `true` → ping hanya memastikan server merespons (TCP handshake, atau
    /// probe UDP untuk Hysteria2). `false` → cek koneksi internet sungguhan
    /// lewat node (perilaku bawaan, D27).
    ///
    /// Default `false`: cek internet adalah satu-satunya cara menangkap node
    /// dengan kredensial salah atau egress diblokir, dan itu penyebab paling
    /// sering user connect sukses tapi tidak bisa mengakses apa pun.
    public var fastPing: Bool

    /// Ke mana uji "benar-benar bisa internet" ditembak (D93).
    public var pingTarget: PingTarget
    /// URL sendiri, dipakai hanya kalau `pingTarget == .custom`.
    public var pingTargetCustomURL: String

    public init(language: AppLanguage = .system, launchAtLogin: Bool = false,
                autoRefreshHours: Int = 6,
                autoReconnect: Bool = true, showPublicIP: Bool = false,
                autoSortAfterPing: Bool = true, hideDeadNodes: Bool = false,
                showNodePort: Bool = true,
                randomMACOnConnect: Bool = false, restoreMACOnDisconnect: Bool = true,
                uiScalePercent: Int = AppUIScale.default,
                adaptiveConcurrency: Bool = true, cpuSharePercent: Int = 50,
                fastPing: Bool = false,
                pingTarget: PingTarget = .gstatic, pingTargetCustomURL: String = "") {
        self.language = language; self.launchAtLogin = launchAtLogin
        self.autoRefreshHours = autoRefreshHours
        self.autoReconnect = autoReconnect; self.showPublicIP = showPublicIP
        self.autoSortAfterPing = autoSortAfterPing; self.hideDeadNodes = hideDeadNodes
        self.showNodePort = showNodePort
        self.randomMACOnConnect = randomMACOnConnect; self.restoreMACOnDisconnect = restoreMACOnDisconnect
        self.uiScalePercent = uiScalePercent
        self.adaptiveConcurrency = adaptiveConcurrency; self.cpuSharePercent = cpuSharePercent
        self.fastPing = fastPing
        self.pingTarget = pingTarget
        self.pingTargetCustomURL = pingTargetCustomURL
    }

    // Backward-compat: settings.json lama tanpa key baru tetap terbaca
    // (decodeIfPresent), bukan reset total.
    private enum CodingKeys: String, CodingKey {
        case language, launchAtLogin, autoRefreshHours
        case autoReconnect, showPublicIP, autoSortAfterPing, hideDeadNodes
        case showNodePort
        case randomMACOnConnect, restoreMACOnDisconnect
        case uiScalePercent, adaptiveConcurrency, cpuSharePercent
        case fastPing
        case pingTarget, pingTargetCustomURL
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // PENTING: `decodeIfPresent` untuk enum BERHENTI throw kalau kuncinya
        // ADA tapi nilainya tak dikenal (mis. `"language":"fr"` dari versi lain,
        // atau file yang rusak). Throw itu keluar dari `init`, keluar dari
        // `JSONDecoder`, lalu ditelan `try?` di `JSONStore.load` — hasilnya
        // SELURUH pengaturan user kembali ke default, diam-diam.
        //
        // `try? decode(...)` yang dipakai: value nonsensical -> `nil` -> default.
        language = (try? c.decode(AppLanguage.self, forKey: .language)) ?? .system
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        autoRefreshHours = try c.decodeIfPresent(Int.self, forKey: .autoRefreshHours) ?? 6
        autoReconnect = try c.decodeIfPresent(Bool.self, forKey: .autoReconnect) ?? true
        showPublicIP = try c.decodeIfPresent(Bool.self, forKey: .showPublicIP) ?? false
        autoSortAfterPing = try c.decodeIfPresent(Bool.self, forKey: .autoSortAfterPing) ?? true
        hideDeadNodes = try c.decodeIfPresent(Bool.self, forKey: .hideDeadNodes) ?? false
        // File lama tidak punya key ini -> tetap default (port tampil), bukan
        // gagal load. Memakai `decode` biasa akan mengembalikan semua settings
        // user ke nol begitu app diperbarui.
        showNodePort = try c.decodeIfPresent(Bool.self, forKey: .showNodePort) ?? true
        randomMACOnConnect = try c.decodeIfPresent(Bool.self, forKey: .randomMACOnConnect) ?? false
        restoreMACOnDisconnect = try c.decodeIfPresent(Bool.self, forKey: .restoreMACOnDisconnect) ?? true
        // File lama tidak punya key ini -> tetap default, bukan gagal load.
        // `try?` supaya nilai aneh dari versi lain tidak merombak settings.
        let raw = ((try? c.decode(Int.self, forKey: .uiScalePercent)) ?? nil) ?? AppUIScale.default
        uiScalePercent = AppUIScale.clamp(raw)
        adaptiveConcurrency = ((try? c.decode(Bool.self, forKey: .adaptiveConcurrency)) ?? nil) ?? true
        let share = ((try? c.decode(Int.self, forKey: .cpuSharePercent)) ?? nil) ?? 50
        cpuSharePercent = AppSettings.nearestCPUShare(share)
        fastPing = try c.decodeIfPresent(Bool.self, forKey: .fastPing) ?? false
        // `decodeIfPresent` + `try?` dua lapis: kuncinya boleh tidak ada (file
        // lama) DAN nilainya boleh tak dikenal (file dari versi lain).
        pingTarget = ((try? c.decodeIfPresent(PingTarget.self, forKey: .pingTarget)) ?? nil) ?? .gstatic
        pingTargetCustomURL = try c.decodeIfPresent(String.self, forKey: .pingTargetCustomURL) ?? ""
    }

    /// Nilai slider CPU-share yang sah: hanya kelipatan 25 antara 25…100.
    ///
    /// SATU sumber kebenaran untuk aturan ini. Sebelumnya logika yang sama ada
    /// dua kali — di `init(from:)` sini dan di `SettingsView.nearestShare` —
    /// jadi angka yang tampil di slider bisa berbeda dari yang tersimpan kalau
    /// salah satunya lupa diubah.
    public static func nearestCPUShare(_ raw: Int) -> Int {
        [25, 50, 75, 100].min(by: { abs($0 - raw) < abs($1 - raw) }) ?? 50
    }
}
