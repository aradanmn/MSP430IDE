import Foundation

/// Thin wrapper around the `git` CLI for the Course Progress panel's
/// "Pull Latest" / "Save & Push" actions. Built on the same `ProcessRunner`
/// every other external-tool invocation in the app uses (see Builder,
/// Flasher) rather than a second subprocess abstraction.
enum GitService {
    static func pull(repoRoot: URL, onOutput: @escaping (String) -> Void = { _ in }) async -> Result<String, Error> {
        await run(["pull"], repoRoot: repoRoot, onOutput: onOutput)
    }

    static func commitAndPush(
        repoRoot: URL,
        paths: [String],
        message: String,
        onOutput: @escaping (String) -> Void = { _ in }
    ) async -> Result<String, Error> {
        let add = await run(["add"] + paths, repoRoot: repoRoot, onOutput: onOutput)
        if case .failure = add { return add }
        let commit = await run(["commit", "-m", message], repoRoot: repoRoot, onOutput: onOutput)
        if case .failure = commit { return commit }
        return await run(["push"], repoRoot: repoRoot, onOutput: onOutput)
    }

    /// Synchronous by design — a single `git status` on one path is fast
    /// enough to call from the main actor at well-defined points (after
    /// loading progress, after a quiz writes it), not on every view redraw.
    static func hasUncommittedChanges(repoRoot: URL, path: String) -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["git", "status", "--porcelain", "--", path]
        proc.currentDirectoryURL = repoRoot
        let outPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = Pipe()
        do {
            try proc.run()
        } catch {
            return false
        }
        proc.waitUntilExit()
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        let out = String(data: data, encoding: .utf8) ?? ""
        return !out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func run(_ args: [String], repoRoot: URL, onOutput: @escaping (String) -> Void) async -> Result<String, Error> {
        var collected = ""
        let exit = await ProcessRunner().run(
            executable: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["git"] + args,
            workingDir: repoRoot,
            environment: nil,
            onLine: { line in
                collected += line
                onOutput(line)
            }
        )
        if exit == 0 { return .success(collected) }
        return .failure(GitError.exitCode(Int(exit), command: args.joined(separator: " "), output: collected))
    }
}

enum GitError: LocalizedError {
    case exitCode(Int, command: String, output: String)

    var errorDescription: String? {
        switch self {
        case .exitCode(let code, let command, let output):
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return "git \(command) exited with status \(code)" + (trimmed.isEmpty ? "" : ": \(trimmed)")
        }
    }
}
