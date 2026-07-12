import Foundation

/// Uniform interface for all build backends. Adding a new build system (e.g.
/// CMake, Ninja) requires only a new conforming type and one case in
/// `ProjectModel.buildSystem(toolchain:configName:)` — AppState is unchanged.
protocol BuildSystem {
    /// Compile and link. Returns the ELF path on success (nil for external builds
    /// that don't expose their artifact path to the IDE).
    func build(onOutput: @escaping (String) -> Void) async -> Result<URL?, Error>

    /// Flash the device.
    func flash(onOutput: @escaping (String) -> Void) async -> Result<Void, Error>

    /// Remove build artifacts.
    func clean(onOutput: @escaping (String) -> Void) async
}

// MARK: - Native

struct NativeBuildSystem: BuildSystem {
    let toolchain: Toolchain
    let project: ProjectModel
    let configName: String

    func build(onOutput: @escaping (String) -> Void) async -> Result<URL?, Error> {
        let result = await Builder(toolchain: toolchain, project: project, configName: configName)
            .build(onOutput: onOutput)
        return result.map { Optional($0) }
    }

    func flash(onOutput: @escaping (String) -> Void) async -> Result<Void, Error> {
        guard toolchain.mspdebugPath != nil else {
            return .failure(FlashError.missingMspdebug)
        }
        let elf = project.buildDir.appendingPathComponent("\(project.name).elf")
        guard FileManager.default.fileExists(atPath: elf.path) else {
            return .failure(BuildSystemError.noArtifact(elf))
        }
        onOutput("\n→ Flashing \(project.name) via mspdebug \(project.flash.driver)\n")
        return await Flasher(toolchain: toolchain, project: project).flash(elf: elf, onOutput: onOutput)
    }

    func clean(onOutput: @escaping (String) -> Void) async {
        try? FileManager.default.removeItem(at: project.buildDir)
        onOutput("Cleaned \(project.buildDir.lastPathComponent)/\n")
    }
}

// MARK: - External

struct ExternalBuildSystem: BuildSystem {
    let project: ProjectModel

    func build(onOutput: @escaping (String) -> Void) async -> Result<URL?, Error> {
        let r = await ExternalBuilder(project: project, command: project.external.build)
            .run(label: "build", onOutput: onOutput)
        return r.map { nil }
    }

    func flash(onOutput: @escaping (String) -> Void) async -> Result<Void, Error> {
        await ExternalBuilder(project: project, command: project.external.flash)
            .run(label: "flash", onOutput: onOutput)
    }

    func clean(onOutput: @escaping (String) -> Void) async {
        _ = await ExternalBuilder(project: project, command: project.external.clean)
            .run(label: "clean", onOutput: onOutput)
    }
}

// MARK: - Errors

enum BuildSystemError: LocalizedError {
    case noArtifact(URL)

    var errorDescription: String? {
        switch self {
        case .noArtifact(let url): return "No build output at \(url.path). Build first."
        }
    }
}
