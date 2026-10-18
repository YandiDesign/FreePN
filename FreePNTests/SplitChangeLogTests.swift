import XCTest
@testable import FreePNApp

/// Riwayat perubahan split: diff-nya harus menangkap perubahan yang
/// benar-benar mengubah arah traffic, dan penjelasannya harus jujur soal
/// KAPAN aturan itu berlaku.
final class SplitChangeLogTests: XCTestCase {

    private func entry(_ action: SplitChangeLog.Action, _ mode: SplitMode) -> SplitChangeLog.Entry {
        SplitChangeLog.Entry(appName: "Safari", bundlePath: "/Applications/Safari.app",
                             mode: mode, action: action)
    }

    private func text(_ action: SplitChangeLog.Action, _ mode: SplitMode) -> String {
        SplitChangeLog.describe(entry(action, mode)).joined(separator: "\n")
    }

    /// Assertion di bawah TIDAK boleh menuliskan kalimat dalam bahasa Inggris
    /// sebagai teks yang dicari. `SplitChangeLog.describe` memakai
    /// `NSLocalizedString`, jadi hasilnya mengikuti bahasa sistem — di mesin
    /// dengan `AppleLanguages = id-ID` seluruh assertion literal Inggris
    /// gagal padahal log-nya sebenarnya benar. Semua assertion sekarang
    /// mengambil key yang sama dengan production code, jadi berlaku di bahasa
    /// mana pun.
    private func l(_ key: String) -> String { L10n.string(key) }

    // MARK: - Arah "memakai VPN"

    /// Eksklusif berbalik arah dari dua mode lain. Kalau ini salah, tombol
    /// "Set sebagai VPN" justru akan membuat app TIDAK lewat VPN — persis
    /// kebalikan dari labelnya.
    func testUsesVPNSemanticsPerMode() {
        XCTAssertTrue(SplitMode.inclusive.usesVPN(appIsListed: true))
        XCTAssertFalse(SplitMode.inclusive.usesVPN(appIsListed: false))
        XCTAssertFalse(SplitMode.exclusive.usesVPN(appIsListed: true))
        XCTAssertTrue(SplitMode.exclusive.usesVPN(appIsListed: false))
    }

    // MARK: - Diff

