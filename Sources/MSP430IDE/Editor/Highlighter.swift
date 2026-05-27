import AppKit

/// A pluggable syntax highlighter. Implementations apply colors and font
/// attributes to an NSTextStorage in-place.
protocol Highlighter {
    func highlight(storage: NSTextStorage)
}

/// Adapter so the existing static CHighlighter conforms to the protocol
/// without disturbing its current call sites.
struct CRegexHighlighter: Highlighter {
    func highlight(storage: NSTextStorage) {
        CHighlighter.highlight(storage: storage)
    }
}
