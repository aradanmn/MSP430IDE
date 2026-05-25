import Foundation

struct GlobMatcher {
    let pattern: String
    private let regex: NSRegularExpression?

    init(_ pattern: String) {
        self.pattern = pattern
        var rx = "^"
        var i = pattern.startIndex
        while i < pattern.endIndex {
            let c = pattern[i]
            switch c {
            case "*":
                let next = pattern.index(after: i)
                if next < pattern.endIndex && pattern[next] == "*" {
                    rx += ".*"
                    i = pattern.index(after: next)
                    if i < pattern.endIndex && pattern[i] == "/" {
                        i = pattern.index(after: i)
                    }
                } else {
                    rx += "[^/]*"
                    i = pattern.index(after: i)
                }
            case "?":
                rx += "[^/]"
                i = pattern.index(after: i)
            case ".", "(", ")", "+", "|", "^", "$", "{", "}", "[", "]", "\\":
                rx += "\\" + String(c)
                i = pattern.index(after: i)
            default:
                rx += String(c)
                i = pattern.index(after: i)
            }
        }
        rx += "$"
        self.regex = try? NSRegularExpression(pattern: rx)
    }

    func matches(_ path: String) -> Bool {
        guard let regex else { return false }
        let range = NSRange(path.startIndex..., in: path)
        return regex.firstMatch(in: path, range: range) != nil
    }
}
