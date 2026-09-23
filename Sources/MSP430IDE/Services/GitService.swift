import Foundation

/// Thin wrapper around the `git` CLI for the Course Progress panel's
/// "Pull Latest" / "Save & Push" actions. Built on the same `ProcessRunner`
/// every other external-tool invocation in the app uses (see Builder,
/// Flasher) rather than a second subprocess abstraction.
enum GitService {
    static func pull(repoRoot: URL, onOutput: @escaping (String) -> Void = { _ in }) async -> Result<String, Error> {
        // --autostash: the course repo routinely has in-progress exercise
        // edits; a bare `git pull` (especially with pull.rebase configured)
        // refuses to run with unstaged changes anywhere in the tree.
        await run(["pull", "--autostash"], repoRoot: repoRoot, onOutput: onOutput)
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

    /// Async like every other git call here: measured at 15–60 ms per run,
    /// which is a dropped frame or three when called from the main actor.
    static func hasUncommittedChanges(repoRoot: URL, path: String) async -> Bool {
        let result = await run(["status", "--porcelain", "--", path], repoRoot: repoRoot, onOutput: { _ in })
        guard case .success(let out) = result else { return false }
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
