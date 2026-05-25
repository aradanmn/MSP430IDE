import Foundation

struct Builder {
    let toolchain: Toolchain
    let project: ProjectModel
    let configName: String

    func build(onOutput: @escaping (String) -> Void) async -> Result<URL, Error> {
        guard let gcc = effectiveGCC() else { return .failure(BuildError.missingCompiler) }
        guard !project.sourceFiles.isEmpty || !project.assemblyFiles.isEmpty else {
            return .failure(BuildError.noSources)
        }
        do {
            try FileManager.default.createDirectory(at: project.buildDir, withIntermediateDirectories: true)
        } catch {
            return .failure(error)
        }

        let effective = project.effectiveFlags(for: configName)
        let supportPath = effectiveSupportPath()
        let elfURL = project.buildDir.appendingPathComponent("\(project.name).elf")

        let mcuFlag = "-mmcu=\(project.mcu)"
        let defineFlags = effective.defines.map { "-D\($0)" }
        var includeFlags: [String] = []
        if let sp = supportPath { includeFlags.append("-I\(sp.path)") }
        for d in effective.includeDirs {
            let url = URL(fileURLWithPath: d, relativeTo: project.rootURL)
            includeFlags.append("-I\(url.path)")
        }

        let runner = ProcessRunner()
        var objectFiles: [URL] = []

        for src in project.sourceFiles {
            let obj = project.buildDir.appendingPathComponent(src.lastPathComponent + ".o")
            let args = [mcuFlag] + effective.cflags + defineFlags + includeFlags + ["-c", src.path, "-o", obj.path]
            onOutput("$ \(gcc.lastPathComponent) \(args.joined(separator: " "))\n")
            let exit = await runner.run(executable: gcc, arguments: args, workingDir: project.rootURL, onLine: onOutput)
            if exit != 0 { return .failure(BuildError.compilerExit(Int(exit))) }
            objectFiles.append(obj)
        }

        for src in project.assemblyFiles {
            let obj = project.buildDir.appendingPathComponent(src.lastPathComponent + ".o")
            let cflagsNoOpt = effective.cflags.filter { !$0.hasPrefix("-O") }
            let asmflags = effective.asmflags.isEmpty
                ? ["-x", "assembler-with-cpp", "-nostdlib"]
                : effective.asmflags
            let args = [mcuFlag] + asmflags + cflagsNoOpt + defineFlags + includeFlags + ["-c", src.path, "-o", obj.path]
            onOutput("$ \(gcc.lastPathComponent) \(args.joined(separator: " "))\n")
            let exit = await runner.run(executable: gcc, arguments: args, workingDir: project.rootURL, onLine: onOutput)
            if exit != 0 { return .failure(BuildError.compilerExit(Int(exit))) }
            objectFiles.append(obj)
        }

        var linkArgs = [mcuFlag]
        linkArgs += effective.ldflags
        if let lp = resolveLinkerScript(effective: effective, supportPath: supportPath) {
            linkArgs.append("-T")
            linkArgs.append(lp)
        }
        if let sp = supportPath {
            linkArgs.append("-L\(sp.path)")
        }
        linkArgs += objectFiles.map { $0.path }
        linkArgs += ["-o", elfURL.path]

        onOutput("$ \(gcc.lastPathComponent) \(linkArgs.joined(separator: " "))\n")
        let exit = await runner.run(executable: gcc, arguments: linkArgs, workingDir: project.rootURL, onLine: onOutput)
        if exit != 0 { return .failure(BuildError.linkerExit(Int(exit))) }

        await runSize(gcc: gcc, elfURL: elfURL, onOutput: onOutput)
        return .success(elfURL)
    }

    private func effectiveGCC() -> URL? {
        if let p = project.toolchainOverride.gccPath {
            return URL(fileURLWithPath: p)
        }
        return toolchain.gccPath
    }

    private func effectiveSupportPath() -> URL? {
        if let p = project.toolchainOverride.supportPath {
            return URL(fileURLWithPath: p)
        }
        return toolchain.supportIncludePath
    }

    private func resolveLinkerScript(effective: BuildFlags, supportPath: URL?) -> String? {
        if !effective.linkerScript.isEmpty {
            let lp = effective.linkerScript
            if lp.hasPrefix("/") { return lp }
            return project.rootURL.appendingPathComponent(lp).path
        }
        guard let sp = supportPath else { return nil }
        let url = sp.appendingPathComponent("\(project.mcu).ld")
        return FileManager.default.fileExists(atPath: url.path) ? url.path : nil
    }

    private func runSize(gcc: URL, elfURL: URL, onOutput: @escaping (String) -> Void) async {
        let sizeBin = gcc.deletingLastPathComponent().appendingPathComponent("msp430-elf-size")
        guard FileManager.default.isExecutableFile(atPath: sizeBin.path) else { return }
        _ = await ProcessRunner().run(executable: sizeBin, arguments: [elfURL.path], workingDir: nil, onLine: onOutput)
    }
}

enum BuildError: LocalizedError {
    case missingCompiler
    case noSources
    case compilerExit(Int)
    case linkerExit(Int)

    var errorDescription: String? {
        switch self {
        case .missingCompiler: return "msp430-elf-gcc not found"
        case .noSources: return "No source files in project"
        case .compilerExit(let c): return "Compile failed (exit \(c))"
        case .linkerExit(let c): return "Link failed (exit \(c))"
        }
    }
}
