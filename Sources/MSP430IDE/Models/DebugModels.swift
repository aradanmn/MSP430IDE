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
