import Foundation

enum ProjectLoaderError: LocalizedError {
    case invalidTOML(underlying: Error)

    var errorDescription: String? {
        if case .invalidTOML(let e) = self { return e.localizedDescription }
        return nil
    }
}

enum ProjectLoader {
    static let configFileName = "msp430.toml"
    static let legacyConfigFileName = ".msp430ide.json"

    static func load(from rawURL: URL) throws -> ProjectModel {
        let canonical = (rawURL.path as NSString).resolvingSymlinksInPath
        let url = URL(fileURLWithPath: canonical)
        let tomlURL = url.appendingPathComponent(configFileName)
        var raw: [String: TOMLValue] = [:]

        let hasToml = FileManager.default.fileExists(atPath: tomlURL.path)
        if hasToml {
            let text = try String(contentsOf: tomlURL, encoding: .utf8)
            do {
                raw = try TOMLParser.parse(text)
            } catch {
                throw ProjectLoaderError.invalidTOML(underlying: error)
            }
        } else if let legacy = tryReadLegacyJSON(at: url) {
            raw = legacy
        }

        let projectTable = raw["project"]?.tableValue ?? [:]
        let name = projectTable["name"]?.stringValue ?? url.lastPathComponent
        let mcu = projectTable["mcu"]?.stringValue ?? "msp430g2553"
        let mode = BuildMode(rawValue: projectTable["mode"]?.stringValue ?? "native") ?? .native

        let sourcesTable = raw["sources"]?.tableValue ?? [:]
        let sourceIncludes = sourcesTable["include"]?.stringArray ?? []
        let sourceExcludes = sourcesTable["exclude"]?.stringArray ?? [
            "build/**", "**/build/**",
            ".git/**", "**/.git/**",
            ".msp430ide/**", "**/.msp430ide/**",
            ".build/**", "**/.build/**",
            ".swiftpm/**", "**/.swiftpm/**",
            "**/node_modules/**",
            "**/bindings/**",
            "**/Pods/**",
            "**/DerivedData/**",
            "**/.DS_Store"
        ]

        let tcTable = raw["toolchain"]?.tableValue ?? [:]
        let toolchainOverride = ToolchainOverride(
            gccPath: nonEmpty(tcTable["gcc"]?.stringValue).map(expandHome),
            supportPath: nonEmpty(tcTable["support_path"]?.stringValue).map(expandHome)
        )

        let flashTable = raw["flash"]?.tableValue ?? [:]
        var flashEnv: [String: String] = [:]
        if let envTable = flashTable["env"]?.tableValue {
            for (k, v) in envTable {
                if let s = v.stringValue { flashEnv[k] = expandHome(s) }
            }
        }
        let flash = FlashConfig(
            driver: flashTable["driver"]?.stringValue ?? "tilib",
            verify: flashTable["verify"]?.boolValue ?? true,
            env: flashEnv
        )

        let defaults = parseFlags(raw["defaults"]?.tableValue ?? [:])

        var configs: [String: BuildFlags] = [:]
        if let cfgs = raw["configs"]?.tableValue {
            for (cname, val) in cfgs {
                if let t = val.tableValue {
                    configs[cname] = parseFlags(t)
                }
            }
        }
        // Debug/Release are auto-injected only for C projects (their flags
        // are C-compiler oriented). Decided after scanSources, below.
        let hasExplicitConfigs = !configs.isEmpty

        let extTable = raw["external"]?.tableValue ?? [:]
        let external = ExternalCommands(
            build: extTable["build"]?.stringValue ?? "make",
            flash: extTable["flash"]?.stringValue ?? "make flash",
            clean: extTable["clean"]?.stringValue ?? "make clean",
            disasm: extTable["disasm"]?.stringValue
        )

        var model = ProjectModel(
            rootURL: url,
            name: name,
            mcu: mcu,
            mode: mode,
            sourceIncludes: sourceIncludes,
            sourceExcludes: sourceExcludes,
            toolchainOverride: toolchainOverride,
            flash: flash,
            defaults: defaults,
            configs: configs,
            external: external
        )
        // hasToml is captured from the outer scope; if false, the project
        // is "implicit" — we'll allow browsing but block building.
        model.isImplicit = !hasToml && (try? Data(contentsOf: url.appendingPathComponent(legacyConfigFileName))) == nil
        scanSources(into: &model)

        // Inject default configs only if the project didn't define its own.
        // C projects get the conventional Debug/Release pair; assembly-only
        // projects get a single neutral "Default" (Debug/Release optimization
        // levels don't apply to the assembler).
        if !hasExplicitConfigs {
            if model.sourceFiles.isEmpty {
                model.configs["Default"] = BuildFlags()
            } else {
                model.configs["Debug"]   = BuildFlags(cflags: ["-O0"], defines: ["DEBUG=1"])
                model.configs["Release"] = BuildFlags(cflags: ["-Os"], defines: ["NDEBUG=1"])
            }
        }
        return model
    }

