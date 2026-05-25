import Foundation

struct TOMLParser {
    private let chars: [Character]
    private var pos: Int = 0
    private var line: Int = 1
    private var col: Int = 1

    private init(_ text: String) {
        self.chars = Array(text)
    }

    static func parse(_ text: String) throws -> [String: TOMLValue] {
        var p = TOMLParser(text)
        return try p.parseDocument()
    }

    private mutating func parseDocument() throws -> [String: TOMLValue] {
        var root: [String: TOMLValue] = [:]
        var currentPath: [String] = []

        while !isAtEnd {
            skipWhitespace(includingNewlines: true)
            if isAtEnd { break }

            if peek() == "[" {
                advance()
                currentPath = try parseDottedKey()
                guard consumeIf("]") else { throw err("expected ']'") }
                ensureTablePath(currentPath, in: &root)
                consumeRestOfLine()
                continue
            }

            let keyPath = try parseDottedKey()
            skipInline()
            guard consumeIf("=") else { throw err("expected '=' after key") }
            skipInline()
            let value = try parseValue()
            assign(value: value, at: currentPath + keyPath, in: &root)
            consumeRestOfLine()
        }
        return root
    }

    private mutating func parseDottedKey() throws -> [String] {
        var parts: [String] = []
        skipInline()
        parts.append(try parseSingleKey())
        while peek() == "." {
            advance()
            skipInline()
            parts.append(try parseSingleKey())
            skipInline()
        }
        skipInline()
        return parts
    }

    private mutating func parseSingleKey() throws -> String {
        skipInline()
        if peek() == "\"" { return try parseQuotedString() }
        var s = ""
        while let c = peek() {
            if c == "_" || c == "-" || c.isLetter || c.isNumber {
                s.append(c)
                advance()
            } else {
                break
            }
        }
        if s.isEmpty { throw err("expected key") }
        return s
    }

    private mutating func parseValue() throws -> TOMLValue {
        skipInline()
        guard let c = peek() else { throw TOMLError.unexpectedEOF }
        if c == "\"" { return .string(try parseQuotedString()) }
        if c == "[" { return try parseArray() }
        if c == "{" { return try parseInlineTable() }
        if c == "t" || c == "f" { return try parseBool() }
        if c == "-" || c.isNumber { return try parseNumber() }
        throw err("unexpected character '\(c)' in value")
    }

    private mutating func parseQuotedString() throws -> String {
        guard consumeIf("\"") else { throw err("expected '\"'") }
        var s = ""
        while let c = peek() {
            if c == "\"" { advance(); return s }
            if c == "\n" { throw err("newline inside string") }
            if c == "\\" {
                advance()
                guard let esc = peek() else { throw TOMLError.unexpectedEOF }
                switch esc {
                case "\"": s.append("\"")
                case "\\": s.append("\\")
                case "n":  s.append("\n")
                case "t":  s.append("\t")
                case "r":  s.append("\r")
                case "0":  s.append("\0")
                default:   throw err("invalid escape '\\\(esc)'")
                }
                advance()
            } else {
                s.append(c)
                advance()
            }
        }
        throw TOMLError.unexpectedEOF
    }

    private mutating func parseBool() throws -> TOMLValue {
        if startsWith("true") { for _ in 0..<4 { advance() }; return .bool(true) }
        if startsWith("false") { for _ in 0..<5 { advance() }; return .bool(false) }
        throw err("expected bool")
    }

    private mutating func parseNumber() throws -> TOMLValue {
        var s = ""
        if peek() == "-" { s.append("-"); advance() }
        while let c = peek(), c.isNumber || c == "_" {
            if c != "_" { s.append(c) }
            advance()
        }
        guard let n = Int(s) else { throw err("invalid number '\(s)'") }
        return .integer(n)
    }

