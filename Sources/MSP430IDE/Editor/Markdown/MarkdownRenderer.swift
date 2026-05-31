import AppKit
import Foundation

/// Renders Markdown to a styled NSAttributedString using Apple's built-in
/// Markdown parser (no third-party dependencies). Handles the common block
/// and inline constructs: headings, paragraphs, bold/italic/inline-code,
/// links, ordered/unordered lists, fenced code blocks, blockquotes, and
/// thematic breaks.
enum MarkdownRenderer {
    static func render(_ markdown: String) -> NSAttributedString {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .full
        options.failurePolicy = .returnPartiallyParsedIfPossible
        options.allowsExtendedAttributes = true

        guard let parsed = try? AttributedString(markdown: markdown, options: options) else {
            return NSAttributedString(string: markdown, attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                .foregroundColor: NSColor.textColor
            ])
        }

        let out = NSMutableAttributedString()

        // Group consecutive runs that belong to the same block.
        var blocks: [[(text: String, inline: InlinePresentationIntent?, link: URL?)]] = []
        var blockIntents: [PresentationIntent?] = []
        var started = false
        var prevIntent: PresentationIntent? = nil

        for run in parsed.runs {
            let text = String(parsed[run.range].characters)
            let intent = run.presentationIntent
            let piece = (text: text, inline: run.inlinePresentationIntent, link: run.link)
            if started, prevIntent == intent, !blocks.isEmpty {
                blocks[blocks.count - 1].append(piece)
            } else {
                blocks.append([piece])
                blockIntents.append(intent)
                prevIntent = intent
                started = true
            }
        }

        for (i, block) in blocks.enumerated() {
            appendBlock(block, intent: blockIntents[i], into: out)
        }

        // Trim trailing newlines.
        while out.string.hasSuffix("\n") {
            out.deleteCharacters(in: NSRange(location: out.length - 1, length: 1))
        }
        return out
    }

    // MARK: - Block rendering

    private static func appendBlock(
        _ runs: [(text: String, inline: InlinePresentationIntent?, link: URL?)],
        intent: PresentationIntent?,
        into out: NSMutableAttributedString
    ) {
        let kinds = intent?.components.map(\.kind) ?? []

        if kinds.contains(where: { if case .thematicBreak = $0 { return true } else { return false } }) {
            let para = NSMutableParagraphStyle()
            para.paragraphSpacingBefore = 8
            para.paragraphSpacing = 8
            out.append(NSAttributedString(string: "\u{00A0}\n", attributes: [
                .font: NSFont.systemFont(ofSize: 6),
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                .strikethroughColor: NSColor.separatorColor,
                .paragraphStyle: para
            ]))
            return
        }

        let isCodeBlock = kinds.contains { if case .codeBlock = $0 { return true } else { return false } }
        let isBlockQuote = kinds.contains { if case .blockQuote = $0 { return true } else { return false } }
        var headerLevel: Int? = nil
        var listMarker: String? = nil
        for k in kinds {
            if case .header(let level) = k { headerLevel = level }
            if case .listItem(let ordinal) = k {
                let ordered = kinds.contains { if case .orderedList = $0 { return true } else { return false } }
                listMarker = ordered ? "\(ordinal).\t" : "•\t"
            }
        }

        let para = NSMutableParagraphStyle()
        let baseSize: CGFloat = 14
        var blockFont = NSFont.systemFont(ofSize: baseSize)
        var blockColor = NSColor.textColor

        if let level = headerLevel {
            let sizes: [CGFloat] = [28, 23, 19, 16, 15, 14]
            let size = sizes[min(max(level, 1), 6) - 1]
            blockFont = NSFont.systemFont(ofSize: size, weight: level <= 2 ? .bold : .semibold)
            para.paragraphSpacingBefore = 14
            para.paragraphSpacing = 6
        } else if isCodeBlock {
            blockFont = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
            blockColor = NSColor.textColor
            para.firstLineHeadIndent = 12
            para.headIndent = 12
            para.paragraphSpacingBefore = 6
            para.paragraphSpacing = 6
        } else if isBlockQuote {
            blockColor = NSColor.secondaryLabelColor
            para.firstLineHeadIndent = 16
            para.headIndent = 16
            para.paragraphSpacing = 8
        } else if listMarker != nil {
            para.headIndent = 22
            para.firstLineHeadIndent = 8
            para.paragraphSpacing = 4
            para.tabStops = [NSTextTab(textAlignment: .left, location: 22)]
        } else {
            para.paragraphSpacing = 10
            para.lineSpacing = 2
        }

        if let marker = listMarker {
            out.append(NSAttributedString(string: marker, attributes: [
                .font: blockFont,
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: para
            ]))
        }

        for piece in runs {
            let text = piece.text
            if text.isEmpty { continue }
            var attrs: [NSAttributedString.Key: Any] = [
                .paragraphStyle: para,
                .foregroundColor: blockColor
            ]
            var font = blockFont
            let inline = piece.inline ?? []
            if inline.contains(.code) || isCodeBlock {
                font = NSFont.monospacedSystemFont(ofSize: isCodeBlock ? 12.5 : baseSize - 1, weight: .regular)
                if !isCodeBlock {
                    attrs[.backgroundColor] = NSColor.quaternaryLabelColor.withAlphaComponent(0.4)
                }
            }
            if inline.contains(.stronglyEmphasized) { font = applyTrait(.boldFontMask, to: font) }
            if inline.contains(.emphasized) { font = applyTrait(.italicFontMask, to: font) }
            if inline.contains(.strikethrough) { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            attrs[.font] = font
            if let link = piece.link {
                attrs[.link] = link
                attrs[.foregroundColor] = NSColor.linkColor
                attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            out.append(NSAttributedString(string: text, attributes: attrs))
        }

        // Block separator.
        out.append(NSAttributedString(string: "\n", attributes: [.font: blockFont, .paragraphStyle: para]))
    }

    private static func applyTrait(_ trait: NSFontTraitMask, to font: NSFont) -> NSFont {
        NSFontManager.shared.convert(font, toHaveTrait: trait)
    }
}