    func testAddingAppInInclusiveIsEnable() {
        let changes = SplitChangeLog.diff(listedBefore: [], listedAfter: ["/Applications/Chrome.app"],
                                          modeBefore: .inclusive, modeAfter: .inclusive)
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes[0].bundlePath, "/Applications/Chrome.app")
        XCTAssertEqual(changes[0].action, .enable)
    }

    /// app baru DITAMBAHKAN ke daftar eksklusif = justru MATIKAN VPN-nya.
    /// Membandingkan daftar mentah tanpa melihat mode akan salah di sini.
    func testAddingAppInExclusiveIsDisable() {
        let changes = SplitChangeLog.diff(listedBefore: [], listedAfter: ["/Applications/Chrome.app"],
                                          modeBefore: .exclusive, modeAfter: .exclusive)
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes[0].action, .disable)
    }

    func testRemovingAppInExclusiveIsEnable() {
        let changes = SplitChangeLog.diff(listedBefore: ["/Applications/Chrome.app"], listedAfter: [],
                                          modeBefore: .exclusive, modeAfter: .exclusive)
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes[0].action, .enable)
    }

    /// Ganti mode dengan daftar yang sama: efek tiap app berbalik, dan itu
    /// perubahan nyata yang harus tercatat — bukan "tidak ada yang berubah".
    func testModeSwitchFlipsEveryListedApp() {
        let list: Set<String> = ["/Applications/Chrome.app", "/Applications/Mail.app"]
        let changes = SplitChangeLog.diff(listedBefore: list, listedAfter: list,
                                          modeBefore: .inclusive, modeAfter: .exclusive)
        XCTAssertEqual(changes.count, 2)
        XCTAssertTrue(changes.allSatisfy { $0.action == .disable })
    }

    /// Ganti mode dengan daftar KOSONG: di eksklusif semua app sudah lewat VPN
    /// dan akan tetap begitu — jadi memang tidak ada yang berubah.
    func testModeSwitchWithEmptyListChangesNothing() {
        let changes = SplitChangeLog.diff(listedBefore: [], listedAfter: [],
                                          modeBefore: .inclusive, modeAfter: .exclusive)
        XCTAssertTrue(changes.isEmpty)
    }

    func testNoChangeProducesNoEntries() {
        let list: Set<String> = ["/Applications/Chrome.app"]
        XCTAssertTrue(SplitChangeLog.diff(listedBefore: list, listedAfter: list,
                                          modeBefore: .inclusive, modeAfter: .inclusive).isEmpty)
    }

    func testDiffIsDeterministic() {
        let before: Set<String> = ["/b.app", "/a.app", "/c.app"]
        let after: Set<String> = ["/c.app"]
        let first = SplitChangeLog.diff(listedBefore: before, listedAfter: after,
                                        modeBefore: .inclusive, modeAfter: .inclusive)
        for _ in 0..<5 {
            XCTAssertEqual(SplitChangeLog.diff(listedBefore: before, listedAfter: after,
                                               modeBefore: .inclusive, modeAfter: .inclusive),
                           first)
        }
        XCTAssertEqual(first.map(\.bundlePath), first.map(\.bundlePath).sorted())
    }

    // MARK: - Isi log

    /// Mode TUN tidak menyuntik env sama sekali. Kalau ini tidak disebut, user
    /// akan mencari `ALL_PROXY` di log dan menyimpulkan app-nya rusak.
    func testTunLogExplicitlySaysNoEnvironment() {
        let on = text(.enable, .inclusive)
        XCTAssertTrue(on.contains("process_path_regex"), on)
        XCTAssertTrue(on.contains(l("splitlog_env_none")), on)
        XCTAssertFalse(on.contains("ALL_PROXY"), on)
    }

    /// Batasan TUN yang paling sering membuat user salah paham: hanya proses yang
    /// melakukan koneksi yang dicocokkan, bukan cucu-cucunya.
    func testTunLogWarnsAboutChildProcesses() {
        XCTAssertTrue(text(.enable, .inclusive).contains("curl"))
        XCTAssertTrue(text(.enable, .exclusive).contains("curl"))
    }

    func testExclusiveEnableWritesDirectOutbound() {
        let on = text(.enable, .exclusive)
        XCTAssertTrue(on.contains("direct"), on)
    }

    /// Aturan TUN baru berlaku setelah sambung ulang; itu yang paling sering
    /// disalahartikan user ("sudah saya centang kok belum jalan").
    func testTunSidesMentionReconnect() {
        XCTAssertTrue(text(.enable, .inclusive).contains(l("splitlog_applies_after_reconnect")))
        XCTAssertTrue(text(.disable, .inclusive).contains(l("splitlog_applies_after_reconnect_off")))
    }

    /// Entri log tidak boleh pernah menyebut core sesi atau env proxy: tidak
    /// ada lagi proses kedua di balik split tunneling, jadi janji seperti itu
    /// akan mengarahkan user mencari penyebab yang sudah tidak ada.
    func testNoEntryPromisesASessionCore() {
        for mode in SplitMode.allCases {
            for action in [SplitChangeLog.Action.enable, .disable] {
                let lines = SplitChangeLog.describe(entry(action, mode))
                for forbidden in ["session", "Session", "ALL_PROXY", "NO_PROXY"] {
                    XCTAssertFalse(lines.contains { $0.contains(forbidden) },
                                   "mode \(mode.rawValue) \(action): \(forbidden) tidak boleh muncul")
                }
            }
        }
    }

    func testHeaderNamesTheAppAndMode() {
        let lines = SplitChangeLog.describe(entry(.enable, .inclusive))
        XCTAssertTrue(lines[0].contains("Safari"))
        XCTAssertTrue(lines[0].contains(SplitMode.inclusive.rawValue))
    }

    // MARK: - Penyimpanan

    func testRoundTripThroughDisk() throws {
        let original = [entry(.enable, .inclusive), entry(.disable, .exclusive)]
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("splitlog-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent(SplitChangeLog.fileName)
        try JSONEncoder().encode(original).write(to: url)
        let back = try JSONDecoder().decode([SplitChangeLog.Entry].self,
                                            from: try Data(contentsOf: url))
        XCTAssertEqual(back.map(\.bundlePath), original.map(\.bundlePath))
        XCTAssertEqual(back.map(\.action), original.map(\.action))
    }

    /// Berkas rusak tidak boleh emptying app atau crash saat launch.
    func testCorruptFileDecodesToEmpty() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("splitlog-bad-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent(SplitChangeLog.fileName)
        try? Data("{bukan json".utf8).write(to: url)
        let back = try? JSONDecoder().decode([SplitChangeLog.Entry].self,
                                             from: try Data(contentsOf: url))
        XCTAssertNil(back, "harus gagal decode, bukan menghasilkan data palsu")
    }

    /// `split_changes.json` versi lama storing entri tanda Terminal berdampingan
    /// dengan entri TUN. Entri Terminal tidak bisa lagi dijelaskan apa pun,
    /// tapi membawanya ikut hilang hanya karena decode satu baris gagal akan
    /// menghapus riwayat yang masih relevan.
    func testLegacyTerminalEntriesAreSkippedWithoutLosingTunEntries() throws {
        let json = """
        [{"id":"00000000-0000-0000-0000-000000000001","at":1,"appName":"Safari",\
        "bundlePath":"/Applications/Safari.app","kind":"vpn","mode":"exclusive",\
        "action":"enable","mixedPort":28108},
        {"id":"00000000-0000-0000-0000-000000000002","at":2,"appName":"Ghostty",\
        "bundlePath":"/Applications/Ghostty.app","kind":"terminal",\
        "action":"enable","mixedPort":28108}]
        """
        let back = SplitChangeLog.decode(Data(json.utf8))
        XCTAssertEqual(back.count, 1)
        XCTAssertEqual(back.first?.bundlePath, "/Applications/Safari.app")
        XCTAssertEqual(back.first?.mode, .exclusive)
        XCTAssertEqual(back.first?.action, .enable)
    }
}

