import Foundation

struct Flasher {
    let toolchain: Toolchain
    let project: ProjectModel

    func flash(elf: URL, onOutput: @escaping (String) -> Void) async -> Result<Void, Error> {
        guard let mspdebug = toolchain.mspdebugPath else {
            return .failure(FlashError.missingMspdebug)
        }
        let progCmd = project.flash.verify ? "prog \(elf.path)" : "load \(elf.path)"
        let args = [project.flash.driver, progCmd]
        onOutput("$ \(mspdebug.lastPathComponent) \(args.joined(separator: " "))\n")

        let exit = await ProcessRunner().run(
            executable: mspdebug,
            arguments: args,
            workingDir: elf.deletingLastPathComponent(),
            environment: project.flash.env,
            onLine: onOutput
        )
        if exit == 0 { return .success(()) }
        return .failure(FlashError.mspdebugExit(Int(exit)))
    }
}

enum FlashError: LocalizedError {
    case missingMspdebug
    case mspdebugExit(Int)

    var errorDescription: String? {
        switch self {
        case .missingMspdebug: return "mspdebug not found"
        case .mspdebugExit(let c): return "mspdebug exited with status \(c)"
        }
    }
}
