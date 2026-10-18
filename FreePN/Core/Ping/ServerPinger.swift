import Foundation
import Network

/// Hasil satu uji "apakah server merespons".
///
/// PENTING: `.aliveUpperBound` BUKAN pengukuran latensi. Untuk protokol UDP
/// (Hysteria2) tidak ada handshake yang bisa diukur — kita hanya tahu bahwa
/// tidak ada ICMP error, jadi host bisa dijangkau. Angkanya karena itu adalah
/// BATAS ATAS deadline, bukan RTT, dan harus ditampilkan berbeda dari angka ms
/// biasa.
public enum ServerPingOutcome: Equatable {
    /// Server membalas handshake. Angkanya RTT yang terukur.
    case replied(Int)
    /// UDP: tidak ada ICMP unreachable dalam deadline → host hidup, port
    /// mungkin terbuka atau di-filter. Angka = batas atas, bukan RTT.
    case aliveUpperBound(Int)
    /// Terbukti tidak merespons: handshake ditolak, atau ICMP unreachable.
    case dead
}

/// Ping "biasa": apakah server-nya merespons, TANPA lewat internet.
///
/// BERBEDA dari `InternetProbe`, yang menjalankan core sing-box dan menembak
/// `generate_204` melalui node tersebut. Di sini tidak ada core, tidak ada
/// proxy, tidak ada kredensial yang diuji — cuma satu koneksi langsung ke
/// `host:port` node.
///
/// Konsekuensi yang disengaja (dan inilah alasan mode ini OPSIONAL, bukan
/// pengganti):
/// - Node dengan kredensial salah atau egress diblokir akan tetap terlihat
///   "hidup", karena portnya memang terbuka. Hanya cek internet yang bisa
///   menangkapnya.
/// - Balasannya jauh lebih cepat dan tidak membakar CPU, jadi cocok untuk
///   menyaring 16.000 server jadi beberapa ratus sebelum ping internet.
public enum ServerPinger {
    /// Verdict saat deadline habis tanpa balasan.
    ///
    /// DIPISAHKAN dari jitteran supaya aturan ini bisa diuji TANPA
    /// jaringan. Test sebelumnya memakai alamat publik dan mengharapkan
    /// diam; di jaringan tertentu alamat itu dijawab proxy atau captive
    /// portal, jadi test gagal tanpa alasan yang benar — persis kelas test
    /// yang membuatnya tidak bisa dipercaya. Aturan ini murni soal
    /// kebijakan, jadi ia harus diuji sebagai kebijakan.
    ///
    /// TCP → `dead`: tidak ada handshake = tidak ada bukti hidup.
    /// UDP → `aliveUpperBound`: server QUIC tidak pernah menjawab paket acak,
    /// jadi timeout di sini justru bukti hidup, bukan bukti kematian.
    public nonisolated static func verdictOnTimeout(for proto: NodeProtocol) -> ServerPingOutcome {
        proto == .hysteria2
            ? .aliveUpperBound(AppConstants.serverPingUDPTimeoutMs)
            : .dead
    }

    /// Satu uji ke satu node.
    public static func ping(_ node: ProxyNode,
                            timeout: TimeInterval = AppConstants.serverPingTimeout) async -> ServerPingOutcome {
        guard !node.host.isEmpty, node.port > 0, node.port <= 65535 else { return .dead }
        switch node.proto {
        case .hysteria2:
            return await udpProbe(node.host, node.port, timeout: AppConstants.serverPingUDPTimeout)
        default:
            return await tcpProbe(node.host, node.port, timeout: timeout)
        }
    }

    // MARK: - TCP

    /// Handshake TCP ke `host:port`. Sukses = server menerima koneksi.
    private static func tcpProbe(_ host: String, _ port: Int,
                                 timeout: TimeInterval) async -> ServerPingOutcome {
        guard let conn = makeConnection(host: host, port: port, using: .tcp) else { return .dead }
        let start = Date()
        return await race(conn: conn, timeout: timeout, start: start, onTimeout: .dead) { state in
            switch state {
            case .ready:  return .finished(.replied(Self.elapsedMs(since: start)))
            case .failed: return .finished(.dead)
            default:      return .keepWaiting
            }
        }
    }

    // MARK: - UDP (Hysteria2)

