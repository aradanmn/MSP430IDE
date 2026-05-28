import Foundation

/// Parses gcc / msp430-elf-as / ld output into structured Diagnostics.
///
/// Supported line shapes:
///   path/to/file.c:23:5: error: 'foo' undeclared
///   path/to/file.c:23:5: warning: unused variable
///   path/to/file.c:23: error: junk at end of line
///   path/to/file.s:14: Error: junk at end of line
///   path/to/file.s: Assembler messages:    (header — ignored)
///   /path/to/lib.a(obj.o): in function 'foo':                (ld — ignored)
///   /path/to/lib.a(obj.o):(.text+0x4): undefined reference   (ld — kept w/o line)
enum DiagnosticParser {
    /// Matches: <path-no-colon>:<line>[:<col>]: <severity>: <message>
    /// Severity is case-insensitive and optional; if missing, we treat the
    /// line as a note unless it contains "error" / "warning" verbatim.
    private static let regex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"^([^:\n]+):(\d+)(?::(\d+))?:\s*(?i)(fatal\s+error|error|warning|note)?:?\s*(.+)$"#,
        options: [.anchorsMatchLines]
    )

    static func parse(output: String, projectRoot: URL?) -> [Diagnostic] {
        guard let regex else { return [] }
        var results: [Diagnostic] = []
        let nsOutput = output as NSString
        let fullRange = NSRange(location: 0, length: nsOutput.length)

        regex.enumerateMatches(in: output, options: [], range: fullRange) { match, _, _ in
            guard let match else { return }
            let line = nsOutput.substring(with: match.range)

            // Skip lines that don't have a parseable severity AND look like
            // generic informational headers ("Assembler messages:", "in function:").
            let pathRange = match.range(at: 1)
            let lineRange = match.range(at: 2)
            let colRange = match.range(at: 3)
            let sevRange = match.range(at: 4)
            let msgRange = match.range(at: 5)

            guard pathRange.location != NSNotFound,
                  lineRange.location != NSNotFound,
                  msgRange.location != NSNotFound else { return }

            let pathStr = nsOutput.substring(with: pathRange).trimmingCharacters(in: .whitespaces)
            guard let lineNum = Int(nsOutput.substring(with: lineRange)) else { return }
            let col = colRange.location != NSNotFound ? Int(nsOutput.substring(with: colRange)) : nil

            let severity: Diagnostic.Severity
            if sevRange.location != NSNotFound {
                let raw = nsOutput.substring(with: sevRange).lowercased()
                if raw.contains("error") { severity = .error }
                else if raw == "warning" { severity = .warning }
                else { severity = .note }
            } else {
                // No explicit severity word — skip purely-informational lines
                // ("in function 'foo':", "Assembler messages:", file lists).
                return
            }

            let message = nsOutput.substring(with: msgRange).trimmingCharacters(in: .whitespaces)
            guard !message.isEmpty else { return }

            let fileURL = resolveFilePath(pathStr, projectRoot: projectRoot)
            results.append(Diagnostic(
                file: fileURL,
                line: lineNum,
                column: col,
                severity: severity,
                message: message,
                rawLine: line
            ))
        }
        return results
    }

    /// Resolves a path string (possibly relative) to a URL. If the path
    /// is absolute we use it; otherwise we try projectRoot/path; finally
    /// we just construct a file URL from the bare path.
    private static func resolveFilePath(_ path: String, projectRoot: URL?) -> URL {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        if let root = projectRoot {
            let joined = root.appendingPathComponent(path)
            if FileManager.default.fileExists(atPath: joined.path) {
                return joined
            }
        }
        return URL(fileURLWithPath: path)
    }
}
