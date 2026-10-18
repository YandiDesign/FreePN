import XCTest
@testable import FreePNApp

/// D69 — panel log berbunyi "tak terbaca" padahal log-nya ada.
///
/// BUG: helper <= 1.3 (yang sudah terpasang) masih menulis ke `/tmp`, sementara
/// app versi ini membaca `/var/log` (perpindahan D61). App diperbarui, helper
/// tidak — jadi kedua sisi menunjuk file BERBEDA tanpa error apa pun.
final class ConnectionLogFallbackTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("freepn-logtest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func make(_ name: String, _ text: String) -> String {
        let p = dir.appendingPathComponent(name)
        try! text.write(to: p, atomically: true, encoding: .utf8)
        return p.path
    }

    /// Path baru dipakai kalau ada — tidak boleh turun ke yang lama.
    func testPrefersNewLocationWhenPresent() {
        let new = make("new.log", "BARU\n")
        let old = make("old.log", "LAMA\n")
        let (text, shown) = ConnectionLog.tailWithLegacyFallback(preferred: new, legacy: old,
                                                                 maxLines: 10)
        XCTAssertEqual(shown, new)
        XCTAssertTrue(text.contains("BARU"))
        XCTAssertFalse(text.contains("LAMA"))
    }

    /// Ini kasus user: app baru, helper lama. Path baru tidak ada, log lama ada
    /// dan berisi isi. Panel harus menunjuki log NYATA, bukan "tak terbaca".
    func testFallsBackToLegacyLocation() {
        let missing = dir.appendingPathComponent("tidak-ada.log").path
        let old = make("old.log", "isi log lama\n")
        let (text, shown) = ConnectionLog.tailWithLegacyFallback(preferred: missing, legacy: old,
                                                                 maxLines: 10)
        XCTAssertEqual(shown, old, "path yang ditampilkan harus yang benar-benar dibaca")
        XCTAssertTrue(text.contains("isi log lama"))
        XCTAssertNotEqual(text, L10n.string("log_unreadable"))
    }

    /// Header menampilkan path yang dipakai — kalau tidak, user melihat header
    /// "/var/log/..." sementara isinya dari "/tmp", dan tidak bisa disbanded.
    ///
    /// D75: versi pertama test ini memakai path BAWAAN dan sebaliknya melewati
    /// dir, padahal fallback-nya tidak bisa di-override — hasilnya test membaca
    /// log NYATA di mesin ini. Itu membuat test gagal di app yang sedang berjalan
    /// (`/tmp/freepn-core-stderr.log` berisi error core asli) ikut gagal.
    ///
    /// Test yang bergantung pada file di luar tempdir bukan test hermetik:
    /// ia bisa hijau di laptop bersih dan merah di mesin yang sedang dipakai —
    /// persis yang terjadi. Sekarang `snapshot` menerima KEDUA path, dan test
    /// ini memakai tempdir sepenuhnya.
    func testSnapshotHeaderNamesThePathActuallyRead() {
        let missingHelper = dir.appendingPathComponent("nh.log").path
        let legacy = make("legacy-helper.log", "isi helper lama\n")
        let out = ConnectionLog.snapshot(header: "HDR",
                                         helperPath: missingHelper,
                                         corePath: dir.appendingPathComponent("nc.log").path,
                                         legacyHelperPath: legacy,
                                         legacyCorePath: dir.appendingPathComponent("lc.log").path,
                                         maxLines: 5)
        XCTAssertTrue(out.contains("HDR"))
        XCTAssertTrue(out.contains(legacy), "header harus menyebut path fallback yang dipakai")
    }

    /// Path temp dipakai penuh — tidak ada file nyata di luar tempdir yang
    /// boleh memengaruhi hasil.
    func testSnapshotIsHermeticUnderTempPaths() {
        let h = make("h.log", "isi helper\n")
        let out = ConnectionLog.snapshot(header: "HDR",
                                         helperPath: h,
                                         corePath: dir.appendingPathComponent("c1.log").path,
                                         legacyHelperPath: dir.appendingPathComponent("c2.log").path,
                                         legacyCorePath: dir.appendingPathComponent("c3.log").path,
                                         maxLines: 5)
        XCTAssertTrue(out.contains("isi helper"))
        XCTAssertFalse(out.contains("freepn-helper.log"),
                       "tidak boleh menyentuh path log sungguhan")
        XCTAssertFalse(out.contains("/tmp/"), "tidak boleh menyentuh /tmp sungguhan")
    }

    /// File yang ADA tapi KOSONG tetap dipakai. Helper yang baru start menulis
    /// log kosong sesaat; mengembalikan "tak terbaca" di titik itu menyesatkan
    /// (seolah file hilang) dan membuat user Mulai reinstall.
    func testEmptyButExistingFileIsNotTreatedAsMissing() {
        let empty = make("empty.log", "")
        let (text, shown) = ConnectionLog.tailWithLegacyFallback(preferred: empty,
                                                                 legacy: dir.appendingPathComponent("x.log").path,
                                                                 maxLines: 5)
        XCTAssertEqual(shown, empty)
        XCTAssertNotEqual(text, L10n.string("log_unreadable"))
    }

    /// Dua-duanya tidak ada = "tak terbaca", dan path yang ditampilkan tetap
    /// yang diharapkan (bukan fallback), supaya pesan error mengarahkan ke
    /// lokasi yang benar.
    func testBothMissingReportsUnreadableAtPreferredPath() {
        let a = dir.appendingPathComponent("a.log").path
        let b = dir.appendingPathComponent("b.log").path
        let (text, shown) = ConnectionLog.tailWithLegacyFallback(preferred: a, legacy: b, maxLines: 5)
        XCTAssertEqual(text, L10n.string("log_unreadable"))
        XCTAssertEqual(shown, a)
    }
}