// MARK: - Entri domain

/// Entri domain harus punya penjelasan sendiri.
///
/// Kalau dia memakai teks entri app, `describe` akan menyebut
/// `process_path_regex` untuk aturan yang sebenarnya `domain_suffix`, dan
/// `splitlog_match_process` ("mencocokkan path proses … proses anak seperti
/// curl TIDAK ikut cocok") — yang tidak ada hubungannya sama sekali dengan
/// domain. User akan mencari matcher yang tidak pernah ditulis dan
/// menyimpulkan split domain-nya rusak.
final class SplitDomainChangeLogTests: XCTestCase {
    private func l(_ key: String) -> String { L10n.string(key) }

    private func lines(isDomain: Bool, mode: SplitMode, action: SplitChangeLog.Action) -> [String] {
        SplitChangeLog.describe(
            SplitChangeLog.Entry(appName: "bank.com", bundlePath: "bank.com",
                                 mode: mode, action: action, isDomain: isDomain))
    }

    func testDomainEntryNeverUsesAppWording() {
        for action in [SplitChangeLog.Action.enable, .disable] {
            let joined = lines(isDomain: true, mode: .exclusive, action: action).joined(separator: "\n")
            XCTAssertFalse(joined.contains("process_path_regex"),
                           "entri domain tidak boleh menyebut process_path_regex")
            XCTAssertFalse(joined.contains("curl"),
                           "peringatan proses anak hanya berlaku untuk entri app")
        }
    }

