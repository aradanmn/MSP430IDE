import Foundation

enum HighlighterRegistry {
    static func highlighter(for url: URL) -> Highlighter {
        switch url.pathExtension.lowercased() {
        case "c", "h":
            return CRegexHighlighter()
        case "s", "asm":
            return ASMHighlighter()
        default:
            return CRegexHighlighter()
        }
    }
}
