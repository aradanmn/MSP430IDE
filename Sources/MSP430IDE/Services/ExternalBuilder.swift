import Foundation

struct ExternalBuilder {
    let project: ProjectModel
    let command: String

    func run(label: String, env: [String: String] = [:], onOutput: @escaping (String) -> Void) async -> Result<Void, Error> {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(ExternalBuildError.empty(label: label)) }

        var mergedEnv = ProcessInfo.processInfo.environment
        let inheritedPath = mergedEnv["PATH"] ?? ""
        mergedEnv["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:\(inheritedPath)"
        for (k, v) in env { mergedEnv[k] = v }

        onOutput("$ \(trimmed)\n")

        let shell = URL(fileURLWithPath: "/bin/sh")
        let args = ["-c", trimmed]
        let exit = await ProcessRunner().run(
            executable: shell,
            arguments: args,
            workingDir: project.rootURL,
            environment: mergedEnv,
            onLine: onOutput
        )
        if exit == 0 { return .success(()) }
        return .failure(ExternalBuildError.commandFailed(exit: Int(exit), label: label))
    }
}

enum ExternalBuildError: LocalizedError {
    case empty(label: String)
    case commandFailed(exit: Int, label: String)

    var errorDescription: String? {
        switch self {
        case .empty(let l): return "No command configured for \(l)"
        case .commandFailed(let e, let l): return "\(l) failed (exit \(e))"
        }
    }
}
