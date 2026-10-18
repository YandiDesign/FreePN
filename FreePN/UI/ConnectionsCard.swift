import Foundation
import SwiftUI

/// Satu koneksi yang sedang lewat core, dari Clash API (`GET /connections`).
///
/// `host` = domain tujuan (mis. `ws.chatgpt.com`), jatuh ke IP bila kosong.
/// `rate` = laju down+up (byte/detik) dari selisih dua snapshot.
public struct LiveConnection: Identifiable, Equatable {
    public var id: String
    public var host: String
    public var appName: String
    public var network: String
    public var download: Int64
    public var upload: Int64
    public var rate: Double

    public init(id: String, host: String, appName: String, network: String,
                download: Int64, upload: Int64, rate: Double) {
        self.id = id; self.host = host; self.appName = appName
        self.network = network; self.download = download; self.upload = upload
        self.rate = rate
    }
}

/// Pengambil + pengolah daftar koneksi live. Logika murni dipisah dari view
/// supaya bisa diuji tanpa core dan tanpa Clash API.
public enum ConnectionsFetcher {
    /// Satu baris mentah dari `/connections` (tanpa laju — laju dihitung dari
    /// selisih dua snapshot di `withRates`).
    public struct Raw: Equatable {
        public var id: String
        public var host: String
        public var appName: String
        public var network: String
        public var download: Int64
        public var upload: Int64
        /// Rantai outbound yang dilewati (mis. `["proxy"]` vs `["direct"]`).
        public var chains: [String]
    }

    /// Ambil snapshot mentah dari core. `nil` bila core tidak menjawab
    /// (belum tersambung, port salah, timeout) — pemanggil menampilkan
    /// empty state, bukan error.
    public static func fetch(clashPort: Int, timeout: TimeInterval = 2) async -> [Raw] {
        guard clashPort > 0,
              let url = URL(string: "http://127.0.0.1:\(clashPort)/connections") else { return [] }
        var req = URLRequest(url: url)
        req.timeoutInterval = timeout
        // `URLSession.shared` — JANGAN sesi kustom: sesi probe punya
        // `httpMaximumConnectionsPerHost` sendiri dan request ke loopback
        // tidak butuh konfigurasi khusus (lihat `RealDelayTester`).
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return [] }
        return decode(data)
    }

    /// Parse body `{"connections": [...]}`. Toleran: entri yang tidak punya
    /// `id` dilewati, field yang hilang diisi default — satu koneksi aneh
    /// tidak boleh menggagalkan seluruh daftar.
    public static func decode(_ data: Data) -> [Raw] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = obj["connections"] as? [[String: Any]] else { return [] }
        var out: [Raw] = []
        out.reserveCapacity(list.count)
        for c in list {
            guard let id = c["id"] as? String, !id.isEmpty else { continue }
            let meta = c["metadata"] as? [String: Any] ?? [:]
            let host = (meta["host"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? (meta["destinationIP"] as? String ?? "")
            let processPath = meta["processPath"] as? String ?? ""
            out.append(Raw(
                id: id,
                host: host.isEmpty ? "-" : host,
                appName: appDisplayName(processPath: processPath),
                network: (meta["network"] as? String ?? "").lowercased(),
                download: number(c["download"]),
                upload: number(c["upload"]),
                chains: c["chains"] as? [String] ?? []))
        }
        return out
    }

    /// Hanya koneksi yang LEWAT VPN (bukan bypass split tunnel).
    ///
    /// Dengan split tunnel (inklusif/eksklusif per domain/app), sebagian
    /// koneksi sengaja `direct` — kartu ini tidak boleh menampilkannya,
    /// kalau tidak user tidak bisa bedakan "apa yang dilindungi VPN" dari
    /// "apa yang jalan langsung". Yang dihitung VPN = rantainya menyentuh
    /// outbound selain `direct`/`block`/`dns-out` (outbound node bernama
    /// `proxy` di config yang dibangun `SingBoxConfigBuilder`).
    public static func vpnOnly(_ rows: [Raw]) -> [Raw] {
        rows.filter { r in
            r.chains.contains { $0 != "direct" && $0 != "block" && $0 != "dns-out" }
        }
    }

    /// Nama app dari `processPath` milik sing-box.
    ///
    /// Helper (mis. `/Applications/Arc.app/.../Browser Helper`) ditampilkan
    /// sebagai bundle app-nya (`Arc`), bukan nama helper — yang dikenali user
    /// adalah aplikasinya. Tanpa `.app` di path, dipakai nama executable.
    public static func appDisplayName(processPath: String) -> String {
        guard !processPath.isEmpty else { return "-" }
        let parts = processPath.split(separator: "/").map(String.init)
        if let bundle = parts.first(where: { $0.hasSuffix(".app") }) {
            return String(bundle.dropLast(4))
        }
        return parts.last ?? "-"
    }

    /// Gabungkan snapshot baru dengan snapshot sebelumnya menjadi laju.
    ///
    /// Koneksi yang baru muncul (belum ada di `previous`) punya laju 0 —
    /// menebak dari total kumulatif justru menghasilkan angka liar sekali
    /// baca. Urut: laju tertinggi dulu, lalu total terbesar.
    public static func withRates(current: [Raw],
                                 previous: [String: (down: Int64, up: Int64, at: Date)],
                                 now: Date = Date()) -> (entries: [LiveConnection], snapshot: [String: (down: Int64, up: Int64, at: Date)]) {
        var snap: [String: (down: Int64, up: Int64, at: Date)] = [:]
        snap.reserveCapacity(current.count)
        var entries: [LiveConnection] = []
        entries.reserveCapacity(current.count)
        for c in current {
            snap[c.id] = (c.download, c.upload, now)
            var rate = 0.0
            if let p = previous[c.id] {
                let dt = now.timeIntervalSince(p.at)
                if dt > 0 {
                    let dd = max(0, c.download - p.down) + max(0, c.upload - p.up)
                    rate = Double(dd) / dt
                }
            }
            entries.append(LiveConnection(id: c.id, host: c.host, appName: c.appName,
                                          network: c.network, download: c.download,
                                          upload: c.upload, rate: rate))
        }
        entries.sort {
            if $0.rate != $1.rate { return $0.rate > $1.rate }
            return ($0.download + $0.upload) > ($1.download + $1.upload)
        }
        return (entries, snap)
    }

    private static func number(_ v: Any?) -> Int64 {
        if let n = v as? Int64 { return n }
        if let n = v as? Int { return Int64(n) }
        if let n = v as? NSNumber { return n.int64Value }
        if let n = v as? Double { return Int64(n) }
        return 0
    }
}

