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

    static func generate(project: ProjectModel, configName: String, toolchain: Toolchain) throws {
        let effective = project.effectiveFlags(for: configName)
        let gcc = project.toolchainOverride.gccPath ?? toolchain.gccPath?.path ?? "msp430-elf-gcc"

        var baseArgs: [String] = [gcc, "-mmcu=\(project.mcu)"]
        baseArgs.append(contentsOf: effective.cflags)
        baseArgs.append(contentsOf: effective.defines.map { "-D\($0)" })
        if let sp = toolchain.supportIncludePath {
            baseArgs.append("-I\(sp.path)")
        }
        for d in effective.includeDirs {
            let url = URL(fileURLWithPath: d, relativeTo: project.rootURL)
            baseArgs.append("-I\(url.path)")
        }

        let entries: [Entry] = project.sourceFiles.map { src in
            Entry(
                directory: project.rootURL.path,
                file: src.path,
                arguments: baseArgs + ["-c", src.path]
            )
        }

        let out = outputURL(for: project)
        try FileManager.default.createDirectory(at: project.workspaceDir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        let data = try encoder.encode(entries)
        try data.write(to: out)
    }
}
