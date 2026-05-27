import Foundation

/// One node in the project file tree. Folders have `url == nil` and a
/// non-empty `children` array; files have a non-nil `url` and `children == nil`.
struct FileNode: Identifiable, Hashable {
    let id: String
    let name: String
    let url: URL?
    var children: [FileNode]?

    var isFolder: Bool { url == nil }

    /// Build a hierarchical tree from a flat list of file URLs, rooted at `root`.
    /// Folders are sorted before files; both alphabetically (case-insensitive).
    static func buildTree(from files: [URL], root: URL) -> [FileNode] {
        let rootPrefix = root.path + "/"

        final class Builder {
            var children: [String: Builder] = [:]
            var url: URL?
        }

        let trie = Builder()
        for file in files {
            let path = file.path
            let rel: String
            if path.hasPrefix(rootPrefix) {
                rel = String(path.dropFirst(rootPrefix.count))
            } else {
                rel = file.lastPathComponent
            }
            let parts = rel.split(separator: "/").map(String.init)
            guard !parts.isEmpty else { continue }

            var current = trie
            for (i, part) in parts.enumerated() {
                if current.children[part] == nil {
                    current.children[part] = Builder()
                }
                current = current.children[part]!
                if i == parts.count - 1 {
                    current.url = file
                }
            }
        }

        func convert(_ b: Builder, name: String, path: String) -> FileNode {
            let nodePath = path.isEmpty ? name : "\(path)/\(name)"
            if b.children.isEmpty {
                return FileNode(id: nodePath, name: name, url: b.url, children: nil)
            }
            let sortedKeys = b.children.keys.sorted { lhs, rhs in
                let lIsFolder = !b.children[lhs]!.children.isEmpty
                let rIsFolder = !b.children[rhs]!.children.isEmpty
                if lIsFolder != rIsFolder { return lIsFolder }
                return lhs.localizedStandardCompare(rhs) == .orderedAscending
            }
            let kids = sortedKeys.map { convert(b.children[$0]!, name: $0, path: nodePath) }
            return FileNode(id: nodePath, name: name, url: b.url, children: kids)
        }

        let topKeys = trie.children.keys.sorted { lhs, rhs in
            let lIsFolder = !trie.children[lhs]!.children.isEmpty
            let rIsFolder = !trie.children[rhs]!.children.isEmpty
            if lIsFolder != rIsFolder { return lIsFolder }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
        return topKeys.map { convert(trie.children[$0]!, name: $0, path: "") }
    }
}
