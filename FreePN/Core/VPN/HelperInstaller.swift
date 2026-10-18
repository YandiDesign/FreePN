import Foundation

/// Pemasang helper root SATU-KLIK (tanpa Terminal): user tinggal isi password
/// di dialog bawaan macOS (`osascript ... with administrator privileges`).
///
/// Cara kerja: app menulis skrip install lengkap ( paths sudah sh-quote ) ke
/// /tmp, lalu memintanya dijalankan sebagai root lewat SATU prompt password.
/// Sumber binary diambil dari DALAM bundle app (Resources/FreePNHelper +
/// Resources/sing-box) sehingga tidak tergantung folder build.
/// Gagal/cancel → error jelas (bukan macet); sukses → Health hijau.
public enum HelperInstaller {
    public static let label = "com.freepn.helper"
    public static let machService = "com.freepn.helper.xpc"
    public static let destDir = "/Library/PrivilegedHelperTools"
    public static let daemonPlist = "/Library/LaunchDaemons/com.freepn.helper.plist"
    public static let stagingPath = "/tmp/freepn-install-helper.sh"

    public enum InstallError: LocalizedError {
        case missingBundleFiles(String)
        case userCancelled
        case failed(String)
        public var errorDescription: String? {
            switch self {
            case .missingBundleFiles(let s): return "Missing bundle files: \(s)"
            case .userCancelled: return L10n.string("install_helper_cancelled")
            case .failed(let s): return s
            }
        }
    }

    /// Lokasi binary di dalam bundle (di-embed via "Embed Helper Binary").
    public static var bundledHelperURL: URL? {
        Bundle.main.url(forResource: "FreePNHelper", withExtension: nil)
    }
    public static var bundledCoreURL: URL? {
        Bundle.main.url(forResource: "sing-box", withExtension: nil)
    }

    /// Quote path ala shell: 'a'"'"'b'.
    public static func shQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Skrip root lengkap sebagai string (pure — bisa di-unit-test).
    public static func installScript(helperSrc: String, coreSrc: String) -> String {
        let h = shQuote(helperSrc), c = shQuote(coreSrc)
        return """
        #!/bin/sh
        # FreePN helper installer (dijalankan sebagai root via dialog password macOS).
        set -e
        LABEL="\(label)"
        DEST="\(destDir)"
        PLIST="\(daemonPlist)"
        mkdir -p "$DEST"
        cp -f \(h) "$DEST/$LABEL"
        cp -f \(c) "$DEST/sing-box"
        chmod 755 "$DEST/$LABEL" "$DEST/sing-box"
        chown root:wheel "$DEST/$LABEL" "$DEST/sing-box"
        cat > "$PLIST" <<'PLIST_EOF'
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        \t<key>Label</key>
        \t<string>\(label)</string>
        \t<key>ProgramArguments</key>
        \t<array>
        \t\t<string>\(destDir)/\(label)</string>
        \t</array>
        \t<key>MachServices</key>
        \t<dict>
        \t\t<key>\(machService)</key>
        \t\t<true/>
        \t</dict>
        \t<key>RunAtLoad</key>
        \t<true/>
        \t<key>KeepAlive</key>
        \t<false/>
        \t<key>StandardOutPath</key>
        \t<string>/tmp/freepn-helper.out.log</string>
        \t<key>StandardErrorPath</key>
        \t<string>/tmp/freepn-helper.err.log</string>
        </dict>
        </plist>
        PLIST_EOF
        chmod 644 "$PLIST"
        chown root:wheel "$PLIST"
        # Corey sendiri saja (dicocokkan lewat config-nya). 'pkill -x sing-box'
        # ikut membunuh sing-box milik tool VPN lain milik user (ClashX,
        # Surge, mihomo, …).
        pkill -f 'freepn/config.json' 2>/dev/null || true
        launchctl bootout system/"$LABEL" 2>/dev/null || true
        launchctl bootstrap system "$PLIST"
        sleep 1
        launchctl print system/"$LABEL" 2>&1 | grep -E "state|program" | head -n 4
        """
    }

    /// Tulis staging script, minta password via dialog macOS, jalankan sebagai root.
    public static func install() async throws -> String {
        guard let h = bundledHelperURL?.path, FileManager.default.isExecutableFile(atPath: h),
              let c = bundledCoreURL?.path, FileManager.default.isExecutableFile(atPath: c) else {
            throw InstallError.missingBundleFiles("FreePNHelper/sing-box")
        }
        try installScript(helperSrc: h, coreSrc: c)
            .write(toFile: stagingPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stagingPath)
        return try await runPrivileged(command: "sh \(shQuote(stagingPath))")
    }

    /// Satu-satunya titik yang menyentuh osascript (mudah di-mock/diuji logikanya).
    static func runPrivileged(command: String) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            // Path staging tanpa spasi; command sudah sh-quote di dalamnya.
            p.arguments = ["-e", "do shell script \"\(command)\" with administrator privileges"]
            let outPipe = Pipe(), errPipe = Pipe()
            p.standardOutput = outPipe; p.standardError = errPipe
            do { try p.run() } catch {
                cont.resume(throwing: InstallError.failed(error.localizedDescription)); return
            }
            DispatchQueue.global().async {
                p.waitUntilExit()
                let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                Task { @MainActor in
                    if p.terminationStatus == 0 {
                        cont.resume(returning: out.trimmingCharacters(in: .whitespacesAndNewlines))
                    } else if err.contains("-128") || err.localizedCaseInsensitiveContains("cancel") {
                        cont.resume(throwing: InstallError.userCancelled)
                    } else {
                        let msg = [err, out].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }.joined(separator: "\n")
                        cont.resume(throwing: InstallError.failed(msg.isEmpty ? "osascript exit \(p.terminationStatus)" : msg))
                    }
                }
            }
        }
    }
}