    private static func parseFlags(_ t: [String: TOMLValue]) -> BuildFlags {
        BuildFlags(
            cflags: t["cflags"]?.stringArray ?? [],
            asmflags: t["asmflags"]?.stringArray ?? [],
            ldflags: t["ldflags"]?.stringArray ?? [],
            defines: t["defines"]?.stringArray ?? [],
            includeDirs: (t["include_dirs"]?.stringArray ?? []).map(expandHome),
            linkerScript: t["linker_script"]?.stringValue ?? ""
        )
    }

    /// Maximum number of source files a single project will index. Beyond
    /// this, we stop scanning and log a warning — almost certainly the
    /// user opened too broad a folder.
    static let scanFileCap = 500

    /// Discovers every subdirectory under `root` that contains its own
    /// `msp430.toml`. Each is an independent sub-project. The root itself
    /// is NOT included in the result; callers handle the root specially.
    static func discoverSubprojects(at root: URL) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: root,
                                             includingPropertiesForKeys: [.isDirectoryKey],
                                             options: [.skipsHiddenFiles]) else { return [] }
        var result: [URL] = []
        let rootPath = root.path
        for case let url as URL in enumerator {
            let canonical = URL(fileURLWithPath: (url.path as NSString).resolvingSymlinksInPath)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: canonical.path, isDirectory: &isDir), isDir.boolValue else { continue }
            if canonical.path == rootPath { continue }
            let tomlURL = canonical.appendingPathComponent(configFileName)
            if fm.fileExists(atPath: tomlURL.path) {
                result.append(canonical)
                enumerator.skipDescendants()
            }
        }
        return result
    }

    /// Broad workspace-level file scan for the file tree. Unlike
    /// `scanSources(into:)`, this does NOT stop at nested-project
    /// boundaries — the whole tree should be browseable. It still
    /// honors the default excludes (build/, .git/, etc.).
    static func scanForDisplay(at root: URL) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: root,
                                             includingPropertiesForKeys: [.isDirectoryKey],
                                             options: [.skipsHiddenFiles]) else { return [] }
        let excludes = defaultDisplayExcludes.map { GlobMatcher($0) }
        let rootPrefix = root.path + "/"
        var result: [URL] = []
        for case let fileURL as URL in enumerator {
            let canonical = URL(fileURLWithPath: (fileURL.path as NSString).resolvingSymlinksInPath)
            let path = canonical.path
            let rel: String
            if path.hasPrefix(rootPrefix) {
                rel = String(path.dropFirst(rootPrefix.count))
            } else {
                rel = canonical.lastPathComponent
            }
            if excludes.contains(where: { $0.matches(rel) }) {
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                    enumerator.skipDescendants()
                }
                continue
            }
            let ext = canonical.pathExtension.lowercased()
            if displayExtensions.contains(ext) {
                result.append(canonical)
                if result.count >= scanFileCap {
                    FileHandle.standardError.write(
                        "ProjectLoader.scanForDisplay: stopping at \(scanFileCap) files in \(root.lastPathComponent).\n"
                            .data(using: .utf8) ?? Data()
                    )
                    break
                }
            }
        }
        return result
    }

    /// File extensions surfaced in the tree (and thus openable). Source +
    /// common text/markdown/config files.
    static let displayExtensions: Set<String> = [
        "c", "h", "s", "asm",
        "txt", "text", "md", "markdown", "mdown",
        "toml", "json", "ld"
    ]

    static let defaultDisplayExcludes: [String] = [
        "build/**", "**/build/**",
        ".git/**", "**/.git/**",
        ".msp430ide/**", "**/.msp430ide/**",
        ".build/**", "**/.build/**",
        ".swiftpm/**", "**/.swiftpm/**",
        "**/node_modules/**",
        "**/bindings/**",
        "**/Pods/**",
        "**/DerivedData/**",
        "**/.DS_Store"
    ]

    static func scanSources(into model: inout ProjectModel) {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: model.rootURL,
                                             includingPropertiesForKeys: [.isDirectoryKey],
                                             options: [.skipsHiddenFiles]) else { return }

        let excludes = model.sourceExcludes.map { GlobMatcher($0) }
        var c: [URL] = []
        var s: [URL] = []
        var h: [URL] = []
        let rootPrefix = model.rootURL.path + "/"
        let rootPath = model.rootURL.path

        for case let fileURL as URL in enumerator {
            let canonicalPath = (fileURL.path as NSString).resolvingSymlinksInPath
            let resolved = URL(fileURLWithPath: canonicalPath)
            let path = resolved.path

            // Don't descend into nested projects (subdirs that have their
            // own msp430.toml).  They should be opened independently.
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                if path != rootPath {
                    let nested = resolved.appendingPathComponent(configFileName).path
                    if fm.fileExists(atPath: nested) {
                        enumerator.skipDescendants()
                        continue
                    }
                }
            }

            let rel: String
            if path.hasPrefix(rootPrefix) {
                rel = String(path.dropFirst(rootPrefix.count))
            } else {
                rel = resolved.lastPathComponent
            }
            if excludes.contains(where: { $0.matches(rel) }) {
                if isDir.boolValue { enumerator.skipDescendants() }
                continue
            }

            let ext = resolved.pathExtension.lowercased()
            switch ext {
            case "c":
                c.append(resolved)
            case "s", "asm":
                s.append(resolved)
            case "h":
                h.append(resolved)
            default:
                break
            }

            if c.count + s.count + h.count >= scanFileCap {
                FileHandle.standardError.write(
                    "ProjectLoader: stopping scan at \(scanFileCap) files in \(model.rootURL.lastPathComponent). Probably opened too broad a folder.\n"
                        .data(using: .utf8) ?? Data()
                )
                break
            }
        }

        for inc in model.sourceIncludes {
            let url = URL(fileURLWithPath: expandHome(inc), relativeTo: model.rootURL)
            if FileManager.default.fileExists(atPath: url.path) {
                let ext = url.pathExtension.lowercased()
                switch ext {
                case "c": if !c.contains(url) { c.append(url) }
                case "s", "asm": if !s.contains(url) { s.append(url) }
                case "h": if !h.contains(url) { h.append(url) }
                default: break
                }
            }
        }

        model.sourceFiles = c.sorted { $0.path < $1.path }
        model.assemblyFiles = s.sorted { $0.path < $1.path }
        model.headerFiles = h.sorted { $0.path < $1.path }
        model.disambiguators = ProjectModel.computeDisambiguators(
            for: model.sourceFiles + model.assemblyFiles + model.headerFiles,
            relativeTo: model.rootURL
        )
    }

    private static func tryReadLegacyJSON(at url: URL) -> [String: TOMLValue]? {
        let legacy = url.appendingPathComponent(legacyConfigFileName)
        guard let data = try? Data(contentsOf: legacy),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        var project: [String: TOMLValue] = [:]
        if let mcu = obj["mcu"] as? String { project["mcu"] = .string(mcu) }
        if let driver = obj["mspdebugDriver"] as? String {
            let flash: [String: TOMLValue] = ["driver": .string(driver)]
            return ["project": .table(project), "flash": .table(flash)]
        }
        return ["project": .table(project)]
    }

    private static func nonEmpty(_ s: String?) -> String? {
        guard let s, !s.isEmpty else { return nil }
        return s
    }

    static func expandHome(_ path: String) -> String {
        if path.hasPrefix("~/") {
            return NSHomeDirectory() + String(path.dropFirst())
        }
        if path == "~" {
            return NSHomeDirectory()
        }
        return path
    }
}
