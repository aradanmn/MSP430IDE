import Foundation

/// Transport: spawns a JSON-RPC-over-stdio language server and handles
/// `Content-Length` framing. Lives off the main actor; hands decoded
/// messages (as untyped dictionaries) back via `onMessage`, which the
/// owner is responsible for hopping to whatever actor it needs.
final class LSPTransport {
    private let proc = Process()
    private let inPipe = Pipe()
    private let outPipe = Pipe()
    private let errPipe = Pipe()
    private var buffer = Data()
    private let headerTerminator = Data("\r\n\r\n".utf8)

    var onMessage: (([String: Any]) -> Void)?
    var onError: ((String) -> Void)?
    var onExit: (() -> Void)?

    var isRunning: Bool { proc.isRunning }

    func start(executable: URL, arguments: [String], environment: [String: String]?) throws {
        proc.executableURL = executable
        proc.arguments = arguments
        proc.standardInput = inPipe
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        if let environment {
            var merged = ProcessInfo.processInfo.environment
            for (k, v) in environment { merged[k] = v }
            proc.environment = merged
        }
        outPipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            guard !d.isEmpty else { return }
            self?.feed(d)
        }
        errPipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            guard !d.isEmpty, let s = String(data: d, encoding: .utf8) else { return }
            self?.onError?(s)
        }
        proc.terminationHandler = { [weak self] _ in
            self?.onExit?()
        }
        try proc.run()
    }

    func send(_ message: [String: Any]) {
        guard let body = try? JSONSerialization.data(withJSONObject: message) else { return }
        var framed = Data("Content-Length: \(body.count)\r\n\r\n".utf8)
        framed.append(body)
        // Writes are small (single messages); do them synchronously.
        try? inPipe.fileHandleForWriting.write(contentsOf: framed)
    }

    func terminate() {
        outPipe.fileHandleForReading.readabilityHandler = nil
        errPipe.fileHandleForReading.readabilityHandler = nil
        if proc.isRunning { proc.terminate() }
    }

    private func feed(_ d: Data) {
        buffer.append(d)
        while true {
            guard let r = buffer.range(of: headerTerminator) else { return }
            let headerData = buffer[buffer.startIndex..<r.lowerBound]
            let header = String(data: headerData, encoding: .utf8) ?? ""
            var length = 0
            for line in header.split(whereSeparator: { $0 == "\r" || $0 == "\n" }) {
                let lower = line.lowercased()
                if lower.hasPrefix("content-length:") {
                    let num = line[line.index(line.startIndex, offsetBy: "content-length:".count)...]
                    length = Int(num.trimmingCharacters(in: .whitespaces)) ?? 0
                }
            }
            let bodyStart = r.upperBound
            let available = buffer.distance(from: bodyStart, to: buffer.endIndex)
            guard available >= length else { return } // wait for more bytes
            let bodyEnd = buffer.index(bodyStart, offsetBy: length)
            let body = Data(buffer[bodyStart..<bodyEnd])
            buffer = Data(buffer[bodyEnd...]) // rebase indices to 0
            if let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                onMessage?(obj)
            }
        }
    }
}

/// Drives a clangd instance: lifecycle, document sync, diagnostics, and
/// completion. Notifications issued before `initialize` completes are
/// queued and flushed in order once the server is ready.
@MainActor
final class LSPClient: ObservableObject {
    @Published private(set) var isRunning: Bool = false

    /// Called on the main actor whenever the server publishes diagnostics
    /// for a file. An empty array means "no problems" (clears prior ones).
    var onPublishDiagnostics: ((_ file: URL, _ diagnostics: [Diagnostic]) -> Void)?

    let clangdPath: URL

    private let transport = LSPTransport()
    private var pendingResponses: [Int: ([String: Any]) -> Void] = [:]
    private var pendingAfterInit: [() -> Void] = []
    private var versions: [String: Int] = [:]
    private var nextId: Int = 1
    private var ready = false

    init(clangdPath: URL) {
        self.clangdPath = clangdPath
    }

