import Foundation

/// Menentukan negara sebuah server dari `ProxyNode`.
///
/// Urutan usaha, dari yang paling murah ke yang paling mahal:
/// 1. **Kode negara yang sudah tersimpan** di node (hasil parse sebelumnya).
/// 2. **Nama node** — `CountryInfer.infer` (emoji bendera, `[XX]`, Mandarin).
/// 3. **GeoIP atas host IPv4** — offline, instan. Mengcover 68,8% node yang
///    host-nya IP literal.
/// 4. **DNS lalu GeoIP** — hanya untuk host domain (31,2%). Butuh satu
///    query DNS, dan hasilnya di-cache per host supaya tidak diulang.
///
/// Semua langkah ini lokal; tidak ada API pihak ketiga.
public enum GeoIPResolver {
    /// Cache hasil per host. Host yang sama sering muncul berkali-kali di
    /// feed (sumber aggregator mengulang node yang sama), jadi tanpa
    /// cache satu feed bisa memicu ribuan query DNS.
    private static var cache: [String: String?] = [:]
    /// Koordinat kota hasil resolusi DNS, supaya pin peta tidak jatuh ke
    /// centroid negara hanya karena host-nya domain, bukan IP literal.
    private static var coordinateCache: [String: (lat: Double, lng: Double)] = [:]
    private static let cacheLock = NSLock()

    /// Bersihkan cache (test).
    public static func resetCache() {
        cacheLock.withLock {
            cache.removeAll()
            coordinateCache.removeAll()
        }
    }

    /// Koordinat kota untuk host domain yang sudah pernah di-resolve.
    ///
    /// `ServerWorldMap.pins` dipanggil dari jalur sinkron (render SwiftUI),
    /// jadi ia tidak bisa menunggu DNS. Yang bisa ia lakukan adalah memakai
    /// hasil yang sudah di-cache oleh pengayaan negara — gratis, dan jauh
    /// lebih tepat daripada centroid.
    public static func cachedCoordinates(for host: String) -> (lat: Double, lng: Double)? {
        cacheLock.withLock { coordinateCache[host.lowercased()] }
    }

    /// Negara + koordinat untuk satu host, dipakai pengayaan massal.
    ///
    /// Host yang sama sering muncul di banyak node (feed aggregator mengulang),
    /// dan hasilnya di-cache — jadi 16.000 node tidak berarti 16.000 query DNS.
    /// Host yang gagal di-resolve ikut di-cache sebagai `nil` supaya domain
    /// mati tidak diulang tiap refresh.
    public static func resolveCountry(host: String) async -> String? {
        let key = host.lowercased()
        guard !key.isEmpty, !key.contains(" ") else { return nil }
        if GeoIP.isIPv4Literal(key) { return GeoIP.countryCode(forIPv4: key) }

        // `withLock` (bukan lock/unlock terpisah) wajib di sini: dipanggil
        // dari konteks async, dan Swift 6 menolak `lock()` di sana — bukan
        // sekadar peringatan.
        if let cached = cacheLock.withLock({ cache[key] }) { return cached }

        guard let ip = await resolveHostIPv4(key) else {
            cacheLock.withLock { cache[key] = nil }
            return nil
        }
        return remember(host: key, ip: ip)
    }

    /// Simpan hasil resolusi: negara untuk kolom tabel, koordinat untuk peta.
    private static func remember(host: String, ip: String) -> String? {
        guard let cc = GeoIP.countryCode(forIPv4: ip) else { return nil }
        cacheLock.withLock {
            cache[host] = cc
            if let hit = GeoIP.lookup(ip), let lat = hit.latitude, let lng = hit.longitude {
                coordinateCache[host] = (lat, lng)
            }
        }
        return cc
    }

