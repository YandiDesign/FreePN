import Foundation

/// Deteksi & dekode base64 standar/URL-safe toleran padding hilang.
public enum Base64Detector {
    /// Dekode base64 standar atau URL-safe, dengan whitespace dibuang dan padding
    /// yang hilang dilengkapi.
    ///
    /// Satu lintasan, bukan lima. Versi sebelumnya memakai
    /// `replacingOccurrences` berulang: pada payload 10 MB itu berarti empat
    /// salinan penuh 10 MB Plus satu `trimmingCharacters` — 50 MB transaksi
    /// sebelum satu byte pun didekode. Yang terjadi adalah `ShareLinkParser`
    /// memanggil fungsi ini di awal feed, jadi biaya itu nyata (D61).
    public static func decodeTolerant(_ s: String) -> Data? {
        // Kumpulkan hanya byte base64 yang sah. Karakter di luar alfabet
        // (spasi, newline, `-`/`_` versi URL-safe) dipetakan atau dibuang
        // dalam satu lintasan.
        var out = [UInt8]()
        out.reserveCapacity(s.utf8.count + 4)
        for byte in s.utf8 {
            switch byte {
            case 0x2D: out.append(0x2B)          // '-' -> '+'
            case 0x5F: out.append(0x2F)          // '_' -> '/'
            case 0x20, 0x09, 0x0A, 0x0D: break  // whitespace diabaikan
            case 0x3D: break                    // '=' yang sudah ada
            default:
                guard isBase64Byte(byte) else { return nil }
                out.append(byte)
            }
        }
        guard !out.isEmpty else { return nil }
        // Panjang byte, bukan jumlah `Character`: base64 itu ASCII, dan
        // menghitung `Character` keliru kalau input pernah memuat skalar
        // non-ASCII yang lolos.
        let rem = out.count % 4
        // rem == 1 mustahil untuk base64 yang sah (4-simbol -> 3 byte), jadi
        // `Data` akan menolak padding 3 anyway; kembalikan nil lebih awal
        // daripada menebak.
        if rem == 1 { return nil }
        if rem != 0 { out.append(contentsOf: Array(repeating: 0x3D, count: 4 - rem)) }
        return Data(base64Encoded: Data(out))
    }

    @inline(__always)
    private static func isBase64Byte(_ b: UInt8) -> Bool {
        (b >= 0x41 && b <= 0x5A)   // A-Z
            || (b >= 0x61 && b <= 0x7A)   // a-z
            || (b >= 0x30 && b <= 0x39)   // 0-9
            || b == 0x2B || b == 0x2F    // + /
    }

    /// Karakter-set putih. Dibangun SEKALI, bukan di setiap pemanggilan —
    /// `looksLikeBase64` dipanggil per node saat parsing share-link (D61).
    private static let allowed: Set<UInt8> = {
        var set = Set<UInt8>(minimumCapacity: 66)
        for b in UInt8(ascii: "A")...UInt8(ascii: "Z") { set.insert(b) }
        for b in UInt8(ascii: "a")...UInt8(ascii: "z") { set.insert(b) }
        for b in UInt8(ascii: "0")...UInt8(ascii: "9") { set.insert(b) }
        set.formUnion([0x2B, 0x2F, 0x3D, 0x2D, 0x5F])   // + / = - _
        return set
    }()

    /// Apakah string ini "terlihat seperti" base64?
    ///
    /// Porte entry ini dijalankan pada SELURUH dokumen sebelum parsing apa pun,
    /// jadi satu lintasan skalar per byte feed sudah terasa. Karena itu ini
    /// berhenti di karakter pertama yang tidak sah, bukan mengoleksi seluruh
    /// string lebih dulu.
    public static func looksLikeBase64(_ s: String) -> Bool {
        var count = 0
        for byte in s.utf8 {
            // Whitespace diperbolehkan (payload base64 sering di-wrap).
            if byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D { continue }
            guard allowed.contains(byte) else { return false }
            count += 1
        }
        // 16 karakter base64 = 12 byte, sudah cukup untuk memuat credential
        // SS maupun UUID. Ambang lama 20 menolak beberapa feed sah.
        return count >= 16
    }
}