    /// Matcher hanya disebut saat rule benar-benar DITULIS. Saat disable
    /// aturannya dihapus, jadi tidak ada matcher yang bisa disebut.
    func testDomainEnableNamesItsMatcher() {
        let joined = lines(isDomain: true, mode: .exclusive, action: .enable).joined(separator: "\n")
        XCTAssertTrue(joined.contains(l("splitlog_match_domain")),
                      "entri domain harus menyebut matcher domain")
    }

    func testDomainEnableNamesTheRuleThatWasWritten() {
        let joined = lines(isDomain: true, mode: .exclusive, action: .enable).joined(separator: "\n")
        XCTAssertTrue(joined.contains("domain_suffix"))
        XCTAssertTrue(joined.contains(l("splitlog_out_direct")),
                      "eksklusif + enable = direct")
    }

    func testDomainEnableInInclusivePointsAtProxy() {
        let joined = lines(isDomain: true, mode: .inclusive, action: .enable).joined(separator: "\n")
        XCTAssertTrue(joined.contains("proxy"))
        XCTAssertFalse(joined.contains(l("splitlog_out_direct")))
    }

    /// Entri app harus TIDAK berubah sama sekali — 17 tes lama masih menguji
    /// teksnya, dan teks itu masih benar.
    func testAppEntryTextIsUnchangedByTheDomainFeature() {
        let joined = lines(isDomain: false, mode: .exclusive, action: .enable).joined(separator: "\n")
        XCTAssertTrue(joined.contains("process_path_regex"))
        XCTAssertTrue(joined.contains(l("splitlog_match_process")))
        XCTAssertTrue(joined.contains("curl"))
    }

    func testNoEntryPromisesAProxyEnvVariable() {
        for isDomain in [true, false] {
            for mode in SplitMode.allCases {
                for action in [SplitChangeLog.Action.enable, .disable] {
                    let joined = lines(isDomain: isDomain, mode: mode, action: action).joined(separator: "\n")
                    XCTAssertFalse(joined.contains("ALL_PROXY"))
                    XCTAssertFalse(joined.contains("NO_PROXY"))
                }
            }
        }
    }

    /// `diff` untuk domain harus menandai hasilnya, supaya UI bisa membedakan
    /// perubahan domain dari perubahan aplikasi.
    func testDiffMarksDomainChanges() {
        let changes = SplitChangeLog.diff(listedBefore: [], listedAfter: ["bank.com"],
                                          modeBefore: .exclusive, modeAfter: .exclusive,
                                          isDomain: true)
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first?.bundlePath, "bank.com")
        XCTAssertEqual(changes.first?.action, .disable)
        XCTAssertTrue(changes.first?.isDomain == true)
    }

    /// Dan defaultnya tetap `false`, supaya 17 pemanggil lama tidak ikut
    /// berubah makna.
    func testAppDiffIsNotMarkedAsDomain() {
        let changes = SplitChangeLog.diff(listedBefore: [], listedAfter: ["/a.app"],
                                          modeBefore: .exclusive, modeAfter: .exclusive)
        XCTAssertFalse(changes.first?.isDomain == true)
    }

    /// Entri lama yang sudah tersimpan tidak punya key `isDomain`. Membaca
    /// lewat `Row` harus tetap dibaca sebagai entri app, bukan gagal.
    func testLegacyEntryWithoutDomainFlagStillDecodes() throws {
        let json = """
        [{"id":"\(UUID().uuidString)","at":\(Date().timeIntervalSince1970),
          "appName":"Safari","bundlePath":"/Applications/Safari.app",
          "mode":"exclusive","action":"disable"}]
        """
        let entries = SplitChangeLog.decode(Data(json.utf8))
        XCTAssertEqual(entries.count, 1)
        XCTAssertFalse(entries[0].isDomain, "entri tanpa key harus berarti app")
    }
}
