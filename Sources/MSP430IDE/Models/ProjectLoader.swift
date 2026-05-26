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

        if FileManager.default.fileExists(atPath: tomlURL.path) {
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
            "build/**", ".git/**", ".msp430ide/**", ".build/**", "**/.DS_Store"
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
        if configs["Debug"] == nil {
            configs["Debug"] = BuildFlags(cflags: ["-O0"], defines: ["DEBUG=1"])
        }
        if configs["Release"] == nil {
            configs["Release"] = BuildFlags(cflags: ["-Os"], defines: ["NDEBUG=1"])
        }

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
        scanSources(into: &model)
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

        for case let fileURL as URL in enumerator {
            let canonicalPath = (fileURL.path as NSString).resolvingSymlinksInPath
            let resolved = URL(fileURLWithPath: canonicalPath)
            let path = resolved.path
            let rel: String
            if path.hasPrefix(rootPrefix) {
                rel = String(path.dropFirst(rootPrefix.count))
            } else {
                rel = resolved.lastPathComponent
            }
            if excludes.contains(where: { $0.matches(rel) }) { continue }

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
