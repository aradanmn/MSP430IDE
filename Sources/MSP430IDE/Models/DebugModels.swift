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

struct RegisterValue: Identifiable, Equatable, Sendable {
    var id: Int { number }
    let number: Int
    let name: String
    let value: UInt32

    var hexString: String { String(format: "0x%04X", value) }

    private static let aliases = ["PC","SP","SR","CG","R4","R5","R6","R7","R8","R9","R10","R11","R12","R13","R14","R15"]

    var displayName: String {
        number < Self.aliases.count ? Self.aliases[number] : name.uppercased()
    }

    /// SR (R2) flag breakdown — nil for all other registers.
    var srFlags: [(name: String, set: Bool)]? {
        guard number == 2 else { return nil }
        return [
            ("C",      value & (1 << 0) != 0),
            ("Z",      value & (1 << 1) != 0),
            ("N",      value & (1 << 2) != 0),
            ("GIE",    value & (1 << 3) != 0),
            ("CPUOFF", value & (1 << 4) != 0),
            ("V",      value & (1 << 8) != 0),
        ]
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
