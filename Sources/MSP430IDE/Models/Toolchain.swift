import Foundation

struct Toolchain: Equatable {
    var gccPath: URL?
    var mspdebugPath: URL?
    var supportIncludePath: URL?

    var isReady: Bool { gccPath != nil && mspdebugPath != nil }

    static func detect() -> Toolchain {
        Toolchain(
            gccPath: findBinary("msp430-elf-gcc"),
            mspdebugPath: findBinary("mspdebug"),
            supportIncludePath: findSupportInclude()
        )
    }

    private static func findBinary(_ name: String) -> URL? {
        let home = NSHomeDirectory()
        let candidates = [
            "\(home)/.local/msp430-gcc/bin/\(name)",
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/opt/ti/msp430-gcc/bin/\(name)",
            "\(home)/ti/msp430-gcc/bin/\(name)"
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return whichBinary(name)
    }

    private static func whichBinary(_ name: String) -> URL? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["which", name]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do { try proc.run() } catch { return nil }
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let raw = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, FileManager.default.isExecutableFile(atPath: trimmed) else { return nil }
        return URL(fileURLWithPath: trimmed)
    }

    private static func findSupportInclude() -> URL? {
        let home = NSHomeDirectory()
        let candidates = [
            "\(home)/.local/msp430-gcc/include",
            "\(home)/ti/msp430-gcc/include",
            "/opt/ti/msp430-gcc/include",
            "\(home)/.local/msp430-gcc-support-files/include"
        ]
        let probe = "msp430g2553.h"
        for path in candidates {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.appendingPathComponent(probe).path) {
                return url
            }
        }
        return nil
    }
}
