import Foundation

enum DebugSessionState: Equatable {
    case idle
    case starting
    case running
    case stopped
    case error(String)
}

struct StackFrame: Identifiable, Equatable, Sendable {
    let id: Int          // frame level (0 = innermost)
    let function: String
    let file: URL?       // resolved URL (fullname from GDB)
    let line: Int?
    let address: String

    static func from(miDict: [String: GDBMIValue], level: Int = 0) -> StackFrame {
        let lvl = Int(miDict["level"]?.string ?? "") ?? level
        let func_ = miDict["func"]?.string ?? "??"
        let fullname = miDict["fullname"]?.string
        let fileStr = miDict["file"]?.string
        let line = Int(miDict["line"]?.string ?? "")
        let addr = miDict["addr"]?.string ?? ""
        let fileURL = fullname.map { URL(fileURLWithPath: $0) }
                   ?? fileStr.map { URL(fileURLWithPath: $0) }
        return StackFrame(id: lvl, function: func_, file: fileURL, line: line, address: addr)
    }
}

struct LocalVariable: Identifiable, Equatable, Sendable {
    var id: String { name }
    let name: String
    let value: String
    let type: String?
}

/// One CPU register as reported by GDB for the selected frame.
struct RegisterValue: Identifiable, Equatable, Sendable {
    let id: Int          // GDB register number
    let name: String     // display name, e.g. "PC", "SP", "R12"
    let value: String    // normalised hex, e.g. "0xF800"
    let changed: Bool    // differs from the value at the previous stop

    /// Normalise GDB's hex output ("0xf800", "0x4") to a zero-padded uppercase
    /// form so the column stays aligned. MSP430 registers are 16-bit; CPUX
    /// parts can hold 20-bit addresses, so pad to at least four digits but
    /// never truncate. Non-numeric values (e.g. "<unavailable>") pass through.
    static func normaliseHex(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        let digits = trimmed.lowercased().hasPrefix("0x") ? String(trimmed.dropFirst(2)) : trimmed
        guard !digits.isEmpty, let n = UInt64(digits, radix: 16) else { return trimmed }
        let hex = String(n, radix: 16, uppercase: true)
        return "0x" + String(repeating: "0", count: max(0, 4 - hex.count)) + hex
    }
}

struct StopEvent: Sendable {
    enum Reason: Sendable {
        case breakpointHit(Int)   // GDB breakpoint number
        case endStepping
        case signalReceived(String)
        case exited
        case unknown(String)
    }
    let reason: Reason
    let frame: StackFrame?
}