/// Kartu "Koneksi Aktif": log trafik live pengganti kartu rekomendasi.
///
/// Menempati slot yang sama (kolom kanan atas, di atas peta) dengan bahasa
/// visual yang sama. Isinya snapshot `GET /connections` tiap 2 detik yang
/// sudah disaring ke HANYA koneksi lewat VPN: domain tujuan + nama app +
/// laju — jawaban atas "apa yang sedang dilindungi VPN sekarang?". Koneksi
/// `direct` (bypass split tunnel inklusif/eksklusif) sengaja tidak tampil.
/// Berbeda dari panel Log di bawah (diagnostik core/helper) dan dari kartu
/// Trafik (angka total + sparkline).
///
/// Sengaja observe `ConnectionManager` sendiri (seperti `TrafficCard`) supaya
/// polling tiap 2 detik tidak menggambar ulang peta/tabel/log di sekitarnya.
struct ConnectionsCard: View {
    @ObservedObject var connection: ConnectionManager

    @State private var entries: [LiveConnection] = []
    @State private var previous: [String: (down: Int64, up: Int64, at: Date)] = [:]
    @State private var timer: Timer? = nil

    /// Berapa baris ditampilkan tanpa scroll — muat di slot kartu lama
    /// (header + ~5 baris ringkas ≈ tinggi strip rekomendasi + sedikit).
    static let maxRows = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                CardHeader("arrow.left.arrow.right", "card_connections")
                Spacer(minLength: 0)
                if connection.status == .connected, !entries.isEmpty {
                    Text("\(entries.count)")
                        .font(Theme.font(.caption, design: .monospaced))
                        .foregroundColor(Palette.textTertiary)
                }
            }

            if connection.status != .connected {
                Text("connections_idle")
                    .font(Theme.font(.callout))
                    .foregroundColor(Palette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if entries.isEmpty {
                Text("connections_none")
                    .font(Theme.font(.callout))
                    .foregroundColor(Palette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 7) {
                        ForEach(entries.prefix(Self.maxRows)) { e in
                            connectionRow(e)
                        }
                    }
                }
                .frame(maxHeight: 172)
            }
        }
        .padding(16)
        .fixedSize(horizontal: false, vertical: true)
        .freepnCard()
        .onAppear { startTimer(); tick() }
        .onDisappear { stopTimer() }
    }

    private func connectionRow(_ e: LiveConnection) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(e.rate > 0 ? Palette.mint : Palette.textTertiary.opacity(0.5))
                .frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 1) {
                Text(e.host)
                    .font(Theme.scaled(13, weight: .semibold))
                    .foregroundColor(Palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(e.appName)
                    .font(Theme.scaled(11))
                    .foregroundColor(Palette.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(TrafficCard.rate(e.rate))
                .font(Theme.font(.callout, design: .monospaced))
                .monospacedDigit()
                .foregroundColor(e.rate > 0 ? Palette.mint : Palette.textTertiary)
        }
    }

    private func startTimer() {
        stopTimer()
        let t = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard connection.status == .connected else {
            if !entries.isEmpty || !previous.isEmpty {
                entries = []
                previous = [:]
            }
            return
        }
        let port = connection.clashPort
        let prev = previous
        Task {
            // Hanya yang lewat VPN — koneksi `direct` (bypass split tunnel)
            // bukan urusan kartu ini.
            let raw = ConnectionsFetcher.vpnOnly(await ConnectionsFetcher.fetch(clashPort: port))
            let merged = ConnectionsFetcher.withRates(current: raw, previous: prev)
            await MainActor.run {
                // Port bisa berganti tiap sesi; kalau user sudah putus di
                // tengah fetch, buang hasilnya — jangan tampilkan daftar basi.
                guard connection.status == .connected else { return }
                entries = merged.entries
                previous = merged.snapshot
            }
        }
    }
}
