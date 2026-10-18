import Foundation

/// Resolver URL template bertanggal (NodeFree & OpenRunner).
/// Mencoba hari ini (WIB & UTC) mundur 7 hari; URL pertama HTTP 200 + ≥1 node dipakai.
public enum SourceResolver {
    public static func candidates(for source: VPNSubscriptionSource, now: Date = Date()) -> [String] {
        // Cocokkan HOST, bukan seluruh URL. `lower.contains("nodefree.org")`
        // ikut cocok untuk `https://evil.example/?r=nodefree.org`, dan itu
        // berarti URL user ditulis ulang supaya request-nya pergi ke nodefree
        // (D61).
        let host = URL(string: source.url)?.host?.lowercased() ?? ""
        let isNodeFree = host == "nodefree.org" || host.hasSuffix(".nodefree.org")
        let isOpenRunner = host.hasSuffix("openrunner.net") || host.hasSuffix(".openrunner.net")
        guard isNodeFree || isOpenRunner else { return [source.url] }

        var out: [String] = []
        for back in 0..<7 {
            // BUG LAMA (D61): dipakai `Calendar.current` — zona waktu mesin
            // user — padahal kalender WIB & UTC yang justru dibangun di atas
            // tidak pernah dipakai untuk apa pun (`_ = cals`). Untuk user
            // di UTC-7, "hari ini menurut WIB" dan "hari ini menurut mesin"
            // berbeda sampai 24 jam sekali sehari, jadi resolver sampai
            // bold URL yang salah sepanjang hari itu.
            //
            // Sekarang: tambah hari di UTC (waktu selalu absolut), lalu
            // FORMAT dengan timezone masing-masing. Menghitung "kemarin" di
            // dua timezone berbeda tidak masuk akal karena yang dihitung tetap
            // instants yang sama.
            let day = calendarUTC.date(byAdding: .day, value: -back, to: now) ?? now
            if isNodeFree {
                let ym = fmtMonth.string(from: day)
                let ymd = fmtWIBDate.string(from: day)
                out.append("https://nodefree.org/dy/\(ym)/\(ymd).yaml")
            }
            if isOpenRunner {
                // Coba tanggal WIB lalu UTC (bisa sama; dedup di bawah)
                let wib = fmtWIBDate.string(from: day)
                let utc = fmtUTCDate.string(from: day)
                out.append("https://freenode.openrunner.net/uploads/\(wib)-clash.yaml")
                if utc != wib {
                    out.append("https://freenode.openrunner.net/uploads/\(utc)-clash.yaml")
                }
            }
        }
        // Dedup sambil pertahankan urutan, lalu tambahkan URL asli sebagai fallback terakhir.
        var seen = Set<String>(); var ded: [String] = []
        for u in out + [source.url] { if seen.insert(u).inserted { ded.append(u) } }
        return ded
    }

    // MARK: - Kalender & formatter (dibangun SEKALI)

    /// `locale = en_US_POSIX` itu wajib, bukan kosmetik: tanpa itu formatter
    /// memakai locale user, dan di locale non-Gregorian (mis. `th-TH` kalender
    /// Buddhis) `yyyy` menghasilkan 2569, bukan 2026 — URL yang dibangun jadi
    /// tidak ada satu pun server yang punya (D61).
    private static func formatter(_ format: String, timeZone: TimeZone) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = timeZone
        f.dateFormat = format
        return f
    }

    private static let fmtMonth = formatter("yyyy/MM", timeZone: TimeZone(identifier: "Asia/Jakarta") ?? .current)
    private static let fmtWIBDate = formatter("yyyyMMdd", timeZone: TimeZone(identifier: "Asia/Jakarta") ?? .current)
    private static let fmtUTCDate = formatter("yyyyMMdd", timeZone: TimeZone(identifier: "UTC") ?? .current)
    private static let calendarUTC: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC") ?? .current
        return c
    }()
}