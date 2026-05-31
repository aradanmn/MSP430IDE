import Foundation

enum BuildMode: String {
    case native
    case external
}

struct ToolchainOverride: Equatable {
    var gccPath: String?
    var supportPath: String?
}

struct FlashConfig: Equatable {
    var driver: String = "tilib"
    var verify: Bool = true
    var env: [String: String] = [:]
}

struct BuildFlags: Equatable {
    var cflags: [String] = []
    var asmflags: [String] = []
    var ldflags: [String] = []
    var defines: [String] = []
    var includeDirs: [String] = []
    var linkerScript: String = ""

    func merged(with override: BuildFlags) -> BuildFlags {
        var r = self
        r.cflags += override.cflags
        r.asmflags += override.asmflags
        r.ldflags += override.ldflags
        r.defines += override.defines
        r.includeDirs += override.includeDirs
        if !override.linkerScript.isEmpty { r.linkerScript = override.linkerScript }
        return r
    }
}

struct ExternalCommands: Equatable {
    var build: String = "make"
    var flash: String = "make flash"
    var clean: String = "make clean"
    var disasm: String?
}

struct ProjectModel: Equatable {
    var rootURL: URL
    var name: String
    var mcu: String
    var mode: BuildMode

    var sourceIncludes: [String]
    var sourceExcludes: [String]
    var toolchainOverride: ToolchainOverride
    var flash: FlashConfig
    var defaults: BuildFlags
    var configs: [String: BuildFlags]
    var external: ExternalCommands

    var sourceFiles: [URL] = []
    var headerFiles: [URL] = []
    var assemblyFiles: [URL] = []

    /// True when the project was opened from a folder that had no
    /// `msp430.toml` file. In that case we can browse files but won't
    /// attempt to build — the source set is implicit and almost
    /// certainly not what the user intends (e.g. multiple `_start`
    /// labels across unrelated exercises).
    var isImplicit: Bool = false
    /// Parent-path suffix shown next to each URL's basename for disambiguation.
    /// Empty string (or missing key) means no suffix is needed — basename is unique.
    var disambiguators: [URL: String] = [:]

    /// For each URL whose basename collides with another in `urls`, returns a short label
    /// that uniquely identifies it within the group. Strategy: prefer the closest-to-leaf
    /// parent directory whose name appears in no other group member's path. If no single
    /// component is unique, fall back to the shortest leaf-rooted path suffix that's
    /// unique among the group (prefixed with "…/"). URLs with unique basenames are not
    /// included in the result.
    static func computeDisambiguators(for urls: [URL], relativeTo root: URL) -> [URL: String] {
        var result: [URL: String] = [:]
        let rootPrefix = root.path + "/"
        let groups = Dictionary(grouping: urls, by: { $0.lastPathComponent })

        for (_, group) in groups where group.count > 1 {
            // Parent-dir components (leaf-to-root order is dirs.reversed()), relative to root.
            let parts: [(URL, [String])] = group.map { url in
                let path = url.path
                let rel: String
                if path.hasPrefix(rootPrefix) {
                    rel = String(path.dropFirst(rootPrefix.count))
                } else {
                    rel = path.hasPrefix("/") ? String(path.dropFirst()) : path
                }
                let comps = rel.split(separator: "/").map(String.init)
                return (url, Array(comps.dropLast()))
            }

            for (url, dirs) in parts {
                guard !dirs.isEmpty else { continue }

                // Pass 1: find the closest-to-leaf single dir name that appears in no
                // other group member's parent dirs.
                let otherDirs: Set<String> = parts.reduce(into: []) { acc, p in
                    if p.0 != url { acc.formUnion(p.1) }
                }
                if let unique = dirs.reversed().first(where: { !otherDirs.contains($0) }) {
                    result[url] = unique
                    continue
                }

                // Pass 2: shortest unique leaf-rooted path suffix among the group.
                var n = 1
                while n <= dirs.count {
                    let suffix = dirs.suffix(n)
                    let unique = !parts.contains { other in
                        other.0 != url && other.1.suffix(n).elementsEqual(suffix)
                    }
                    if unique { break }
                    n += 1
                }
                let chosen = dirs.suffix(min(n, dirs.count))
                let suffixPath = chosen.joined(separator: "/")
                let needsEllipsis = chosen.count < dirs.count
                result[url] = needsEllipsis ? "…/\(suffixPath)" : suffixPath
            }
        }
        return result
    }

    var configNames: [String] {
        configs.keys.sorted { lhs, rhs in
            let order = ["Debug", "Release"]
            let li = order.firstIndex(of: lhs) ?? Int.max
            let ri = order.firstIndex(of: rhs) ?? Int.max
            if li != ri { return li < ri }
            return lhs < rhs
        }
    }

    var buildDir: URL { rootURL.appendingPathComponent("build") }
    var workspaceDir: URL { rootURL.appendingPathComponent(".msp430ide") }
    var workspaceFile: URL { workspaceDir.appendingPathComponent("workspace.json") }
    var configURL: URL { rootURL.appendingPathComponent("msp430.toml") }

    func effectiveFlags(for configName: String) -> BuildFlags {
        guard let override = configs[configName] else { return defaults }
        return defaults.merged(with: override)
    }
}

final class TextBuffer: ObservableObject, Identifiable {
    let id = UUID()
    let url: URL
    @Published var text: String
    @Published var isDirty: Bool = false

    /// Saved scroll + cursor state so switching tabs restores position.
    var savedScrollOrigin: CGPoint = .zero
    var savedSelection: NSRange = NSRange(location: 0, length: 0)

    init(url: URL, text: String) {
        self.url = url
        self.text = text
    }

    static func load(from url: URL) -> TextBuffer {
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        return TextBuffer(url: url, text: text)
    }

    func markDirty() { isDirty = true }
    func markClean() { isDirty = false }
}
