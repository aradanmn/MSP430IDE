import Foundation

enum ProjectValidator {
    static func runAndExit(path: String) -> Never {
        let url = URL(fileURLWithPath: path)
        do {
            let proj = try ProjectLoader.load(from: url)
            print("name:  \(proj.name)")
            print("mcu:   \(proj.mcu)")
            print("mode:  \(proj.mode.rawValue)")
            print("root:  \(proj.rootURL.path)")
            print("sources (\(proj.sourceFiles.count)):")
            for s in proj.sourceFiles { print("  C   \(rel(s, root: proj.rootURL))") }
            for s in proj.assemblyFiles { print("  ASM \(rel(s, root: proj.rootURL))") }
            for s in proj.headerFiles { print("  H   \(rel(s, root: proj.rootURL))") }
            print("configs: \(proj.configNames)")
            for name in proj.configNames {
                let e = proj.effectiveFlags(for: name)
                print("  [\(name)] cflags=\(e.cflags) defines=\(e.defines) ldflags=\(e.ldflags)")
                if !e.linkerScript.isEmpty { print("           linker_script=\(e.linkerScript)") }
            }
            print("flash: driver=\(proj.flash.driver) verify=\(proj.flash.verify) env=\(proj.flash.env)")
            if proj.mode == .external {
                print("external: build=\(quote(proj.external.build))")
                print("          flash=\(quote(proj.external.flash))")
                print("          clean=\(quote(proj.external.clean))")
                if let d = proj.external.disasm { print("          disasm=\(quote(d))") }
            }
            if let g = proj.toolchainOverride.gccPath { print("toolchain.gcc override: \(g)") }
            if let s = proj.toolchainOverride.supportPath { print("toolchain.support override: \(s)") }
            exit(0)
        } catch {
            FileHandle.standardError.write("validate failed: \(error.localizedDescription)\n".data(using: .utf8)!)
            exit(1)
        }
    }

    static func buildAndExit(path: String, configName: String) -> Never {
        let url = URL(fileURLWithPath: path)
        let toolchain = Toolchain.detect()
        do {
            let proj = try ProjectLoader.load(from: url)
            print("Building \(proj.name) [\(configName)] (\(proj.mode.rawValue))")
            let group = DispatchGroup()
            group.enter()
            Task.detached {
                defer { group.leave() }
                switch proj.mode {
                case .native:
                    let result = await Builder(toolchain: toolchain, project: proj, configName: configName).build {
                        FileHandle.standardOutput.write($0.data(using: .utf8) ?? Data())
                    }
                    switch result {
                    case .success(let elf): print("OK: \(elf.path)"); exit(0)
                    case .failure(let e): print("FAIL: \(e.localizedDescription)"); exit(2)
                    }
                case .external:
                    let result = await ExternalBuilder(project: proj, command: proj.external.build).run(label: "build") {
                        FileHandle.standardOutput.write($0.data(using: .utf8) ?? Data())
                    }
                    switch result {
                    case .success: print("OK"); exit(0)
                    case .failure(let e): print("FAIL: \(e.localizedDescription)"); exit(2)
                    }
                }
            }
            group.wait()
            exit(0)
        } catch {
            print("Build setup failed: \(error.localizedDescription)")
            exit(1)
        }
    }

    private static func rel(_ url: URL, root: URL) -> String {
        let prefix = root.path + "/"
        if url.path.hasPrefix(prefix) { return String(url.path.dropFirst(prefix.count)) }
        return url.path
    }

    private static func quote(_ s: String) -> String { "\"\(s)\"" }
}
