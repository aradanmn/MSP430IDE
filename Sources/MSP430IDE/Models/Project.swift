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
    /// Parent-path suffix shown next to each URL's basename for disambiguation.
    /// Empty string (or missing key) means no suffix is needed — basename is unique.
    var disambiguators: [URL: String] = [:]

    /// For each URL whose basename collides with another in `urls`, returns the shortest
    /// parent-dir path (relative to `root`) that uniquely identifies it. Prefixed with
    /// "…/" if it's a strict suffix of the full relative path. URLs with unique basenames
    /// are not included.
    static func computeDisambiguators(for urls: [URL], relativeTo root: URL) -> [URL: String] {
        var result: [URL: String] = [:]
        let rootPrefix = root.path + "/"
        let groups = Dictionary(grouping: urls, by: { $0.lastPathComponent })

        for (_, group) in groups where group.count > 1 {
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
