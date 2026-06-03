import Foundation

// GDBMIValue represents a parsed MI value
indirect enum GDBMIValue: Sendable {
    case string(String)
    case tuple([String: GDBMIValue])
    case list([GDBMIValue])
}

extension GDBMIValue {
    subscript(_ key: String) -> GDBMIValue? {
        if case .tuple(let d) = self { return d[key] }
        return nil
    }
    var string: String? {
        if case .string(let s) = self { return s }; return nil
    }
    var array: [GDBMIValue]? {
        if case .list(let a) = self { return a }; return nil
    }
    var dict: [String: GDBMIValue]? {
        if case .tuple(let d) = self { return d }; return nil
    }
}

enum GDBMIRecord: Sendable {
    case result(token: Int?, cls: String, results: [String: GDBMIValue])
    case execAsync(token: Int?, cls: String, results: [String: GDBMIValue])
    case notifyAsync(token: Int?, cls: String, results: [String: GDBMIValue])
    case console(String)
    case target(String)
    case log(String)
    case prompt
    case unknown
}

enum GDBMIParser {
    static func parse(line: String) -> GDBMIRecord {
        var p = MIParser(Array(line))
        return p.parseRecord()
    }
}

private struct MIParser {
    var chars: [Character]
    var i: Int = 0

    init(_ chars: [Character]) { self.chars = chars }

    var current: Character? { i < chars.count ? chars[i] : nil }
    mutating func advance() { if i < chars.count { i += 1 } }
    mutating func skip(_ c: Character) { if current == c { advance() } }

    mutating func consumeDigits() -> Int? {
        var s = ""
        while let c = current, c.isNumber { s.append(c); advance() }
        return s.isEmpty ? nil : Int(s)
    }

    mutating func consumeIdent() -> String {
        var s = ""
        while let c = current, c.isLetter || c.isNumber || c == "-" || c == "_" {
            s.append(c); advance()
        }
        return s
    }

    mutating func parseCString() -> String {
        skip("\"")
        var s = ""
        while let c = current, c != "\"" {
            if c == "\\" {
                advance()
                guard let esc = current else { break }
                advance()
                switch esc {
                case "n": s.append("\n")
                case "t": s.append("\t")
                case "r": s.append("\r")
                case "\\": s.append("\\")
                case "\"": s.append("\"")
                case "0": s.append("\0")
                default: s.append("\\"); s.append(esc)
                }
            } else {
                s.append(c); advance()
            }
        }
        skip("\"")
        return s
    }

    mutating func parseValue() -> GDBMIValue {
        switch current {
        case "\"": return .string(parseCString())
        case "{": return .tuple(parseTuple())
        case "[": return .list(parseList())
        default: return .string("")
        }
    }

    mutating func parseTuple() -> [String: GDBMIValue] {
        skip("{")
        var d: [String: GDBMIValue] = [:]
        while let c = current, c != "}" {
            let key = consumeIdent()
            guard !key.isEmpty else { advance(); continue }
            skip("=")
            d[key] = parseValue()
            skip(",")
        }
        skip("}")
        return d
    }

    mutating func parseList() -> [GDBMIValue] {
        skip("[")
        var items: [GDBMIValue] = []
        while let c = current, c != "]" {
            if isAtResult() {
                let key = consumeIdent()
                skip("=")
                items.append(.tuple([key: parseValue()]))
            } else {
                items.append(parseValue())
            }
            skip(",")
        }
        skip("]")
        return items
    }

    func isAtResult() -> Bool {
        var j = i
        var has = false
        while j < chars.count {
            let c = chars[j]
            if c.isLetter || c.isNumber || c == "-" || c == "_" { has = true; j += 1 }
            else { break }
        }
        return has && j < chars.count && chars[j] == "="
    }

    mutating func parseResults() -> [String: GDBMIValue] {
        var r: [String: GDBMIValue] = [:]
        while current == "," {
            advance()
            let k = consumeIdent()
            guard !k.isEmpty else { continue }
            skip("=")
            r[k] = parseValue()
        }
        return r
    }

    mutating func parseRecord() -> GDBMIRecord {
        let trimmed = String(chars).trimmingCharacters(in: .whitespaces)
        if trimmed == "(gdb)" || trimmed.hasSuffix("(gdb)") { return .prompt }
        if trimmed.isEmpty { return .unknown }

        let token = consumeDigits()
        guard let c = current else { return .unknown }
        switch c {
        case "^":
            advance(); let cls = consumeIdent(); return .result(token: token, cls: cls, results: parseResults())
        case "*":
            advance(); let cls = consumeIdent(); return .execAsync(token: token, cls: cls, results: parseResults())
        case "=":
            advance(); let cls = consumeIdent(); return .notifyAsync(token: token, cls: cls, results: parseResults())
        case "~":
            advance(); return .console(parseCString())
        case "@":
            advance(); return .target(parseCString())
        case "&":
            advance(); return .log(parseCString())
        default:
            return .unknown
        }
    }
}
