import Foundation

/// Skeleton — fills in during E5.
/// Spawns clangd, handles JSON-RPC framing, surfaces diagnostics + completion.
@MainActor
final class LSPClient: ObservableObject {
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var diagnosticsByURI: [String: [LSP.Diagnostic]] = [:]

    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var pendingResponses: [Int: (Data) -> Void] = [:]
    private var nextId: Int = 1

    let clangdPath: URL

    init(clangdPath: URL) {
        self.clangdPath = clangdPath
    }

    static func detect() -> URL? {
        let candidates = [
            "/usr/bin/clangd",
            "/opt/homebrew/opt/llvm/bin/clangd",
            "/opt/homebrew/bin/clangd",
            "/usr/local/bin/clangd"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    func start(rootURI: URL) async throws {
        // TODO E5: spawn clangd, send initialize/initialized, mark isRunning = true
        isRunning = false
    }

    func stop() async {
        // TODO E5: send shutdown + exit, terminate process
        isRunning = false
    }

    func didOpen(url: URL, text: String, languageId: String) async {
        // TODO E5
    }

    func didChange(url: URL, text: String) async {
        // TODO E5
    }

    func didSave(url: URL) async {
        // TODO E5
    }

    func didClose(url: URL) async {
        // TODO E5
    }

    func completion(at position: LSP.Position, in url: URL) async -> LSP.CompletionList? {
        // TODO E5
        return nil
    }
}