    /// Probe UDP untuk protokol QUIC.
    ///
    /// `.ready` pada `NWConnection` UDP berarti socket lokal siap — BUKAN ada
    /// percakapan, karena UDP tidak punya handshake. Jadi setelah `.ready` kita
    /// kirim satu datagram lalu menunggu: satu-satunya bukti "tidak hidup"
    /// adalah kernel melaporkan ICMP port-unreachable, yang sampai ke app
    /// sebagai `.failed`.
    ///
    /// Kalau tidak ada error sampai deadline, kesimpulannya "tidak ada bukti
    /// kematian" — dan itu sengaja dianggap HIDUP. Membalik aturan ini akan
    /// menandai hampir semua HY2 yang sehat sebagai mati, karena server QUIC
    /// memang tidak pernah menjawab paket acak. Kesalahan itu jauh lebih
    /// merusak daripada misses pada node HY2 yang portnya sungguhan sudah
    /// ditutup di firewall.
    private static func udpProbe(_ host: String, _ port: Int,
                                 timeout: TimeInterval) async -> ServerPingOutcome {
        guard let conn = makeConnection(host: host, port: port, using: .udp) else { return .dead }
        return await race(conn: conn, timeout: timeout, start: Date(),
                          onTimeout: verdictOnTimeout(for: .hysteria2)) { state in
            switch state {
            case .ready:
                conn.send(content: UDPProbe.payload, completion: .contentProcessed { _ in })
                return .keepWaiting
            case .failed:
                return .finished(.dead)
            default:
                return .keepWaiting
            }
        }
    }

    /// Datagram pemicu. Isinya tidak penting — yang penting kernel sempat
    /// mencoba mengirimnya sehingga ICMP error bisa sampai ke kita.
    private enum UDPProbe {
        static let payload: Data = Data([0x00])
    }

    // MARK: - Inti

    private static func makeConnection(host: String, port: Int,
                                       using params: NWParameters) -> NWConnection? {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else { return nil }
        return NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: params)
    }

    /// Apa yang harus dilakukan terhadap satu perubahan state koneksi.
    private enum Step {
        /// Belum ada bukti apa pun — lanjut menunggu.
        case keepWaiting
        /// Keputusan selesai, canonical.
        case finished(ServerPingOutcome)
    }

    private static func elapsedMs(since start: Date) -> Int {
        max(1, Int(Date().timeIntervalSince(start) * 1000))
    }

    /// Jalankan satu koneksi sambil berlomba dengan deadline.
    ///
    /// `NWConnection` berbasis callback dan tidak bisa dibatalkan lewat
    /// `await`, jadi racing-nya dibuat dengan `withTaskGroup`: dua anak
    /// (koneksi vs timer), anak pertama yang selesai menang, sisanya
    /// dibatalkan. Setelah hasilnya diambil, `conn.cancel()` dipanggil supaya
    /// anak yang masih menggantung selalu bangun oleh state `.cancelled` —
    /// tanpa itu `withTaskGroup` akan menggantung sampai timeout kedua pada
    /// setiap node yang timeout.
    private static func race(conn: NWConnection, timeout: TimeInterval, start: Date,
                             onTimeout: ServerPingOutcome,
                             step: @escaping (NWConnection.State) -> Step) async -> ServerPingOutcome {
        let ns = UInt64(max(0.05, timeout) * 1_000_000_000)
        return await withTaskGroup(of: ServerPingOutcome.self) { group in
            group.addTask {
                await withCheckedContinuation { (cont: CheckedContinuation<ServerPingOutcome, Never>) in
                    let lock = NSLock()
                    var settled = false
                    func settle(_ outcome: ServerPingOutcome) {
                        lock.lock()
                        let already = settled
                        settled = true
                        lock.unlock()
                        if !already { cont.resume(returning: outcome) }
                    }
                    conn.stateUpdateHandler = { state in
                        if case .cancelled = state {
                            settle(.dead)
                            return
                        }
                        if case .finished(let outcome) = step(state) { settle(outcome) }
                    }
                    conn.start(queue: .global(qos: .userInitiated))
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: ns)
                return onTimeout
            }
            let result = await group.next() ?? .dead
            group.cancelAll()
            conn.cancel()
            return result
        }
    }
}