    private mutating func parseArray() throws -> TOMLValue {
        guard consumeIf("[") else { throw err("expected '['") }
        var items: [TOMLValue] = []
        while !isAtEnd {
            skipWhitespace(includingNewlines: true)
            if peek() == "]" { advance(); return .array(items) }
            items.append(try parseValue())
            skipWhitespace(includingNewlines: true)
            if peek() == "," { advance(); continue }
            if peek() == "]" { advance(); return .array(items) }
            throw err("expected ',' or ']' in array")
        }
        throw TOMLError.unexpectedEOF
    }

    private mutating func parseInlineTable() throws -> TOMLValue {
        guard consumeIf("{") else { throw err("expected '{'") }
        var t: [String: TOMLValue] = [:]
        skipInline()
        if peek() == "}" { advance(); return .table(t) }
        while !isAtEnd {
            skipInline()
            let keyParts = try parseDottedKey()
            guard consumeIf("=") else { throw err("expected '=' in inline table") }
            skipInline()
            let v = try parseValue()
            t = insertRecursive(value: v, path: keyParts, in: t)
            skipInline()
            if peek() == "," { advance(); continue }
            if peek() == "}" { advance(); return .table(t) }
            throw err("expected ',' or '}' in inline table")
        }
        throw TOMLError.unexpectedEOF
    }

    // MARK: - Cursor

    private var isAtEnd: Bool { pos >= chars.count }
    private func peek() -> Character? { isAtEnd ? nil : chars[pos] }

    private mutating func advance() {
        guard !isAtEnd else { return }
        if chars[pos] == "\n" { line += 1; col = 1 } else { col += 1 }
        pos += 1
    }

    private mutating func consumeIf(_ c: Character) -> Bool {
        if peek() == c { advance(); return true }
        return false
    }

    private func startsWith(_ s: String) -> Bool {
        let arr = Array(s)
        if pos + arr.count > chars.count { return false }
        for i in 0..<arr.count {
            if chars[pos + i] != arr[i] { return false }
        }
        return true
    }

    private mutating func skipInline() {
        while let c = peek(), c == " " || c == "\t" { advance() }
    }

    private mutating func skipWhitespace(includingNewlines: Bool) {
        while !isAtEnd {
            let c = chars[pos]
            if c == " " || c == "\t" { advance(); continue }
            if includingNewlines && c == "\n" { advance(); continue }
            if c == "#" {
                while !isAtEnd, chars[pos] != "\n" { advance() }
                continue
            }
            break
        }
    }

    private mutating func consumeRestOfLine() {
        skipInline()
        if peek() == "#" {
            while !isAtEnd, chars[pos] != "\n" { advance() }
        }
        if peek() == "\n" { advance() }
    }

    private func err(_ msg: String) -> TOMLError {
        TOMLError.syntax(line: line, column: col, message: msg)
    }

    // MARK: - Tree assembly

    private func ensureTablePath(_ path: [String], in root: inout [String: TOMLValue]) {
        guard !path.isEmpty else { return }
        root = ensureTableRec(path: path, in: root)
    }

    private func ensureTableRec(path: [String], in dict: [String: TOMLValue]) -> [String: TOMLValue] {
        var d = dict
        let key = path[0]
        if path.count == 1 {
            if case .table = d[key] { /* already a table */ }
            else if d[key] == nil { d[key] = .table([:]) }
            return d
        }
        var inner: [String: TOMLValue] = [:]
        if case .table(let t)? = d[key] { inner = t }
        inner = ensureTableRec(path: Array(path.dropFirst()), in: inner)
        d[key] = .table(inner)
        return d
    }

    private func assign(value: TOMLValue, at path: [String], in root: inout [String: TOMLValue]) {
        root = insertRecursive(value: value, path: path, in: root)
    }

    private func insertRecursive(value: TOMLValue, path: [String], in dict: [String: TOMLValue]) -> [String: TOMLValue] {
        var d = dict
        let key = path[0]
        if path.count == 1 {
            d[key] = value
            return d
        }
        var inner: [String: TOMLValue] = [:]
        if case .table(let t)? = d[key] { inner = t }
        inner = insertRecursive(value: value, path: Array(path.dropFirst()), in: inner)
        d[key] = .table(inner)
        return d
    }
}