/// D70 — bagian log Core disembunyikan saat kosong, TAPI tidak dihapus.
///
/// Core yang start bersih tidak menulis apa pun ke stderr, jadi panel
/// menampilkan "(kosong)" dan hanya memboros ruang. Tapi begitu ada masalah,
/// isi core adalah bukti yang paling menentukan (`ERROR ... listen packet
/// connection using tun`), jadi bagian ini harus muncul kembali tepat ketika
/// dibutuhkan.
final class CoreSectionVisibilityTests: XCTestCase {
    private var dir: URL!
    override func setUpWithError() throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("freepn-coresec-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }
    private func make(_ name: String, _ text: String) -> String {
        let p = dir.appendingPathComponent(name)
        try! text.write(to: p, atomically: true, encoding: .utf8)
        return p.path
    }

    /// Path yang SENGAJA tidak ada, di dalam tempdir.
    ///
    /// D75: test D70 dulu mengoper `helperPath`/`corePath` temp tapi TIDAK
    /// mengoper path legacy, sehingga `snapshot()` jatuh ke konstanta
    /// `/tmp/freepn-core-stderr.log` yang SEDANG berisi error core asli di
    /// mesin ini — test gagal karena file nyata, bukan karena bug. Tanpa ini,
    /// testnya hanya hijau di mesin yang log-nya kosong.
    private func absent() -> String {
        dir.appendingPathComponent("tidak-ada-\(UUID().uuidString).log").path
    }

    /// Inti: core kosong → bagiannya TIDAK muncul sama sekali. Ini yang
    /// diminta user ("log bawah hapus saja, kosong").
    func testEmptyCoreSectionIsOmitted() {
        let h = make("h.log", "isi helper\n")
        let c = make("c.log", "")
        let out = ConnectionLog.snapshot(header: "HDR", helperPath: h, corePath: c,
                                         legacyHelperPath: absent(), legacyCorePath: absent(),
                                         maxLines: 10)
        XCTAssertTrue(out.contains("HDR"))
        XCTAssertTrue(out.contains("isi helper"))
        XCTAssertFalse(out.contains(L10n.string("log_core")),
                       "core kosong tidak boleh menambah bagian kosong ke panel")
    }

    /// Tapi begitu core bicara, bagiannya WAJIB muncul. Menghapus permanen
    /// akan membuang bukti kenapa connect gagal.
    func testNonEmptyCoreSectionStillAppears() {
        let h = make("h.log", "isi helper\n")
        let c = make("c.log", "ERROR[0086] connection: listen packet connection using tun\n")
        let out = ConnectionLog.snapshot(header: "HDR", helperPath: h, corePath: c,
                                         legacyHelperPath: absent(), legacyCorePath: absent(),
                                         maxLines: 10)
        XCTAssertTrue(out.contains(L10n.string("log_core")),
                       "core yang punya isi harus tetap tampil")
        XCTAssertTrue(out.contains("listen packet connection"))
    }

    /// "Tak terbaca" juga disembunyikan untuk core: tidak ada di sana juga
    /// tidak menambah informasi apa pun.
    func testUnreadableCoreSectionIsOmitted() {
        let h = make("h.log", "isi helper\n")
        let out = ConnectionLog.snapshot(header: "HDR", helperPath: h,
                                         corePath: dir.appendingPathComponent("nope.log").path,
                                         legacyHelperPath: absent(), legacyCorePath: absent(),
                                         maxLines: 10)
        XCTAssertTrue(out.contains("isi helper"))
        XCTAssertFalse(out.contains(L10n.string("log_core")))
    }

    func testBlankDetection() {
        XCTAssertTrue(ConnectionLog.isBlank(""))
        XCTAssertTrue(ConnectionLog.isBlank("   \n  "))
        XCTAssertTrue(ConnectionLog.isBlank(L10n.string("log_empty")))
        XCTAssertTrue(ConnectionLog.isBlank(L10n.string("log_unreadable")))
        XCTAssertFalse(ConnectionLog.isBlank("apa saja"))
        // Spasi di sekitar penanda localized tidak boleh dianggap non-kosong.
        XCTAssertTrue(ConnectionLog.isBlank("  \(L10n.string("log_empty"))  "))
    }
}

/// D69 — versi helper harus TERDETEKSI, bukan ditebak.
///
/// Helper 1.3 lama dan 1.4 baru sama-sama melaporkan "FreePNHelper 1.3"
/// sebelum D69, sehingga pemeriksaan kesehatan menyatakan "OK" untuk helper
/// yang menulis ke lokasi log yang salah. twofold: versi harus Expected naik,
/// dan pencocokan harus ketat.
final class HelperVersionTests: XCTestCase {
    func testExpectedVersionIsInCompatibleList() {
        XCTAssertTrue(AppConstants.helperCompatibleVersions.contains(AppConstants.helperVersion),
                      "versi yang diharapkan harus selalu dianggap kompatibel")
    }

