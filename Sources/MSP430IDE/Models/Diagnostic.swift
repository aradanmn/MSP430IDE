import Foundation

/// A single compiler/assembler/linker diagnostic that maps to a
/// specific point in a source file. Surfaced as a clickable row in the
/// console and as a colored marker in the gutter.
struct Diagnostic: Identifiable, Equatable, Hashable {
    enum Severity: String {
        case error, warning, note
    }

    let id = UUID()
    let file: URL
    let line: Int           // 1-based
    let column: Int?        // 1-based, optional (gas often omits)
    let severity: Severity
    let message: String

    /// The full original line as printed by the compiler — kept so the
    /// console can render it verbatim even if our parse missed something.
    let rawLine: String

    static func == (lhs: Diagnostic, rhs: Diagnostic) -> Bool {
        lhs.file == rhs.file && lhs.line == rhs.line &&
        lhs.column == rhs.column && lhs.severity == rhs.severity &&
        lhs.message == rhs.message
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(file)
        hasher.combine(line)
        hasher.combine(column)
        hasher.combine(severity)
        hasher.combine(message)
    }
}
