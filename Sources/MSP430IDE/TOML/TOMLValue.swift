import Foundation

enum TOMLValue: Equatable {
    case string(String)
    case integer(Int)
    case bool(Bool)
    case array([TOMLValue])
    case table([String: TOMLValue])

    var stringValue: String? {
        if case .string(let s) = self { return s } else { return nil }
    }

    var intValue: Int? {
        if case .integer(let i) = self { return i } else { return nil }
    }

    var boolValue: Bool? {
        if case .bool(let b) = self { return b } else { return nil }
    }

    var arrayValue: [TOMLValue]? {
        if case .array(let a) = self { return a } else { return nil }
    }

    var tableValue: [String: TOMLValue]? {
        if case .table(let t) = self { return t } else { return nil }
    }

    var stringArray: [String]? {
        guard case .array(let arr) = self else { return nil }
        return arr.compactMap { $0.stringValue }
    }
}

enum TOMLError: LocalizedError {
    case syntax(line: Int, column: Int, message: String)
    case unexpectedEOF

    var errorDescription: String? {
        switch self {
        case .syntax(let line, let col, let msg):
            return "TOML parse error at \(line):\(col): \(msg)"
        case .unexpectedEOF:
            return "TOML: unexpected end of input"
        }
    }
}
