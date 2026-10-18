import XCTest

/// D84 — peta dunia harus menandi server yang SEDANG DIPAKAI, bukan server
/// yang DIREKOMENDASIKAN.
///
/// Gejalanya (dilaporkan user): peta menampilkan negara A, padahal tunnel
/// sedang berjalan di negara B.
///
/// Akar masalahnya bukan di `ServerWorldMap` — itu view murni yang benar —
/// tapi di CALL SITE-nya: peta pernah diberi `state.recommendedNode`, yang
/// (`AppState.recommendedNode`) jatuh ke `selectedNode ?? quickConnectNode()
/// ?? filteredNodes.first`. Artinya peta menunjuk server tebakan bahkan saat
/// tidak ada sambungan apa pun, dan bisa loncat ke node lain setiap ping
/// tiba (`invalidateDerived()` membuang cache rekomendasi).
///
/// Test lain (`RedesignLogicTests`) mengunci FUNGSI: `mapNode` dan `pins`.
/// Test ini mengunci PEMAKAIAN-nya, karena fungsi yang benar tetap bisa
/// disalahpakai oleh pemanggil yang salah — persis yang terjadi di sini.
///
/// Ini memindai SOURCE, sama seperti `OverflowMenuStylingTests`. Yang dijaga
/// adalah invarian struktural, bukan perilaku runtime.
final class MapNodeSourceTests: XCTestCase {

    private func read(_ relPath: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relPath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private var connectViewSource: String {
        (try? read("FreePN/UI/ConnectView.swift")) ?? ""
    }

    /// Sanity check: kalau file tidak terbaca, semua assertion lain di kelas
    /// ini akan lolos karena string kosong. Ini yang mencegah tes hening.
    func testSourceIsActuallyRead() throws {
        let src = connectViewSource
        XCTAssertGreaterThan(src.count, 20_000, "FreePN/UI/ConnectView.swift tidak terbaca")
        XCTAssertTrue(src.contains("struct ConnectView"))
        XCTAssertTrue(src.contains("struct ServerWorldMap"))
    }

    /// REGRESI UTAMA: peta tidak boleh diberi `recommended`.
    func testMapIsNeverFedTheRecommendedNode() {
        let src = connectViewSource
        for (offset, line) in src.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            guard line.contains("ServerWorldMap(") else { continue }
            XCTAssertFalse(line.contains("recommended"),
                           "ConnectView.swift:\(offset + 1) — peta diberi server yang "
                           + "direkomendasikan; harusnya `activeNode` (server yang dipakai)")
        }
    }

    /// Pemanggilan peta harus mengoper `activeNode`, dan status sambung harus
    /// ikut dioper supaya denyut berarti "tunnel hidup".
    func testMapIsFedActiveNodeWithConnectionStatus() throws {
        let call = try XCTUnwrap(
            Self.slice(connectViewSource, from: "ServerWorldMap(",
                       to: ".frame(maxWidth: .infinity, maxHeight: .infinity"),
            "tidak menemukan pemanggilan ServerWorldMap di mapCard")
        XCTAssertTrue(call.contains("node: activeNode"),
                      "peta harus memakai activeNode, bukan node lain")
        XCTAssertTrue(call.contains("isConnected:"),
                      "peta harus diberi status sambung; tanpa itu denyut berarti "
                      + "\"ada node\", bukan \"tunnel hidup\"")
    }

    /// `activeNode` harus lahir dari `mapNode(connected:selected:)` supaya
    /// aturan "terhubung menang atas terpilih" bisa diuji sebagai fungsi murni.
    func testActiveNodeComesFromTheTestableHelper() throws {
        let body = try XCTUnwrap(
            Self.slice(connectViewSource, from: "var activeNode: ProxyNode? {", to: "\n    }"),
            "tidak menemukan `activeNode`")
        XCTAssertTrue(body.contains("Self.mapNode("),
                      "activeNode harus lewat mapNode(connected:selected:) supaya "
                      + "aturan 'terhubung menang atas terpilih' bisa diuji")
    }