    /// Negara sebuah node, atau `nil` bila tidak ada yang bisa saying.
    ///
    /// Fungsi SINKRON yang hanya melakukan langkah 1–3 (tanpa DNS). Aman
    /// dipanggil dari mana saja; dipakai parser yang tidak mau menunggu.
    public static func countryCode(for node: ProxyNode) -> String? {
        if let existing = node.countryCode, !existing.isEmpty { return existing }
        if let fromName = CountryInfer.infer(from: node.name) { return fromName }
        return GeoIP.countryCode(for: node.host)
    }

    /// Versi async yang juga mencoba DNS untuk host domain.
    ///
    /// Hasil di-cache sehingga panggilan berikutnya (node lain dengan host
    /// sama) tidak melakukan query lagi.
    public static func countryCodeResolvingDNS(for node: ProxyNode) async -> String? {
        if let existing = node.countryCode, !existing.isEmpty { return existing }
        if let fromName = CountryInfer.infer(from: node.name) { return fromName }

        let host = node.host
        if GeoIP.isIPv4Literal(host) {
            return GeoIP.countryCode(forIPv4: host)
        }

        if let cached = cacheLock.withLock({ cache[host] }) { return cached }

        guard let ip = await resolveHostIPv4(host) else {
            cacheLock.withLock { cache[host] = nil }
            return nil
        }
        return remember(host: host.lowercased(), ip: ip)
    }

    /// Resolusi DNS yang memprioritaskan A record.
    ///
    /// Database ini IPv4 saja, jadi A record yang dipakai dan AAAA
    /// diabaikan. Menghemat satu tingkat kegagalan untuk domain yang
    /// hanya punya AAAA.
    public static func resolveHostIPv4Public(_ host: String) async -> String? {
        await resolveHostIPv4(host)
    }

    /// `getaddrinfo` adalah blocking call — resolver yang lambat bisa menahan
    /// thread beberapa detik. Dipindah ke queue terpisah supaya tidak ikut
    /// memakan thread *cooperative pool* milik Swift Concurrency, yang jumlah
    /// thread-nya hanya sebanding jumlah core CPU.
    ///
    /// LEBAR DIBATAS (D61). Versi lalu memakai `.concurrent` tanpa ambang:
    /// feed 16.000 node menyisakan ~5.000 host domain, dan semuanya masuk
    /// antrean tanpa batas — ribuan `getaddrinfo` blocking sekaligus yang
    /// membanjiri resolver dan membuat thread queue meledak. Semaphore
    /// membatasi jumlah yang benar-benar berjalan.
    private static let dnsQueue = DispatchQueue(label: "freepn.geoip.dns",
                                                qos: .utility,
                                                attributes: .concurrent)
    private static let dnsLimiter = DispatchSemaphore(value: 16)

    private static func resolveHostIPv4(_ host: String) async -> String? {
        guard !host.isEmpty, !host.contains(" ") else { return nil }
        return await withCheckedContinuation { continuation in
            dnsQueue.async {
                dnsLimiter.wait()
                let value = blockingResolveHostIPv4(host)
                dnsLimiter.signal()
                continuation.resume(returning: value)
            }
        }
    }

    /// Pemanggilan blocking `getaddrinfo`. SELALU dipanggil di dalam
    /// `resolveHostIPv4`, tidak pernah langsung.
    private static func blockingResolveHostIPv4(_ host: String) -> String? {
        var hints = addrinfo(
            ai_flags: AI_ADDRCONFIG,
            ai_family: AF_INET,
            ai_socktype: SOCK_STREAM,
            ai_protocol: IPPROTO_TCP,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil)
        var res: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, nil, &hints, &res)
        guard status == 0, let first = res else { return nil }
        defer { freeaddrinfo(first) }

        var cursor: UnsafeMutablePointer<addrinfo>? = first
        while let info = cursor {
            if info.pointee.ai_family == AF_INET,
               let sa = info.pointee.ai_addr {
                let v4 = UnsafeRawPointer(sa)
                    .assumingMemoryBound(to: sockaddr_in.self).pointee.sin_addr
                return GeoIP.formatIPv4(v4)
            }
            cursor = info.pointee.ai_next
        }
        return nil
    }
}