import Foundation

enum GDBError: Error, LocalizedError {
    case launchFailed(String)
    case commandFailed(String)
    case notConnected

    var errorDescription: String? {
        switch self {
        case .launchFailed(let m): return "GDB launch failed: \(m)"
        case .commandFailed(let m): return "GDB error: \(m)"
        case .notConnected: return "No active GDB session"
        }
    }
}

actor GDBClient {
    private var process: Process?
    private var inputHandle: FileHandle?
    private var lineBuffer = ""
    private var nextToken = 1
    private var pending: [Int: CheckedContinuation<[String: GDBMIValue], any Error>] = [:]
    private var readyContinuation: CheckedContinuation<Void, any Error>?

    var onStopped: (@Sendable (StopEvent) -> Void)?
    var onRunning: (@Sendable () -> Void)?
    var onOutput: (@Sendable (String) -> Void)?
    var onExited: (@Sendable () -> Void)?

    func setCallbacks(
        onStopped: @Sendable @escaping (StopEvent) -> Void,
        onRunning: @Sendable @escaping () -> Void,
        onOutput: @Sendable @escaping (String) -> Void,
        onExited: @Sendable @escaping () -> Void
    ) {
        self.onStopped = onStopped
        self.onRunning = onRunning
        self.onOutput = onOutput
        self.onExited = onExited
    }

    // Start GDB with MI mode; waits for first "(gdb)" prompt then sends -gdb-set mi-async on
    func start(gdbPath: URL, elfPath: URL, workingDir: URL?) async throws {
        let proc = Process()
        proc.executableURL = gdbPath
        proc.arguments = ["--interpreter=mi", "--quiet", elfPath.path]
        if let wd = workingDir { proc.currentDirectoryURL = wd }

        let inPipe  = Pipe()
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardInput  = inPipe
        proc.standardOutput = outPipe
        proc.standardError  = errPipe

        inputHandle = inPipe.fileHandleForWriting

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { [weak self] in await self?.receiveText(text) }
        }
        errPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { [weak self] in await self?.receiveText(text) }
        }
        proc.terminationHandler = { [weak self] _ in
            Task { [weak self] in await self?.handleExit() }
        }

        do { try proc.run() } catch {
            throw GDBError.launchFailed(error.localizedDescription)
        }
        process = proc

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, any Error>) in
            readyContinuation = cont
        }
        _ = try? await send("-gdb-set mi-async on")
    }

    @discardableResult
    func send(_ command: String) async throws -> [String: GDBMIValue] {
        guard inputHandle != nil else { throw GDBError.notConnected }
        let token = nextToken; nextToken += 1
        let line = Data("\(token)\(command)\n".utf8)
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[String: GDBMIValue], any Error>) in
            pending[token] = cont
            do { try inputHandle?.write(contentsOf: line) } catch {
                pending.removeValue(forKey: token)
                cont.resume(throwing: error)
            }
        }
    }

    func stop() {
        for (_, c) in pending { c.resume(throwing: GDBError.notConnected) }
        pending = [:]
        readyContinuation?.resume(throwing: GDBError.notConnected)
        readyContinuation = nil
        process?.terminate()
        process = nil
        inputHandle = nil
    }

    // MARK: - Private

    private func receiveText(_ text: String) {
        lineBuffer += text
        while let nl = lineBuffer.firstIndex(of: "\n") {
            let line = String(lineBuffer[lineBuffer.startIndex..<nl])
            lineBuffer = String(lineBuffer[lineBuffer.index(after: nl)...])
            handleLine(line)
        }
    }

    private func handleLine(_ raw: String) {
        let line = raw.trimmingCharacters(in: .init(charactersIn: "\r"))
        guard !line.isEmpty else { return }
        let record = GDBMIParser.parse(line: line)
        switch record {
        case .prompt:
            if let cont = readyContinuation { readyContinuation = nil; cont.resume(returning: ()) }

        case .result(let token, let cls, let results):
            if let tok = token, let cont = pending.removeValue(forKey: tok) {
                if cls == "error" {
                    let msg = results["msg"]?.string ?? results["message"]?.string ?? "unknown"
                    cont.resume(throwing: GDBError.commandFailed(msg))
                } else {
                    cont.resume(returning: results)
                }
            }

        case .execAsync(_, let cls, let results):
            if cls == "stopped" { onStopped?(parseStopEvent(results)) }
            else if cls == "running" { onRunning?() }

        case .console(let text):
            if !text.isEmpty { onOutput?(text) }

        default: break
        }
    }

    private func handleExit() {
        for (_, c) in pending { c.resume(throwing: GDBError.notConnected) }
        pending = [:]
        readyContinuation?.resume(throwing: GDBError.notConnected)
        readyContinuation = nil
        process = nil
        inputHandle = nil
        onExited?()
    }

    private func parseStopEvent(_ r: [String: GDBMIValue]) -> StopEvent {
        let reasonStr = r["reason"]?.string ?? ""
        let frame: StackFrame? = r["frame"]?.dict.map { StackFrame.from(miDict: $0) }
        let reason: StopEvent.Reason
        switch reasonStr {
        case "breakpoint-hit":
            reason = .breakpointHit(Int(r["bkptno"]?.string ?? "") ?? 0)
        case "end-stepping-range", "function-finished":
            reason = .endStepping
        case "signal-received":
            reason = .signalReceived(r["signal-name"]?.string ?? "unknown")
        case "exited", "exited-normally", "exited-signalled":
            reason = .exited
        default:
            reason = .unknown(reasonStr)
        }
        return StopEvent(reason: reason, frame: frame)
    }
}