    /// D88 — peta hidup di `mapCard` sendiri, kartu dominan layar ini.
    ///
    /// Dan yang sama pentingnya: peta TIDAK boleh muncul di kartu Koneksi
    /// maupun di kartu Daya. Dua kartu itu menjawab pertanyaan berbeda —
    /// "trafik apa yang sedang lewat" dan "apa status tunnel" — sedangkan peta
    /// menjawab "negara mana yang sedang saya pakai". Kalau ketiganya digabung
    /// lagi, pin akan pindah-pindah hanya karena isi kartu berubah.
    func testMapLivesInItsOwnCardAndNowhereElse() throws {
        let src = connectViewSource
        let mapCard = try XCTUnwrap(
            Self.slice(src, from: "private var mapCard: some View {",
                       to: "private var powerCard: some View {"),
            "tidak menemukan mapCard")
        XCTAssertTrue(mapCard.contains("ServerWorldMap("),
                      "peta harus ada di mapCard")

        let powerCard = try XCTUnwrap(
            Self.slice(src, from: "private var powerCard: some View {",
                       to: "// MARK: - Tinggi terkunci"),
            "tidak menemukan powerCard")
        XCTAssertFalse(powerCard.contains("ServerWorldMap("),
                       "peta tidak boleh di kartu Daya")

        // Kartu koneksi live tinggal di file sendiri; peta tidak boleh ada
        // di sana — kartu itu soal koneksi yang LEWAT, peta soal server
        // yang DIPAKAI.
        let card = try XCTUnwrap(
            read("FreePN/UI/ConnectionsCard.swift"),
            "tidak menemukan ConnectionsCard.swift")
        XCTAssertFalse(card.contains("ServerWorldMap("),
                       "peta tidak boleh di kartu Koneksi Aktif")
    }

    /// Slot di atas peta sekarang milik kartu Koneksi Aktif, bukan strip
    /// rekomendasi. Kartu rekomendasi ("satu saran server statis") dihapus
    /// karena informasinya kalah penting dari "koneksi apa yang sedang lewat
    /// tunnel" — yang hanya ada saat VPN hidup.
    func testConnectionsCardReplacesRecommendedSlot() throws {
        let src = connectViewSource
        XCTAssertFalse(src.contains("recommendedCard"),
                       "strip rekomendasi sudah dihapus dari ConnectView")
        XCTAssertFalse(src.contains("card_recommended"),
                       "key kartu rekomendasi tidak boleh dipakai lagi")

        let top = try XCTUnwrap(
            Self.slice(connectViewSource, from: "private var topRow: some View {",
                       to: "/// Trafik + Sumber Subscription"),
            "tidak menemukan topRow")
        XCTAssertTrue(top.contains("ConnectionsCard(connection:"),
                      "slot di atas peta harus diisi ConnectionsCard")

        // Kartu koneksi menempel ke isinya (seperti strip lama), bukan
        // diregangkan — dan datanya dari Clash API core, bukan tebakan.
        let card = try XCTUnwrap(
            read("FreePN/UI/ConnectionsCard.swift"),
            "tidak menemukan ConnectionsCard.swift")
        XCTAssertTrue(card.contains(".fixedSize(horizontal: false, vertical: true)"),
                      "kartu harus menempel ke isinya")
        XCTAssertTrue(card.contains("/connections"),
                      "kartu harus membaca koneksi live dari Clash API")
    }

    // MARK: - Helper

    /// Potong source di antara dua anchor, keduanya WAJIB ada. Mengembalikan
    /// `nil` kalau anchor tidak ditemukan, supaya assertion di pemanggil
    /// gagal dengan pesan yang benar dan bukan diam-diam lolos.
    private static func slice(_ src: String, from start: String, to end: String) -> String? {
        guard let r = src.range(of: start) else { return nil }
        let rest = r.upperBound
        guard let e = src.range(of: end, range: rest..<src.endIndex) else { return nil }
        return String(src[rest..<e.lowerBound])
    }
}