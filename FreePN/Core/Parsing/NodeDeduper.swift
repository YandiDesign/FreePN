import Foundation

/// Kebersihan daftar node: dedup + buang node yang jelas tidak bisa dipakai.
///
/// D51 — feed gratis memuat link share korup. Contoh nyata di feed
/// `morpheusadam` (1.743 node): `ss://ax51Ok45f351XA@104.18.218.118:443`
/// yang payload base64-nya byte mentah (`k\x1eu:N9\x7f~u\`), bukan
/// `method:password`. Parser ours menerimanya — isinya kebetulan punya tanda
/// `:` dan UTF-8 valid — lalu `sing-box check` menolak SELURUH config probe
/// dengan `unknown method: k`, sehingga verifikasi internet dilewati untuk
/// ratusan node yang sebenarnya sehat.
///
/// Node seperti itu tidak akan pernah bisa dipakai. Buang di pintu masuk
/// (parser) dan, sebagai jaring kedua, lagi di `InternetProbe` — karena
/// `nodes.json` user bisa sudah berisi node rusak dari versi app sebelumnya.
public enum NodeDeduper {
    public static func dedup(_ nodes: [ProxyNode]) -> [ProxyNode] {
        var seen = Set<String>()
        var out: [ProxyNode] = []
        out.reserveCapacity(nodes.count)
        for n in nodes {
            if seen.insert(n.id).inserted { out.append(n) }
        }
        return out
    }

    /// Buang node yang korup atau tidak mungkin dipakai sing-box.
    ///
    /// Murni & nonisolated supaya bisa diuji tanpa actor.
    public static func keepingUsable(_ nodes: [ProxyNode]) -> [ProxyNode] {
        nodes.filter(isUsable)
    }

    /// Satu node layak uji kalau alamatnya masuk akal, kredensialnya bukan byte
    /// sampah, dan — untuk Shadowsocks — metodenya benar-benar ada di
    /// sing-box. Method di luar daftar itu dijamin ditolak core, jadi node
    /// seperti itu hanya menambah beban tanpa pernah bisa lulus.
    public static func isUsable(_ node: ProxyNode) -> Bool {
        guard Validators.isValidPort(node.port), Validators.isValidHost(node.host) else { return false }
        guard Validators.isPlausibleSecret(node.credential) else { return false }
        if node.proto == .shadowsocks {
            // CASE-INSENSITIF. Feed gratis sangat sering menulis `AES-256-GCM`
            // atau `chacha20-ietf-Poly1305` dengan huruf kapital — keduanya
            // method yang valid. Pencocokan exact membuang node yang
            // benar-benar bisa dipakai, dan user melihat "hanya 2.000 dari
            // 8.000 node" tanpa sebab yang jelas (D61).
            guard let cipher = node.cipher,
                  Validators.shadowsocksMethods.contains(cipher.lowercased()) else {
                return false
            }
        }
        return true
    }
}
