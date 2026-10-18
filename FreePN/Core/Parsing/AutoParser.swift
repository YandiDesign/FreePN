import Foundation

/// Auto-deteksi format: (1) YAML Clash `proxies:`, (2) base64 share-link, (3) teks share-link.
public enum AutoParser {
    /// Hasil parsing satu feed.
    ///
    /// `unsupported` dan `unusable` sengaja DUA angka terpisah (D62).
    ///
    /// Semuanya dulu dijumlahkan jadi satu dan ditampilkan sebagai
    /// "tidak didukung". Padahal keduanya hal yang sangat berbeda bagi user:
    /// "protokol yang app tidak bisa pakai" vs "entri yang korup dan tidak
    /// akan pernah hidup". Untuk feed `ermaozi`, 224 dari 279 angka itu
    /// protokol (http/socks5/anytls), sisanya node korup — dan user tidak
    /// punya cara melihat pemisahan itu.
    public struct Outcome {
        public var nodes: [ProxyNode]
        /// Entry dengan protokol yang FreePN tidak bisa pakai.
        public var unsupported: Int
        /// Node yang ter-parse tapi korup / tidak mungkin dipakai (jaring D51).
        public var unusable: Int

        public init(nodes: [ProxyNode], unsupported: Int, unusable: Int = 0) {
            self.nodes = nodes
            self.unsupported = unsupported
            self.unusable = unusable
        }

        /// Total yang tidak jadi node — untukBackward compatibility dengan
        /// kode yang hanya butuh satu angka (mis. logging).
        public var rejected: Int { unsupported + unusable }
    }

    public static func parse(text: String, sourceID: String) -> Outcome {
        var nodes: [ProxyNode]
        var unsupported: Int
        // D91: entri yang gagal di-parse karena field wajib hilang ikut dihitung
        // sebagai korup, bukan dibuang tanpa jejak. Tanpa ini angka di kolom
        // "Keterangan" tidak pernah cocok dengan isi feed.
        var malformed = 0
        if ClashYAMLParser.canHandle(text) {
            let r = ClashYAMLParser.parse(text: text, sourceID: sourceID)
            nodes = r.nodes
            unsupported = r.unsupported
            malformed += r.malformed
            // `canHandle` cuma `text.contains("proxies:")`. Kalau string itu
            // muncul di dalam KOMENTAR atau di dalam nama node, kita masuk
            // jalur Clash tapi dapat 0 node — dan jalur share-link yang
            // sebenarnya benar TIDAK PERNAH dicoba. Feed seperti itu tampil
            // sebagai "0 node" padahal isinya tidak salah (D61).
            if nodes.isEmpty {
                let s = ShareLinkParser.parse(text: text, sourceID: sourceID)
                if !s.nodes.isEmpty {
                    nodes = s.nodes
                    unsupported += s.unsupported
                    malformed += s.malformed
                }
            }
        } else {
            let r = ShareLinkParser.parse(text: text, sourceID: sourceID)
            nodes = r.nodes
            unsupported = r.unsupported
            malformed += r.malformed
        }
        // D51: link share dari feed gratis kadang korup (payload base64-nya
        // byte mentah, bukan `method:password`). Node seperti itu LOOK-nya
        // valid bagi parser tapi membuat `sing-box check` menolak SELURUH
        // config probe — jadi satu node sampah mematikan verifikasi internet
        // untuk ratusan node sehat. Buang di pintu masuk, sekali saja, untuk
        // semua jalur parse.
        let before = nodes.count
        nodes = NodeDeduper.keepingUsable(nodes)
        return Outcome(nodes: nodes, unsupported: unsupported,
                       unusable: malformed + (before - nodes.count))
    }
}
