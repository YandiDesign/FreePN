import Foundation

/// Satu baris log pengujian konektivitas (D93).
///
/// Kenapa ini ada: laporan user yang paling sulit ditangani adalah "ping all
/// bilang semua mati, tapi pas saya coba beberapa, internetnya normal". Tanpa
/// catatan, kedua klaim itu sama-sama tidak bisa dibuktikan — dan satu-satunya
/// cara menebak adalah mengganti hostname, yang sekarang bisa dilakukan lewat
/// Pengaturan tapi tetap hanya menebak.
///
/// Yang dicatat: node mana, hasilnya apa, dan **sebab kegagalan kalau ada**.
/// Baris "gagal" tanpa sebabnya persis masalah yang membuat app ini sebelumnya
/// selalu menyalahkan kredensial.
public struct PingLogEntry: Identifiable {
    public let id = UUID()

    public enum Kind: String, Hashable {
        /// Uji internet sungguhan (lewat core sing-box).
        case internet
        /// Ping cepat TCP/UDP.
        case fast
        /// Peristiwa tingkat sesi: core gagal start, config ditolak, batas
        /// waktu habis. Tanpa ini, "semua mati" dan "core-nya tidak pernah
        /// jalan" terlihat identik dari sisi user.
        case session

        public var label: String {
            switch self {
            case .internet: return L10n.string("ping_log_kind_internet")
            case .fast:     return L10n.string("ping_log_kind_fast")
            case .session:  return L10n.string("ping_log_kind_session")
            }
        }
    }

    public var at: Date
    public var kind: Kind
    public var nodeID: String
    /// Nama node saat pengujian. Disalin, bukan diambil lewat `nodeIndex`:
    /// log harus tetap bisa dibaca setelah node-nya dihapus.
    public var nodeName: String
    public var proto: String
    public var host: String
    /// Host tujuan uji. `nil` untuk baris bertipe `.session` yang bukan uji.
    public var targetHost: String?
    /// Latensi hasil uji, kalau sukses.
    public var ms: Int?
    /// Verdict apa adanya — `nil` untuk baris `.session`.
    public var verdict: ProbeVerdict?

    public var failure: ProbeFailure? {
        if case .failed(let why) = verdict { return why }
        return nil
    }

    public var ok: Bool { if case .ok = verdict { return true }; return false }

    /// True kalau hasilnya `skipped` — diuji sebagian, atau core-nya tumbang.
    public var skipped: Bool { if case .skipped = verdict { return true }; return false }

    /// Ringkasan satu baris untuk UI.
    public var summary: String {
        switch kind {
        case .session:
            return nodeName
        case .fast, .internet:
            if ok, let ms = ms { return L10n.formatted("ping_log_ok", ms) }
            if skipped { return L10n.string("ping_log_skipped") }
            return failure.map { L10n.string("ping_log_failed_\($0.rawValue)") }
                ?? L10n.string("ping_log_failed_unknown")
        }
    }

    public init(at: Date = Date(), kind: Kind, nodeID: String = "", nodeName: String = "",
                proto: String = "", host: String = "", targetHost: String? = nil,
                ms: Int? = nil, verdict: ProbeVerdict? = nil) {
        self.at = at
        self.kind = kind
        self.nodeID = nodeID
        self.nodeName = nodeName
        self.proto = proto
        self.host = host
        self.targetHost = targetHost
        self.ms = ms
        self.verdict = verdict
    }
}

/// Ringkasan satu putaran ping — jawaban langsung untuk "kenapa semua mati".
public struct PingRunSummary {
    public var startedAt: Date
    public var targetHost: String
    public var mode: PingTarget
    public var tested: Int
    public var alive: Int
    /// Node yang ditolak CORE, jadi tidak pernah diuji sama sekali.
    public var rejectedByCore: Int
    /// Berapa yang tidak sempat diuji karena batas waktu habis.
    public var notTested: Int
    public var stoppedByBudget: Bool
    /// Penyebab kegagalan -> berapa kali muncul.
    public var byFailure: [ProbeFailure: Int]

    public init(startedAt: Date = Date(), targetHost: String = "", mode: PingTarget = .gstatic,
                tested: Int = 0, alive: Int = 0, rejectedByCore: Int = 0,
                notTested: Int = 0, stoppedByBudget: Bool = false,
                byFailure: [ProbeFailure: Int] = [:]) {
        self.startedAt = startedAt
        self.targetHost = targetHost
        self.mode = mode
        self.tested = tested
        self.alive = alive
        self.rejectedByCore = rejectedByCore
        self.notTested = notTested
        self.stoppedByBudget = stoppedByBudget
        self.byFailure = byFailure
    }

    /// Kalimat satu baris yang langsung menjawab pertanyaan user.
    public var headline: String {
        L10n.formatted("ping_summary_headline", alive, tested,
                       targetHost.isEmpty ? mode.label : targetHost)
    }

    /// Daftar sebab kegagalan, dari yang paling sering.
    public var failureChips: [(ProbeFailure, Int)] {
        byFailure.sorted { lhs, rhs in
            lhs.value == rhs.value ? lhs.key.rawValue < rhs.key.rawValue : lhs.value > rhs.value
        }
    }
}