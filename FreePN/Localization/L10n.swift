import Foundation
import SwiftUI

/// Helper lokalisasi untuk string non-SwiftUI (notifikasi, menu bar, error helper).
/// UI SwiftUI memakai Text(LocalizedStringKey) + NSLocalizedString agar live tanpa restart.
public enum L10n {
    public static func string(_ key: String, comment: String = "") -> String {
        return NSLocalizedString(key, comment: comment)
    }

    public static func formatted(_ key: String, _ args: CVarArg...) -> String {
        let fmt = NSLocalizedString(key, comment: "")
        return String(format: fmt, arguments: args)
    }

    /// Locale efektif dari pengaturan bahasa.
    public static func locale(for language: AppLanguage) -> Locale {
        switch language {
        case .id: return Locale(identifier: "id")
        case .en: return Locale(identifier: "en")
        case .system: return Locale.current
        }
    }

    /// Identifier bahasa Apple untuk UserDefaults AppleLanguages (live tanpa restart).
    public static func appleLanguages(for language: AppLanguage) -> [String]? {
        switch language {
        case .system: return nil
        case .id: return ["id"]
        case .en: return ["en"]
        }
    }
}

/// Formatter "2 jam lalu" yang dipakai bersama.
///
/// `RelativeDateTimeFormatter` adalah salah satu inisialisasi Foundation
/// termahal yang ada (ia membangun objek ICU di balik layar). Sempat dibuat
/// baru di dalam `body` — dan untuk_sources_ satu formatter per BARIS tabel,
/// tiap beberapa detik saat app digambar ulang.
///
/// Sekarang hanya ada satu per (locale, gaya satuan), dibuat sekali lalu
/// dipakai ulang. `NSDateFormatter` tidak thread-safe untuk disetel ulang
/// sambil dipakai, jadi dictionary-nya dijaga lock dan formatter-nya TIDAK
/// pernah dimodifikasi setelah dibuat (D61).
public enum RelativeDate {
    private static var cache: [String: RelativeDateTimeFormatter] = [:]
    private static let lock = NSLock()

    private static func formatter(for locale: Locale, full: Bool) -> RelativeDateTimeFormatter {
        let key = "\(locale.identifier)#\(full ? "full" : "short")"
        lock.lock()
        defer { lock.unlock() }
        if let hit = cache[key] { return hit }
        let f = RelativeDateTimeFormatter()
        f.locale = locale
        if full { f.unitsStyle = .full }
        cache[key] = f
        return f
    }

    /// "2 jam lalu" / "2 hours ago" — gaya ringkas.
    public static func string(for date: Date, language: AppLanguage) -> String {
        formatter(for: L10n.locale(for: language), full: false)
            .localizedString(for: date, relativeTo: Date())
    }

    /// Versi `unitsStyle = .full`.
    public static func stringFull(for date: Date, language: AppLanguage) -> String {
        formatter(for: L10n.locale(for: language), full: true)
            .localizedString(for: date, relativeTo: Date())
    }
}
