import Foundation

/// Manages the GDB/mspdebug subprocess pair and all GDB/MI interactions.
/// AppState holds one instance and wires the callbacks to update its own
/// @Published properties — views never reference DebugSession directly.
/// Preconditions (project mode, toolchain presence, built ELF) are checked
/// by AppState.startDebugging, which owns user-facing status messages.
@MainActor
final class DebugSession {

    // MARK: - Callback interface (wired by AppState at init time)

    struct Callbacks {
        var onStateChanged:           (DebugSessionState) -> Void  = { _ in }
        var onIsDebuggingChanged:     (Bool) -> Void               = { _ in }
        var onCurrentLocation:        (URL?, Int?) -> Void         = { _, _ in }
        var onStackChanged:           ([StackFrame]) -> Void       = { _ in }
        var onLocalsChanged:          ([LocalVariable]) -> Void    = { _ in }
        var onRegistersChanged:       ([RegisterValue]) -> Void    = { _ in }
        var onPanelTabChanged:        (Int) -> Void                = { _ in }
        var onConsoleOutput:          (String) -> Void             = { _ in }
        var onSelectFile:             (URL) -> Void                = { _ in }
        var onJumpToLine:             (URL, Int) -> Void           = { _, _ in }
        var onStopped:                () -> Void                   = {}
        var onDebugActiveChanged:     (Bool) -> Void               = { _ in }
    }
    var callbacks = Callbacks()

    // MARK: - GDB internals (private)

    private var gdbClient: GDBClient?
    private var mspdebugProcess: Process?
    /// Maps "path:line" keys to GDB breakpoint numbers for the live session.
    private(set) var gdbBreakpointMap: [String: Int] = [:]
    private var cachedRegisterNames: [String]? = nil

    // MARK: - Session lifecycle

    func start(project: ProjectModel, gdbPath: URL, mspdebugPath: URL,
               elf: URL, breakpoints: [URL: Set<Int>]) async {
        callbacks.onStateChanged(.starting)
        callbacks.onIsDebuggingChanged(true)
        callbacks.onDebugActiveChanged(true)
        callbacks.onConsoleOutput("────────────────────────────────────────\n")
        callbacks.onConsoleOutput("→ Starting debug session: \(project.name) (\(project.flash.driver))\n")

        // Start mspdebug GDB stub
        let srv = Process()
        srv.executableURL = mspdebugPath
        srv.arguments = [project.flash.driver, "gdb"]
        srv.currentDirectoryURL = project.rootURL
        if !project.flash.env.isEmpty {
            var env = ProcessInfo.processInfo.environment
            for (k, v) in project.flash.env { env[k] = v }
            srv.environment = env
        }
        let srvOut = Pipe(); let srvErr = Pipe()
        srv.standardOutput = srvOut; srv.standardError = srvErr
        for pipe in [srvOut, srvErr] {
            pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
                let d = h.availableData
                guard !d.isEmpty, let t = String(data: d, encoding: .utf8) else { return }
                Task { @MainActor [weak self] in self?.callbacks.onConsoleOutput(t) }
            }
        }
        do { try srv.run() } catch {
            callbacks.onConsoleOutput("✗ mspdebug failed: \(error.localizedDescription)\n")
            await cleanup(); return
        }
        mspdebugProcess = srv

        // Wait for mspdebug GDB stub to be ready
        try? await Task.sleep(nanoseconds: 1_500_000_000)

        let client = GDBClient()
        gdbClient = client
        await client.setCallbacks(
            onStopped:  { @Sendable [weak self] event in Task { @MainActor [weak self] in self?.handleStopped(event) } },
            onRunning:  { @Sendable [weak self] in       Task { @MainActor [weak self] in self?.handleRunning() } },
            onOutput:   { @Sendable [weak self] text in  Task { @MainActor [weak self] in self?.callbacks.onConsoleOutput(text) } },
            onExited:   { @Sendable [weak self] in       Task { @MainActor [weak self] in await self?.cleanup() } }
        )

