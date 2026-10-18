import Foundation

/// Host yang dipakai uji "benar-benar bisa internet" (D93).
///
/// Dulu `AppConstants.testURL` satu konstanta yang tidak bisa diubah. User yang
/// punya jaringan yang memblokir salah satu host tidak punya pilihan apa pun —
/// seluruh daftar server bisa terlihat mati hanya karena satu host tidak
/// terjangkau, dan tidak ada cara membuktikannya.
///
/// Urutan dari yang paling ringan: endpoint `generate_204` tidak mengembalikan
/// body dan tidak butuh TLS sama sekali, jadi satu handshake lebih murah
/// daripada `https://` ke situs mana pun.
///
/// Sengaja TIDAK di `Shared/`: `L10n` tidak terlihat dari sana, dan target ini
/// hanya dipakai app.
public enum PingTarget: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    /// 204 tanpa body, tanpa TLS. Default — paling sedikit bisa gagal.
    case gstatic
    /// 204 tanpa body. Alternatif kalau gstatic diblokir di jaringan itu.
    case cloudflare
    /// Halaman beranda Google, HTTP polos. Bukan 204 — tapi tetap ringan.
    case google
    /// Diisi sendiri oleh user.
    case custom

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .gstatic:    return L10n.string("ping_target_gstatic")
        case .cloudflare: return L10n.string("ping_target_cloudflare")
        case .google:     return L10n.string("ping_target_google")
        case .custom:     return L10n.string("ping_target_custom")
        }
    }

    /// URL yang ditembak sing-box untuk target ini. `nil` untuk `.custom`
    /// sampai user mengisi.
    public var url: String? {
        switch self {
        case .gstatic:    return "http://www.gstatic.com/generate_204"
        case .cloudflare: return "http://cp.cloudflare.com/generate_204"
        case .google:     return "http://www.google.com/generate_204"
        case .custom:     return nil
        }
    }

    /// URL yang benar-benar dipakai.
    ///
    /// Kalau targetnya custom tapi kosong atau bukan URL yang valid, jatuh ke
    /// gstatic. Alasannya: URL yang tidak bisa di-parse akan ditolak sing-box,
    /// dan itu berarti SETIAP node terlihat "mati" hanya karena tidak ada yang
    /// ditembak — pesan paling menyesatkan yang bisa muncul di app ini.
    public func resolvedURL(custom: String) -> String {
        if self == .custom {
            let t = custom.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty, let u = URL(string: t), u.host != nil,
               u.scheme == "http" || u.scheme == "https" { return t }
            return PingTarget.gstatic.url ?? ""
        }
        return url ?? (PingTarget.gstatic.url ?? "")
    }

    /// Host yang ditampilkan di log, supaya user tahu dia sedang menguji ke mana.
    public func displayHost(custom: String) -> String {
        URL(string: resolvedURL(custom: custom))?.host ?? L10n.string("ping_target_custom")
    }

    /// URL custom yang diisi user valid atau bukan — bukan `resolvedURL`, yang
    /// selalu mengembalikan sesuatu. Dipakai UI untuk menampilkan peringatan
    /// alih-alih diam-diam memakai gstatic.
    public static func isUsableCustomURL(_ raw: String) -> Bool {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let u = URL(string: t), u.host != nil else { return false }
        return u.scheme == "http" || u.scheme == "https"
    }
}