    /// Helper yang sudah terpasang (1.3) tetap boleh dipakai — bedanya cuma
    /// lokasi log, dan TETAP BEKERJA. Menolaknya akan memutus VPN pada
    /// setiap user yang belum reinstall, padahal tidak ada yang rusak.
    func testPreviousVersionStillAccepted() {
        XCTAssertTrue(HealthChecker.isHelperVersionAcceptable("FreePNHelper 1.3"))
    }

    func testCurrentVersionAccepted() {
        XCTAssertTrue(HealthChecker.isHelperVersionAcceptable("FreePNHelper 1.4"))
    }

    /// Helper lama yang punya bug state-per-koneksi (D69 pre-1.3) masih ditolak.
    func testOldBrokenVersionRejected() {
        XCTAssertFalse(HealthChecker.isHelperVersionAcceptable("FreePNHelper 1.2"))
        XCTAssertFalse(HealthChecker.isHelperVersionAcceptable(""))
        XCTAssertFalse(HealthChecker.isHelperVersionAcceptable("bukan helper"))
    }

    /// "1.30" BUKAN "1.3". `contains` biasa akan menerimanya, dan itu berarti
    /// versi fiktif bisa lolos pemeriksaan kesehatan.
    func testVersionMatchingIsNotSubstringLoose() {
        XCTAssertFalse(HealthChecker.isHelperVersionAcceptable("FreePNHelper 1.30"))
        XCTAssertFalse(HealthChecker.isHelperVersionAcceptable("FreePNHelper 1.40"))
    }

    /// Helper yang laporkan versi Expected di dalam teks lain tidak boleh
    /// dianggap healthy — ini yang membuat "1.4" pada string arbitrer lolos.
    func testVersionMustAppearAsToken() {
        XCTAssertFalse(HealthChecker.isHelperVersionAcceptable("FreePNHelper v1.4-beta"))
        XCTAssertTrue(HealthChecker.isHelperVersionAcceptable("FreePNHelper 1.4 (arm64)"))
    }

    /// Helper harus melaporkan versi dari `AppConstants` — kalau literalnya
    /// ditulis terpisah di dua tempat, keduanya pasti menyimpang diam-diam dan
    /// pemeriksaan kesehatan menilai build yang salah.
    func testHelperSourceUsesSharedConstant() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // FreePNTests/
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("FreePNHelper/HelperService.swift")
        let src = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(src.contains("AppConstants.helperVersion"),
                      "HelperService harus baca AppConstants.helperVersion, bukan literal")
        XCTAssertFalse(src.contains("FreePNHelper 1.4"),
                       "versi tidak boleh ditulis literal di helper")
    }
}