        do {
            try await client.start(gdbPath: gdbPath, elfPath: elf, workingDir: project.rootURL)
            callbacks.onConsoleOutput("→ GDB connected\n")
            try await client.send("-target-select remote :2000")
            callbacks.onConsoleOutput("→ Target connected\n")

            // Download the program to flash. A remote MSP430 target already
            // holds the program; we (re)load to guarantee the chip matches the
            // ELF we have symbols for.
            callbacks.onConsoleOutput("→ Loading program into flash…\n")
            _ = try await client.send("-target-download")

            // Push breakpoints to GDB. The UI already caps them at the hardware
            // limit, so failures here are unexpected — log them if they occur.
            gdbBreakpointMap = [:]
            for (url, lines) in breakpoints {
                for line in lines.sorted() {
                    do {
                        let result = try await client.send("-break-insert -f \(url.path):\(line)")
                        if let no = result["bkpt"]?["number"]?.string.flatMap(Int.init) {
                            gdbBreakpointMap["\(url.path):\(line)"] = no
                        }
                    } catch {
                        callbacks.onConsoleOutput("⚠ Breakpoint \(url.lastPathComponent):\(line) not armed: \(error.localizedDescription)\n")
                    }
                }
            }

            // After -target-download the CPU sits halted at the reset vector.
            // Leave it there (no -exec-continue) so the user can inspect or
            // step from the very first instruction without needing a breakpoint.
            callbacks.onStateChanged(.stopped)
            callbacks.onPanelTabChanged(0)
            let frames = await refreshState()
            if let top = frames.first, let url = top.file, let line = top.line {
                callbacks.onSelectFile(url)
                callbacks.onJumpToLine(url, line)
            }
            callbacks.onStopped()
            callbacks.onConsoleOutput("→ Halted at entry — Continue (F5) to run, or Step Instruction (F11) to trace\n")
        } catch {
            callbacks.onConsoleOutput("✗ Debug session failed: \(error.localizedDescription)\n")
            await cleanup()
        }
    }

    func stop() async {
        _ = try? await gdbClient?.send("-gdb-exit")
        await cleanup()
    }

    // MARK: - Execution control

    func resume()          { fire("-exec-continue") }
    func pause()           { fire("-exec-interrupt") }
    func stepIn()          { fire("-exec-step") }
    func stepOver()        { fire("-exec-next") }
    func stepOut()         { fire("-exec-finish") }
    /// Step exactly one machine instruction, following calls into subroutines.
    func stepInstruction() { fire("-exec-stepi") }
    /// Step exactly one machine instruction, stepping over calls (continues until they return).
    func nextInstruction() { fire("-exec-nexti") }

    func selectFrame(_ frame: StackFrame) {
        let client = gdbClient
        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = try? await client?.send("-stack-select-frame \(frame.id)")
            _ = await self.refreshState()
            if let url = frame.file, let line = frame.line {
                self.callbacks.onSelectFile(url)
                self.callbacks.onJumpToLine(url, line)
            }
        }
    }

    // MARK: - Breakpoints

    /// Sync a breakpoint add/remove to the live GDB session (no-op when not active).
    func syncBreakpoint(file: URL, line: Int, added: Bool) {
        let key = "\(file.path):\(line)"
        if added {
            guard let client = gdbClient else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let result = try await client.send("-break-insert -f \(file.path):\(line)")
                    if let no = result["bkpt"]?["number"]?.string.flatMap(Int.init) {
                        self.gdbBreakpointMap[key] = no
                    }
                } catch {
                    self.callbacks.onConsoleOutput("⚠ Breakpoint not set: \(error.localizedDescription)\n")
                }
            }
        } else {
            if let bkptNo = gdbBreakpointMap.removeValue(forKey: key) {
                let client = gdbClient
                Task { _ = try? await client?.send("-break-delete \(bkptNo)") }
            }
        }
    }

    /// True when the breakpoint at file:line was accepted by the hardware
    /// debugger. `isDebugging` is passed in so the gutter shows full dots
    /// when no session is active — "unconfirmed" only matters live.
    func isBreakpointConfirmed(file: URL, line: Int, isDebugging: Bool) -> Bool {
        guard isDebugging else { return true }
        return gdbBreakpointMap["\(file.path):\(line)"] != nil
    }

    // MARK: - Internals

    private func fire(_ command: String) {
        let client = gdbClient
        Task { _ = try? await client?.send(command) }
    }

    private func handleStopped(_ event: StopEvent) {
        callbacks.onStateChanged(.stopped)
        callbacks.onPanelTabChanged(0)   // auto-select Registers tab
        if let frame = event.frame {
            callbacks.onCurrentLocation(frame.file, frame.line)
            if let url = frame.file, let line = frame.line {
                callbacks.onSelectFile(url)
                callbacks.onJumpToLine(url, line)
            }
        }
        Task { @MainActor [weak self] in _ = await self?.refreshState() }
        callbacks.onStopped()
    }

    private func handleRunning() {
        callbacks.onStateChanged(.running)
    }

    /// Fetch stack, locals, and registers concurrently; returns the frames so
    /// start() can jump the editor to the entry PC.
    @discardableResult
    private func refreshState() async -> [StackFrame] {
        guard let client = gdbClient else { return [] }

        // Fetch register names once per session, then values on every stop
        if cachedRegisterNames == nil,
           let namesResult = try? await client.send("-data-list-register-names"),
           let namesArray = namesResult["register-names"]?.array {
            cachedRegisterNames = namesArray.compactMap { $0.string }
        }
        let names = cachedRegisterNames

        async let stackFetch  = client.send("-stack-list-frames")
        async let localsFetch = client.send("-stack-list-locals --simple-values")
        async let regValFetch = client.send("-data-list-register-values x")

        let stackResult  = try? await stackFetch
        let localsResult = try? await localsFetch
        let valResult    = try? await regValFetch

        var frames: [StackFrame] = []
        if let stackList = stackResult?["stack"]?.array {
            frames = stackList.compactMap { item -> StackFrame? in
                guard let frameDict = item.dict?["frame"]?.dict else { return nil }
                return StackFrame.from(miDict: frameDict)
            }
            callbacks.onStackChanged(frames)
            if let top = frames.first {
                callbacks.onCurrentLocation(top.file, top.line)
            }
        }

        if let localsList = localsResult?["locals"]?.array {
            let locals = localsList.compactMap { item -> LocalVariable? in
                let d: [String: GDBMIValue]?
                if case .tuple(let dict) = item { d = dict } else { d = item.dict }
                guard let d, let name = d["name"]?.string else { return nil }
                return LocalVariable(name: name, value: d["value"]?.string ?? "", type: d["type"]?.string)
            }
            callbacks.onLocalsChanged(locals)
        }

        if let names, let valArray = valResult?["register-values"]?.array {
            let regs = valArray.compactMap { item -> RegisterValue? in
                let d: [String: GDBMIValue]?
                if case .tuple(let dict) = item { d = dict } else { d = item.dict }
                guard let d,
                      let numStr = d["number"]?.string, let num = Int(numStr),
                      let valStr = d["value"]?.string,
                      num < names.count, !names[num].isEmpty else { return nil }
                let stripped = valStr.hasPrefix("0x") ? String(valStr.dropFirst(2)) : valStr
                let v = UInt32(stripped, radix: valStr.hasPrefix("0x") ? 16 : 10) ?? 0
                return RegisterValue(number: num, name: names[num], value: v)
            }.sorted { $0.number < $1.number }
            callbacks.onRegistersChanged(regs)
        }

        return frames
    }

    private func cleanup() async {
        await gdbClient?.stop()
        gdbClient = nil
        mspdebugProcess?.terminate()
        mspdebugProcess = nil
        gdbBreakpointMap = [:]
        cachedRegisterNames = nil
        callbacks.onStateChanged(.idle)
        callbacks.onIsDebuggingChanged(false)
        callbacks.onDebugActiveChanged(false)
        callbacks.onCurrentLocation(nil, nil)
        callbacks.onStackChanged([])
        callbacks.onLocalsChanged([])
        callbacks.onRegistersChanged([])
        callbacks.onPanelTabChanged(0)
    }
}
