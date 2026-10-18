import Foundation

/// Pembaca database GeoIP **GeoLite2 City** (MaxMind, EULA; GeoNames CC BY 4.0).
///
/// Format biner `geoip-country.bin`, dibuat oleh `scripts/build-geolite2.py`:
///
///     magic  8 byte  "FPNGEO02"
///     count  4 byte  UInt32 BE
///     ncodes 2 byte  UInt16 BE
///     codes  ncodes x 2 byte   — kode negara ASCII, terurut
///     record 11 byte, fixed    — startIP UInt32 BE | span UInt16 BE
///                                  | lat UInt16 BE | lng UInt16 BE | idx UInt8
///
/// Record **fixed-width** supaya pencarian dilakukan langsung di berkas yang
/// di-memory-map (stride 11). Tidak ada 2,4 juta record yang dimuat ke RAM —
/// yang dipegang Swift hanya byte-nya sendiri, dan OS bisa evict halaman yang
/// sudah lama tidak disentuh.
///
/// Pencarian: "record terakhir dengan `start <= ip`", lalu **verifikasi `ip`
/// masih di dalam span**. Verifikasi wajib: tanpa itu, IP yang jatuh di celah
/// (blok privat 10/8, 192.168/16 — tidak ada di GeoLite2) akan mewarisi data
/// record sebelumnya. Test menangkap 192.168.1.1 -> "ML" (Mali) sebelum
/// span disimpan.
///
/// Koordinat skala 1/128 derajat (~870 m) — jauh di bawah satu piksel peta
/// dunia selebar ~300 pt, jadi penghematan 2 byte per record tidak terlihat.
///
/// Sepenuhnya **offline**: tidak ada panggilan jaringan. Pembaca GeoIP bawaan
/// DotMap memanggil ipwho.is / ipinfo.io; di sini lokasi server dibaca dari
/// database sendiri, jadi tidak ada IP user yang keluar dari mesin.
///
/// ⚠️ Batas lisensi (GeoLite2 EULA §5): data ini tidak boleh dipakai untuk
/// menemukan rumah, orang, atau alamat jalan tertentu. Yang ditampilkan hanya
/// negara dan koordinat kota server — jauh di atas level itu.
public enum GeoIP {
    private static let magic = Array("FPNGEO02".utf8)
    private static let recordSize = 11

    public static let resourceName = "geoip-country"

    /// Hasil lookup satu alamat.
    public struct Record: Equatable {
        public let ip: String
        /// Kode ISO alpha-2; `nil` bila IP di luar database (mis. blok privat).
        public let country: String?
        /// Koordinat kota; `nil` bila record tidak punya lokasi.
        public let latitude: Double?
        public let longitude: Double?
    }

    // MARK: - Keadaan
    private static var blob: Data?
    private static var codes: [String] = []
    private static var count = 0
    private static var recordsOffset = 0
    private static var attempted = false
    private static var available = false
    private static let lock = NSLock()

    /// Pasang blob database dalam format yang sama persis dengan berkas asli.
    /// Dipakai oleh `load()` sekaligus test — jadi test benar-benar melewati
    /// decoder yang sama, bukan jalur khusus.
    static func install(blob newBlob: Data) -> Bool {
        let ok = parse(newBlob)
        lock.lock()
        blob = ok ? newBlob : nil
        attempted = true
        available = ok
        lock.unlock()
        return ok
    }

    /// Buang cache (test).
    static func reset() {
        lock.lock(); defer { lock.unlock() }
        blob = nil; codes = []; count = 0; recordsOffset = 0
        attempted = false; available = false
    }

    /// Validasi header + kode negara. Tubuh record dibaca malas saat lookup.
    private static func parse(_ data: Data) -> Bool {
        guard data.count > 14 else { return false }
        let head = [UInt8](data.prefix(8))
        guard head == magic else { return false }
        let n = Int(data[8]) << 24 | Int(data[9]) << 16 | Int(data[10]) << 8 | Int(data[11])
        let nc = Int(data[12]) << 8 | Int(data[13])
        guard n > 0, nc > 0 else { return false }
        let off = 14 + nc * 2
        guard off + n * recordSize <= data.count else { return false }

        var newCodes: [String] = []
        newCodes.reserveCapacity(nc)
        let bytes = [UInt8](data.prefix(off))
        for i in 0..<nc {
            newCodes.append(String(UnicodeScalar(bytes[14 + i * 2]))
                            + String(UnicodeScalar(bytes[15 + i * 2])))
        }
        lock.lock()
        codes = newCodes
        count = n
        recordsOffset = off
        lock.unlock()
        return true
    }

