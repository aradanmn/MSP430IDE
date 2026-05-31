import Foundation

/// Skeleton — fills in during E5.
/// Translates a ProjectModel + active config into compile_commands.json
/// written to `<project>/.msp430ide/compile_commands.json`, which clangd reads.
enum CompileCommandsGenerator {
    struct Entry: Codable {
        let directory: String
        let file: String
        let arguments: [String]
    }

    static func outputURL(for project: ProjectModel) -> URL {
        project.workspaceDir.appendingPathComponent("compile_commands.json")
    }

    /// Per-project base compile flags, in the form clangd consumes. The
    /// compiler is the real msp430 cross-gcc so clangd's `--query-driver`
    /// can extract the device's system include paths and target.
    private static func baseArguments(for project: ProjectModel, configName: String, toolchain: Toolchain) -> [String] {
        let resolvedConfig = project.configs[configName] != nil ? configName : (project.configNames.first ?? configName)
        let effective = project.effectiveFlags(for: resolvedConfig)
        let gcc = project.toolchainOverride.gccPath ?? toolchain.gccPath?.path ?? "msp430-elf-gcc"

        var args: [String] = [gcc, "-mmcu=\(project.mcu)"]
        args.append(contentsOf: effective.cflags)
        args.append(contentsOf: effective.defines.map { "-D\($0)" })
        let supportPath = project.toolchainOverride.supportPath ?? toolchain.supportIncludePath?.path
        if let supportPath {
            args.append("-I\(supportPath)")
        }
        for d in effective.includeDirs {
            let url = URL(fileURLWithPath: d, relativeTo: project.rootURL)
            args.append("-I\(url.path)")
        }
        return args
    }

    static func generate(project: ProjectModel, configName: String, toolchain: Toolchain) throws {
        let baseArgs = baseArguments(for: project, configName: configName, toolchain: toolchain)
        let entries: [Entry] = project.sourceFiles.map { src in
            Entry(directory: project.rootURL.path, file: src.path, arguments: baseArgs + ["-c", src.path])
        }
        try FileManager.default.createDirectory(at: project.workspaceDir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        try encoder.encode(entries).write(to: outputURL(for: project))
    }

    /// Emits one combined compile_commands.json covering every sub-project,
    /// so a single clangd rooted at the workspace can serve them all.
    static func generateCombined(projects: [ProjectModel], configName: String, toolchain: Toolchain, outputDir: URL) throws {
        var entries: [Entry] = []
        for project in projects {
            let baseArgs = baseArguments(for: project, configName: configName, toolchain: toolchain)
            for src in project.sourceFiles {
                entries.append(Entry(directory: project.rootURL.path, file: src.path, arguments: baseArgs + ["-c", src.path]))
            }
        }
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        try encoder.encode(entries).write(to: outputDir.appendingPathComponent("compile_commands.json"))
    }
}
