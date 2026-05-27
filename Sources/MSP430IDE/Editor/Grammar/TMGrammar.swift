import Foundation

/// A TextMate-format syntax grammar, decoded from a `.tmLanguage.json` file.
///
/// We support a usable subset of the TextMate language grammar spec
/// (https://macromates.com/manual/en/language_grammars):
///   - `name`, `scopeName`, `fileTypes` for identification
///   - `patterns` and `repository`
///   - Per-pattern: `match` + `name` + `captures`, OR
///                  `begin` + `end` + `name` + (begin|end)Captures + patterns + contentName, OR
///                  `include` ("#name" → repository.name, "$self" → grammar root)
///
/// Not implemented: `while` patterns, cross-grammar includes
/// ("source.foo#bar"), injection grammars, back-references in end patterns.
struct TMGrammar: Codable {
    let name: String?
    let scopeName: String?
    let fileTypes: [String]?
    let firstLineMatch: String?
    let patterns: [TMPattern]?
    let repository: [String: TMPattern]?
}

struct TMPattern: Codable {
    let name: String?
    let contentName: String?
    let match: String?
    let begin: String?
    let end: String?
    let whilePattern: String?
    let captures: [String: TMCapture]?
    let beginCaptures: [String: TMCapture]?
    let endCaptures: [String: TMCapture]?
    let patterns: [TMPattern]?
    let include: String?
    let disabled: Int?

    enum CodingKeys: String, CodingKey {
        case name, contentName
        case match, begin, end
        case whilePattern = "while"
        case captures, beginCaptures, endCaptures
        case patterns, include, disabled
    }
}

struct TMCapture: Codable {
    let name: String?
    let patterns: [TMPattern]?
}

/// A scoped token produced by the engine. Range is in UTF-16 units
/// (NSString-style) so it applies directly to NSTextStorage.
struct TMToken: Equatable {
    let range: NSRange
    let scopes: [String]

    var primaryScope: String { scopes.last ?? "" }
}