    /// Muat database dari bundle. Aman dipanggil berulang.
    @discardableResult
    public static func load() -> Bool {
        lock.lock()
        if attempted { let ok = available; lock.unlock(); return ok }
        lock.unlock()

        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "bin"),
              let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            install(blob: Data())
            return false
        }
        return install(blob: data)
    }

    // MARK: - Pencarian

    /// Lookup satu alamat IPv4. Mengembalikan record dengan negara & koordinat
    /// `nil` bila IP tidak ada di database.
    ///
    /// Murni, nonisolated, thread-safe.
    public static func lookup(_ ip: String) -> Record? {
        guard let value = ipv4Value(ip) else { return nil }
        if !load() { return nil }

        lock.lock()
        let data = blob, n = count, off = recordsOffset, cs = codes
        lock.unlock()
        guard let data = data, n > 0 else { return nil }

        // Binary search: indeks terakhir dengan start <= value.
        var lo = 0, hi = n - 1, found = -1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if start(of: mid, in: data, off: off) <= value { found = mid; lo = mid + 1 }
            else { hi = mid - 1 }
        }
        guard found >= 0 else {
            return Record(ip: ip, country: nil, latitude: nil, longitude: nil)
        }
        // Verifikasi rentang: ip harus masih di dalam span record ini.
        let s = start(of: found, in: data, off: off)
        let span = span(of: found, in: data, off: off)
        guard value <= s + span else {
            return Record(ip: ip, country: nil, latitude: nil, longitude: nil)
        }
        let base = off + found * recordSize
        let lat = coord(data[base + 6], data[base + 7], bias: 90.0)
        let lng = coord(data[base + 8], data[base + 9], bias: 180.0)
        let idx = Int(data[base + 10])
        return Record(ip: ip,
                      country: idx < cs.count ? cs[idx] : nil,
                      latitude: lat, longitude: lng)
    }

    private static func start(of i: Int, in data: Data, off: Int) -> UInt32 {
        let b = off + i * recordSize
        return UInt32(data[b]) << 24 | UInt32(data[b + 1]) << 16
             | UInt32(data[b + 2]) << 8 | UInt32(data[b + 3])
    }

    private static func span(of i: Int, in data: Data, off: Int) -> UInt32 {
        let b = off + i * recordSize + 4
        return UInt32(data[b]) << 8 | UInt32(data[b + 1])
    }

    /// UInt16 -> derajat: nilai disimpan sebagai (derajat + bias) * 128.
    private static func coord(_ hi: UInt8, _ lo: UInt8, bias: Double) -> Double {
        let units = Double(UInt16(hi) << 8 | UInt16(lo))
        return units / 128.0 - bias
    }

    /// Kode negara saja (bentuk yang dipakai parser).
    public static func countryCode(forIPv4 ip: String) -> String? {
        lookup(ip)?.country
    }

    /// Versi yang menerima hostname atau IPv6: keduanya `nil`. Database ini
    /// IPv4 saja, dan resolusi DNS adalah I/O — pemanggil yang butuh itu
    /// memakai `GeoIPResolver`.
    public static func countryCode(for hostOrIP: String) -> String? {
        guard isIPv4Literal(hostOrIP) else { return nil }
        return countryCode(forIPv4: hostOrIP)
    }

    // MARK: - Parsing alamat (murni, bisa diuji)

    /// Ubah "1.2.3.4" jadi UInt32, atau `nil` kalau bukan IPv4 v4.
    ///
    /// Ditulis manual, bukan lewat `inet_pton`, supaya bisa diuji tanpa
    /// pointer dan tanpa Foundation network.
    public static func ipv4Value(_ s: String) -> UInt32? {
        var parts = [UInt32]()
        parts.reserveCapacity(4)
        var acc: UInt32?
        for scalar in s.unicodeScalars {
            if scalar == "." {
                guard let v = acc else { return nil }
                parts.append(v)
                if parts.count > 3 { return nil }
                acc = nil
                continue
            }
            guard scalar.value >= 48, scalar.value <= 57 else { return nil }
            let digit = UInt32(scalar.value - 48)
            if let a = acc {
                let next = a * 10 + digit
                guard next <= 255 else { return nil }   // tolak overflow / > 3 digit
                acc = next
            } else {
                acc = digit
            }
        }
        guard parts.count == 3, let last = acc else { return nil }
        parts.append(last)
        return (parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3]
    }

    public static func isIPv4Literal(_ s: String) -> Bool {
        ipv4Value(s) != nil
    }

    /// Kebalikan dari `ipv4Value`: `in_addr` -> "1.2.3.4", dipakai setelah
    /// resolusi DNS yang mengembalikan `in_addr`, bukan string.
    public static func formatIPv4(_ addr: in_addr) -> String {
        let v = UInt32(bigEndian: addr.s_addr)
        return "\((v >> 24) & 0xFF).\((v >> 16) & 0xFF).\((v >> 8) & 0xFF).\(v & 0xFF)"
    }
}