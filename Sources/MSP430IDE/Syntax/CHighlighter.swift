import AppKit

enum CHighlighter {
    static let keywords: Set<String> = [
        "auto", "break", "case", "char", "const", "continue", "default", "do", "double",
        "else", "enum", "extern", "float", "for", "goto", "if", "inline", "int", "long",
        "register", "restrict", "return", "short", "signed", "sizeof", "static", "struct",
        "switch", "typedef", "union", "unsigned", "void", "volatile", "while",
        "_Bool", "_Complex", "_Imaginary",
        "asm", "__asm__", "__attribute__", "__interrupt", "interrupt", "__delay_cycles"
    ]

    private static let baseFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    private static let boldFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold)

    private static let keywordRegex: NSRegularExpression? = {
        let pattern = "\\b(" + keywords.joined(separator: "|") + ")\\b"
        return try? NSRegularExpression(pattern: pattern, options: [])
    }()

    private static let lineCommentRegex = try? NSRegularExpression(pattern: #"//[^\n]*"#, options: [])
    private static let blockCommentRegex = try? NSRegularExpression(pattern: #"/\*[\s\S]*?\*/"#, options: [])
    private static let stringRegex = try? NSRegularExpression(pattern: #""(\\.|[^"\\])*""#, options: [])
    private static let charRegex = try? NSRegularExpression(pattern: #"'(\\.|[^'\\])*'"#, options: [])
    private static let numberRegex = try? NSRegularExpression(pattern: #"\b(0x[0-9A-Fa-f]+|0b[01]+|\d+)([uUlL]+)?\b"#, options: [])
    private static let preprocessorRegex = try? NSRegularExpression(pattern: #"^\s*#\s*\w+"#, options: [.anchorsMatchLines])
    private static let registerRegex = try? NSRegularExpression(pattern: #"\bP[1-9](DIR|OUT|IN|REN|IE|IFG|SEL2?)\b"#, options: [])
    private static let bitRegex = try? NSRegularExpression(pattern: #"\bBIT[0-7]\b"#, options: [])
    private static let wdtRegex = try? NSRegularExpression(pattern: #"\b(WDTCTL|WDTPW|WDTHOLD|TACTL|TACCR0|TACCR1|TACCTL0|TACCTL1|TAR|CCR0|CCR1|CCIE|CCIFG|TASSEL_\d|MC_\d|ID_\d)\b"#, options: [])

    static func highlight(storage: NSTextStorage) {
        let string = storage.string
        let length = (string as NSString).length
        let full = NSRange(location: 0, length: length)

        storage.beginEditing()
        defer { storage.endEditing() }

        storage.setAttributes([
            .font: baseFont,
            .foregroundColor: NSColor.textColor
        ], range: full)

        let kwColor = NSColor.systemPink
        let strColor = NSColor.systemRed
        let numColor = NSColor.systemOrange
        let commentColor = NSColor.systemGreen
        let prepColor = NSColor.systemPurple
        let regColor = NSColor.systemTeal
        let bitColor = NSColor.systemIndigo

        apply(keywordRegex, in: string, range: full, storage: storage, color: kwColor, bold: true)
        apply(registerRegex, in: string, range: full, storage: storage, color: regColor)
        apply(bitRegex, in: string, range: full, storage: storage, color: bitColor)
        apply(wdtRegex, in: string, range: full, storage: storage, color: regColor)
        apply(numberRegex, in: string, range: full, storage: storage, color: numColor)
        apply(preprocessorRegex, in: string, range: full, storage: storage, color: prepColor, bold: true)
        apply(stringRegex, in: string, range: full, storage: storage, color: strColor)
        apply(charRegex, in: string, range: full, storage: storage, color: strColor)
        apply(blockCommentRegex, in: string, range: full, storage: storage, color: commentColor, italic: true)
        apply(lineCommentRegex, in: string, range: full, storage: storage, color: commentColor, italic: true)
    }

    private static func apply(_ regex: NSRegularExpression?, in text: String, range: NSRange, storage: NSTextStorage, color: NSColor, bold: Bool = false, italic: Bool = false) {
        guard let regex = regex else { return }
        regex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            guard let r = match?.range else { return }
            storage.addAttribute(.foregroundColor, value: color, range: r)
            if bold {
                storage.addAttribute(.font, value: boldFont, range: r)
            }
            if italic {
                let italicFont = NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
                storage.addAttribute(.font, value: italicFont, range: r)
            }
        }
    }
}
