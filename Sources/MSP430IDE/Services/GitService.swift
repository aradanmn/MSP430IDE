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

    /// True if `path` either has uncommitted changes OR has local commits
    /// that haven't reached the upstream branch yet. The latter matters
    /// after a commit succeeds but a push fails (network hiccup, diverged
    /// remote) — `hasUncommittedChanges` alone would report "clean" (the
    /// file IS committed) and disable the retry affordance even though the
    /// commit never actually reached the remote.
    static func needsPush(repoRoot: URL, path: String) async -> Bool {
        if await hasUncommittedChanges(repoRoot: repoRoot, path: path) { return true }
        let ahead = await run(["log", "--oneline", "@{u}..HEAD", "--", path], repoRoot: repoRoot, onOutput: { _ in })
        guard case .success(let out) = ahead else { return false }
        return !out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Accumulates a `Process`'s combined stdout/stderr safely. `run()`'s
    /// `onLine` callback is invoked by two independent `Pipe`
    /// `readabilityHandler`s (stdout, stderr) that aren't guaranteed to run
    /// serialized, so a plain `var` mutated from both would be a data race.
    private final class OutputAccumulator: @unchecked Sendable {
        private var text = ""
        private let lock = NSLock()
        func append(_ s: String) {
            lock.lock(); defer { lock.unlock() }
            text += s
        }
        var current: String {
            lock.lock(); defer { lock.unlock() }
            return text
        }
    }

    private static func run(_ args: [String], repoRoot: URL, onOutput: @escaping (String) -> Void) async -> Result<String, Error> {
        let collected = OutputAccumulator()
        let exit = await ProcessRunner().run(
            executable: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["git"] + args,
            workingDir: repoRoot,
            environment: nil,
            onLine: { line in
                collected.append(line)
                onOutput(line)
            }
        )
        let output = collected.current
        if exit == 0 { return .success(output) }
        return .failure(GitError.exitCode(Int(exit), command: args.joined(separator: " "), output: output))
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