    static func detect() -> URL? {
        let candidates = [
            "/usr/bin/clangd",
            "/opt/homebrew/opt/llvm/bin/clangd",
            "/opt/homebrew/bin/clangd",
            "/usr/local/bin/clangd",
            "/Library/Developer/CommandLineTools/usr/bin/clangd"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    // MARK: - Lifecycle

    func start(rootURI: URL, compileCommandsDir: URL, queryDriver: URL?) async {
        guard !isRunning else { return }
        var args = [
            "--compile-commands-dir=\(compileCommandsDir.path)",
            "--background-index",
            "--header-insertion=never",
            "--limit-results=64",
            "--pch-storage=memory",
            "--log=error"
        ]
        if let queryDriver {
            args.append("--query-driver=\(queryDriver.path)")
        }

        transport.onMessage = { [weak self] obj in
            DispatchQueue.main.async { self?.handle(obj) }
        }
        transport.onError = { _ in /* clangd logs to stderr; ignore */ }
        transport.onExit = { [weak self] in
            DispatchQueue.main.async {
                self?.isRunning = false
                self?.ready = false
            }
        }

        do {
            try transport.start(executable: clangdPath, arguments: args, environment: nil)
        } catch {
            isRunning = false
            return
        }
        isRunning = true

        _ = await sendRequest("initialize", initializeParams(rootURI: rootURI))
        notify("initialized", [:])
        ready = true
        let queued = pendingAfterInit
        pendingAfterInit = []
        for action in queued { action() }
    }

    func stop() async {
        guard isRunning else { return }
        _ = await sendRequest("shutdown", [:])
        notify("exit", [:])
        transport.terminate()
        isRunning = false
        ready = false
        versions = [:]
        pendingResponses = [:]
        pendingAfterInit = []
    }

    // MARK: - Document sync

    func didOpen(url: URL, text: String, languageId: String) {
        runWhenReady { [weak self] in
            guard let self else { return }
            self.versions[url.absoluteString] = 1
            self.notify("textDocument/didOpen", [
                "textDocument": [
                    "uri": url.absoluteString,
                    "languageId": languageId,
                    "version": 1,
                    "text": text
                ]
            ])
        }
    }

    func didChange(url: URL, text: String) {
        runWhenReady { [weak self] in
            guard let self else { return }
            let v = (self.versions[url.absoluteString] ?? 1) + 1
            self.versions[url.absoluteString] = v
            self.notify("textDocument/didChange", [
                "textDocument": ["uri": url.absoluteString, "version": v],
                "contentChanges": [["text": text]]
            ])
        }
    }

    func didSave(url: URL) {
        runWhenReady { [weak self] in
            self?.notify("textDocument/didSave", ["textDocument": ["uri": url.absoluteString]])
        }
    }

    func didClose(url: URL) {
        runWhenReady { [weak self] in
            self?.versions[url.absoluteString] = nil
            self?.notify("textDocument/didClose", ["textDocument": ["uri": url.absoluteString]])
        }
    }

    // MARK: - Completion

    func completion(at position: LSP.Position, in url: URL) async -> LSP.CompletionList? {
        guard ready else { return nil }
        let params: [String: Any] = [
            "textDocument": ["uri": url.absoluteString],
            "position": ["line": position.line, "character": position.character]
        ]
        guard let obj = await sendRequest("textDocument/completion", params),
              let result = obj["result"], !(result is NSNull),
              let data = try? JSONSerialization.data(withJSONObject: result) else {
            return nil
        }
        if let list = try? JSONDecoder().decode(LSP.CompletionList.self, from: data) { return list }
        if let items = try? JSONDecoder().decode([LSP.CompletionItem].self, from: data) {
            return LSP.CompletionList(isIncomplete: false, items: items)
        }
        return nil
    }

    // MARK: - Internals

    private func runWhenReady(_ action: @escaping () -> Void) {
        if ready { action() } else { pendingAfterInit.append(action) }
    }

    private func notify(_ method: String, _ params: Any) {
        transport.send(["jsonrpc": "2.0", "method": method, "params": params])
    }

    @discardableResult
    private func sendRequest(_ method: String, _ params: Any) async -> [String: Any]? {
        let id = nextId
        nextId += 1
        return await withCheckedContinuation { (cont: CheckedContinuation<[String: Any]?, Never>) in
            pendingResponses[id] = { obj in cont.resume(returning: obj) }
            transport.send(["jsonrpc": "2.0", "id": id, "method": method, "params": params])
        }
    }

    private func handle(_ obj: [String: Any]) {
        if let method = obj["method"] as? String {
            // Server→client request: acknowledge with a null result so clangd
            // doesn't stall (covers workspace/configuration, registerCapability…).
            if let id = obj["id"] {
                transport.send(["jsonrpc": "2.0", "id": id, "result": NSNull()])
            }
            if method == "textDocument/publishDiagnostics",
               let params = obj["params"] as? [String: Any],
               let uri = params["uri"] as? String {
                let raw = params["diagnostics"] as? [[String: Any]] ?? []
                let (file, diags) = convert(uri: uri, raw)
                onPublishDiagnostics?(file, diags)
            }
            return
        }
        if let id = obj["id"] as? Int, let handler = pendingResponses.removeValue(forKey: id) {
            handler(obj)
        }
    }

    private func convert(uri: String, _ raw: [[String: Any]]) -> (URL, [Diagnostic]) {
        let fileURL: URL
        if let u = URL(string: uri), u.isFileURL {
            fileURL = URL(fileURLWithPath: u.path)
        } else {
            fileURL = URL(fileURLWithPath: uri.replacingOccurrences(of: "file://", with: ""))
        }
        let diags: [Diagnostic] = raw.map { d in
            let message = d["message"] as? String ?? ""
            let sevNum = d["severity"] as? Int ?? 1
            let severity: Diagnostic.Severity = sevNum == 1 ? .error : (sevNum == 2 ? .warning : .note)
            var line = 1, col = 1
            if let range = d["range"] as? [String: Any],
               let start = range["start"] as? [String: Any] {
                line = (start["line"] as? Int ?? 0) + 1
                col = (start["character"] as? Int ?? 0) + 1
            }
            return Diagnostic(file: fileURL, line: line, column: col,
                              severity: severity, message: message, rawLine: message)
        }
        return (fileURL, diags)
    }

    private func initializeParams(rootURI: URL) -> [String: Any] {
        [
            "processId": Int(ProcessInfo.processInfo.processIdentifier),
            "rootUri": rootURI.absoluteString,
            "capabilities": [
                "textDocument": [
                    "synchronization": ["dynamicRegistration": false, "didSave": true],
                    "publishDiagnostics": ["relatedInformation": false],
                    "completion": [
                        "dynamicRegistration": false,
                        "completionItem": ["snippetSupport": false, "documentationFormat": ["plaintext"]]
                    ]
                ],
                "workspace": ["configuration": true]
            ],
            "initializationOptions": [:]
        ]
    }
}
