import Foundation

/// Minimal LSP types — skeleton for E5. Only what we'll need on day one
/// (initialize, didOpen/didChange, publishDiagnostics, completion).

enum LSP {
    struct Position: Codable, Equatable {
        let line: Int
        let character: Int
    }

    struct Range: Codable, Equatable {
        let start: Position
        let end: Position
    }

    struct Diagnostic: Codable, Equatable {
        let range: Range
        let severity: Int?
        let code: CodeValue?
        let source: String?
        let message: String

        enum CodeValue: Codable, Equatable {
            case string(String)
            case integer(Int)

            init(from decoder: Decoder) throws {
                let c = try decoder.singleValueContainer()
                if let s = try? c.decode(String.self) { self = .string(s) }
                else if let i = try? c.decode(Int.self) { self = .integer(i) }
                else { throw DecodingError.typeMismatch(CodeValue.self, .init(codingPath: decoder.codingPath, debugDescription: "expected string or int")) }
            }

            func encode(to encoder: Encoder) throws {
                var c = encoder.singleValueContainer()
                switch self {
                case .string(let s): try c.encode(s)
                case .integer(let i): try c.encode(i)
                }
            }
        }
    }

    struct PublishDiagnosticsParams: Codable {
        let uri: String
        let diagnostics: [Diagnostic]
    }

    struct CompletionItem: Codable, Identifiable {
        let label: String
        let kind: Int?
        let detail: String?
        let documentation: String?
        let insertText: String?
        var id: String { label + "_" + (detail ?? "") }
    }

    struct CompletionList: Codable {
        let isIncomplete: Bool
        let items: [CompletionItem]
    }
}
