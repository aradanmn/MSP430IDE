import SwiftUI
import AppKit
import Combine

extension Notification.Name {
    static let msp430EditorJumpToLine = Notification.Name("MSP430IDE.editorJumpToLine")
}

@MainActor
final class AppState: ObservableObject {
    /// Active project for build/flash. In workspace mode this is the
    /// sub-project enclosing the selected file; in single-project mode
    /// it's just the root project. Nil if no sub-project encloses the
    /// active file.
    @Published var project: ProjectModel?

    /// The folder the user opened. May be a single-project root or a
    /// workspace containing many sub-projects.
    @Published var workspaceRoot: URL?

    /// Sub-project root URLs → loaded ProjectModel. Includes the
    /// workspaceRoot itself if it has its own msp430.toml.
    @Published var subprojects: [URL: ProjectModel] = [:]

    /// Every source/header file under workspaceRoot. Drives the file tree.
    /// Independent of which sub-project is active; doesn't get filtered
    /// by per-project sources.exclude.
    @Published var displayFiles: [URL] = []

    @Published var workspace: WorkspaceState = WorkspaceState()
    @Published var activeConfig: String = "Debug"
    @Published var selectedFile: URL?
    @Published var buffers: [URL: TextBuffer] = [:]
    @Published var consoleOutput: String = ""
    @Published var isBuilding: Bool = false
    @Published var isFlashing: Bool = false
    @Published var statusMessage: String = "Ready"
    @Published var toolchain: Toolchain

    /// Per-file diagnostics from the most recent build. Drives gutter
    /// markers and clickable console lines.
    @Published var diagnostics: [URL: [Diagnostic]] = [:]
    /// Flat list in the order they appeared in the build output, for the
    /// console to render as clickable rows.
    @Published var diagnosticsInOrder: [Diagnostic] = []

    /// Fired after a build's diagnostics have been parsed. Subscribers
    /// (e.g. PanelManager) can react by surfacing the Problems tab.
    var onDiagnosticsUpdated: (([Diagnostic]) -> Void)?

    let editor = EditorService()
    private var editorSubscription: AnyCancellable?

    /// clangd integration (nil if clangd isn't installed). Provides live
    /// diagnostics and completion independent of the build.
    /// Watches the workspace tree so external add/remove/rename of files
    /// is reflected in the file tree without reopening the project.
    private var fileWatcher: FileSystemWatcher?
    private var refreshTask: Task<Void, Never>?

    let lsp: LSPClient?
    private var lspRootURL: URL?
    private var lspOpenDocs: Set<URL> = []
    private var bufferObservers: [URL: AnyCancellable] = [:]

    /// Diagnostics from the last build (per file). Kept separate from LSP
    /// diagnostics so neither clobbers the other; `diagnostics` is the
    /// merged, displayed result.
    private var buildDiagnostics: [URL: [Diagnostic]] = [:]
    /// Live diagnostics published by clangd, per file.
    private var lspDiagnostics: [URL: [Diagnostic]] = [:]
    /// True when either input dict has changed since the last merge.
    private var diagnosticsDirty = false

    init() {
        self.toolchain = Toolchain.detect()
        if let clangd = LSPClient.detect() {
            self.lsp = LSPClient(clangdPath: clangd)
        } else {
            self.lsp = nil
        }
        editorSubscription = editor.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.objectWillChange.send()
            }
        }
        lsp?.onPublishDiagnostics = { [weak self] file, diags in
            guard let self else { return }
            self.lspDiagnostics[file] = diags
            self.diagnosticsDirty = true
            self.refreshDisplayedDiagnostics()
        }
    }

    // MARK: - LSP (clangd)

    private static let cFamilyExtensions: Set<String> = ["c", "h", "cpp", "cc", "cxx", "hpp", "hh", "hxx"]

    private func isCFamily(_ url: URL) -> Bool {
        Self.cFamilyExtensions.contains(url.pathExtension.lowercased())
    }

    private func languageId(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "cpp", "cc", "cxx", "hpp", "hh", "hxx": return "cpp"
        default: return "c"
        }
    }

    /// (Re)generate compile_commands.json for the workspace and ensure a
    /// clangd instance is running, rooted at the workspace.
    private func ensureLSPStarted() {
        guard let lsp, let root = workspaceRoot, !subprojects.isEmpty else { return }
        guard toolchain.gccPath != nil else { return } // query-driver needs the cross-gcc
        let outDir = root.appendingPathComponent(".msp430ide")
        try? CompileCommandsGenerator.generateCombined(
            projects: Array(subprojects.values),
            configName: activeConfig,
            toolchain: toolchain,
            outputDir: outDir
        )
        if lspRootURL == root && lsp.isRunning { return }
        lspRootURL = root
        let driver = toolchain.gccPath
        Task { await lsp.start(rootURI: root, compileCommandsDir: outDir, queryDriver: driver) }
    }

    /// Creates a buffer and starts observing it so edits stream to clangd
    /// (debounced). Use this everywhere instead of `TextBuffer.load`.
    private func makeBuffer(for url: URL) -> TextBuffer {
        let buf = TextBuffer.load(from: url)
        bufferObservers[url] = buf.$text
            .dropFirst()
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] text in self?.lspDidChange(url: url, text: text) }
        return buf
    }

    private func lspDidOpen(_ url: URL) {
        guard let lsp, isCFamily(url), let buf = buffers[url], !lspOpenDocs.contains(url) else { return }
        lspOpenDocs.insert(url)
        lsp.didOpen(url: url, text: buf.text, languageId: languageId(for: url))
    }

    private func lspDidChange(url: URL, text: String) {
        guard let lsp, lspOpenDocs.contains(url) else { return }
        lsp.didChange(url: url, text: text)
    }

    private func lspDidClose(_ url: URL) {
        bufferObservers[url] = nil
        guard let lsp, lspOpenDocs.remove(url) != nil else { return }
        lspDiagnostics[url] = nil
        lsp.didClose(url: url)
        refreshDisplayedDiagnostics()
    }

    // MARK: - Editor pop-out windows

    private var editorWindows: [URL: EditorWindowController] = [:]
    private var editorTearPreview: NSWindow?
    private var lastEditorSize: [URL: NSSize] = [:]
    private static let defaultEditorWindowSize = NSSize(width: 700, height: 460)

    /// The main app window, used to detect when a floating editor is dragged
    /// back onto it (to dock). Set by MainView.
    weak var mainWindow: NSWindow?
    private var draggedEditorURL: URL?
    private var suppressEditorMove = false
    private var editorMouseUpMonitors: [Any] = []

    func setMainWindow(_ window: NSWindow?) { mainWindow = window }

    private func installEditorDragMonitorsIfNeeded() {
        guard editorMouseUpMonitors.isEmpty else { return }
        let onUp: () -> Void = { [weak self] in Task { @MainActor in self?.handleEditorDragRelease() } }
        if let g = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: { _ in onUp() }) {
            editorMouseUpMonitors.append(g)
        }
        if let l = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp, handler: { ev in onUp(); return ev }) {
            editorMouseUpMonitors.append(l)
        }
    }

    func noteEditorWindowMoved(_ url: URL) {
        guard !suppressEditorMove else { return }
        draggedEditorURL = url
    }

    private func handleEditorDragRelease() {
        guard let url = draggedEditorURL else { return }
        draggedEditorURL = nil
        guard let mw = mainWindow, mw.frame.contains(NSEvent.mouseLocation) else { return }
        // Dropped onto the main window → dock the file back (closing the
        // window re-adds its tab via editorWindowClosed).
        editorWindows[url]?.window.close()
    }

    /// Open `url` in its own editor window (sharing the same TextBuffer, so
    /// it's the same document). Removes it from the main tab bar while
    /// floating; closing the window re-docks it.
    func popOutEditor(_ url: URL, at screenPoint: NSPoint? = nil) {
        guard buffers[url] != nil else { return }
        if let existing = editorWindows[url] {
            existing.window.makeKeyAndOrderFront(nil)
            return
        }
        let content = EditorPaneContent(url: url, buffer: buffers[url]!)
            .environmentObject(self)
        let hosting = NSHostingController(rootView: AnyView(content))
        let window = NSWindow(contentViewController: hosting)
        window.title = url.lastPathComponent
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView]
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.backgroundColor = .textBackgroundColor
        window.setContentSize(lastEditorSize[url] ?? Self.defaultEditorWindowSize)
        suppressEditorMove = true
        if let p = screenPoint {
            window.setFrameTopLeftPoint(NSPoint(x: p.x - 80, y: p.y + 12))
        } else {
            window.center()
        }
        suppressEditorMove = false
        installEditorDragMonitorsIfNeeded()
        let controller = EditorWindowController(url: url, window: window, appState: self)
        editorWindows[url] = controller

        // Remove from the main tab bar (still open, just elsewhere).
        editor.detach(url)
        selectedFile = editor.activeTab
        if let active = selectedFile { project = enclosingProject(for: active) ?? project }

        window.makeKeyAndOrderFront(nil)
    }

    func editorWindowClosed(_ url: URL) {
        if let size = editorWindows[url]?.window.contentView?.frame.size {
            lastEditorSize[url] = size
        }
        editorWindows[url] = nil
        // Re-dock the tab (the buffer was never released).
        guard buffers[url] != nil else { return }
        editor.open(url)
        selectedFile = url
        if let proj = enclosingProject(for: url) { project = proj }
        persistWorkspaceState()
    }

    // Tear preview for editor tabs (mirrors the panel tear preview).
    func beginEditorTearPreview(_ url: URL) {
        guard editorTearPreview == nil, let buffer = buffers[url] else { return }
        let hosting = NSHostingController(rootView: EditorTearPreview(filename: url.lastPathComponent, buffer: buffer))
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.borderless]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.setContentSize(lastEditorSize[url] ?? Self.defaultEditorWindowSize)
        window.alphaValue = 0.82
        editorTearPreview = window
        window.orderFront(nil)
        moveEditorTearPreview(to: NSEvent.mouseLocation)
    }

    func moveEditorTearPreview(to screenPoint: NSPoint) {
        editorTearPreview?.setFrameTopLeftPoint(NSPoint(x: screenPoint.x - 40, y: screenPoint.y + 14))
    }

    func endEditorTear(commit: Bool, url: URL, at screenPoint: NSPoint) {
        editorTearPreview?.orderOut(nil)
        editorTearPreview = nil
        if commit { popOutEditor(url, at: screenPoint) }
    }

    // MARK: - File tree watching

    private func startWatching(_ root: URL) {
        fileWatcher?.stop()
        let watcher = FileSystemWatcher(path: root.path) { [weak self] in
            Task { @MainActor [weak self] in self?.scheduleTreeRefresh() }
        }
        watcher.start()
        fileWatcher = watcher
    }

    private func stopWatching() {
        fileWatcher?.stop()
        fileWatcher = nil
        refreshTask?.cancel()
        refreshTask = nil
    }

    /// Debounced — FSEvents can deliver bursts. Uses a Task instead of
    /// DispatchWorkItem so cancellation is MainActor-safe on macOS 26+.
    private func scheduleTreeRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            self?.refreshFileTree()
        }
    }

    /// Re-scan the tree and reload sub-project source lists to reflect
    /// files added/removed outside the IDE.
    func refreshFileTree() {
        guard let root = workspaceRoot else { return }
        let scanned = ProjectLoader.scanForDisplay(at: root)
        if scanned != displayFiles { displayFiles = scanned }

        // Pick up sub-projects newly created (or deleted) on disk.
        var discovered: Set<URL> = []
        if FileManager.default.fileExists(atPath: root.appendingPathComponent(ProjectLoader.configFileName).path) {
            discovered.insert(root)
        }
        for sub in ProjectLoader.discoverSubprojects(at: root) { discovered.insert(sub) }
        for removed in subprojects.keys where !discovered.contains(removed) {
            subprojects[removed] = nil
        }
        for sub in discovered {
            if let updated = try? ProjectLoader.load(from: sub) { subprojects[sub] = updated }
        }
        if let active = selectedFile { project = enclosingProject(for: active) ?? project }

        // Keep clangd's compilation database current.
        ensureLSPStarted()
    }

    // MARK: - Project lifecycle

    func promptOpenProject() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        panel.message = "Choose an MSP430 project folder, or a parent folder containing several"
        if panel.runModal() == .OK, let url = panel.url {
            openProject(at: url)
        }
    }

    func createBlinkProject() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "BlinkG2553"
        panel.message = "Choose a location for the new project folder"
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try BlinkTemplate.create(at: url)
                openProject(at: url)
                appendConsole("✓ Created C project at \(url.path)\n")
            } catch {
                appendConsole("Failed to create project: \(error.localizedDescription)\n")
            }
        }
    }

    /// Prompts for the project language, then scaffolds the matching blink
    /// template.
    func createProject() {
        let alert = NSAlert()
        alert.messageText = "New MSP430 Project"
        alert.informativeText = "Choose the language for your new blink project."
        alert.addButton(withTitle: "C")          // default (Return)
        alert.addButton(withTitle: "Assembly")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:  createBlinkProject()
        case .alertSecondButtonReturn: createAssemblyProject()
        default: break
        }
    }

    func createAssemblyProject() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "BlinkAsmG2553"
        panel.message = "Choose a location for the new assembly project folder"
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try BlinkTemplate.createAssembly(at: url)
                openProject(at: url)
                appendConsole("✓ Created assembly project at \(url.path)\n")
            } catch {
                appendConsole("Failed to create project: \(error.localizedDescription)\n")
            }
        }
    }

    /// Switches the active project between native and external build modes by
    /// rewriting its `msp430.toml` `mode` field, then reloading the model.
    func setBuildMode(_ mode: BuildMode) {
        guard let proj = project, proj.mode != mode else { return }
        let tomlURL = proj.configURL
        guard var text = try? String(contentsOf: tomlURL, encoding: .utf8) else {
            appendConsole("✗ Couldn't read \(tomlURL.lastPathComponent) to change build mode.\n")
            return
        }
        let newLine = "mode = \"\(mode.rawValue)\""
        if let range = text.range(of: #"(?m)^[ \t]*mode[ \t]*=[ \t]*"[^"]*""#, options: .regularExpression) {
            text.replaceSubrange(range, with: newLine)
        } else if let projRange = text.range(of: #"(?m)^\[project\][ \t]*$"#, options: .regularExpression) {
            // Insert right after the [project] header.
            text.insert(contentsOf: "\n" + newLine, at: projRange.upperBound)
        } else {
            text = "[project]\n\(newLine)\n\n" + text
        }
        do {
            try text.write(to: tomlURL, atomically: true, encoding: .utf8)
        } catch {
            appendConsole("✗ Couldn't write build mode: \(error.localizedDescription)\n")
            return
        }
        // Reload the affected sub-project so the new mode takes effect now.
        if let reloaded = try? ProjectLoader.load(from: proj.rootURL) {
            subprojects[proj.rootURL] = reloaded
            project = reloaded
            ensureLSPStarted()
        }
        statusMessage = "Build mode: \(mode.rawValue)"
    }

    func openProject(at url: URL) {
        let canonical = URL(fileURLWithPath: (url.path as NSString).resolvingSymlinksInPath)
        let fm = FileManager.default

        // Reset state
        self.workspaceRoot = canonical
        self.subprojects = [:]
        self.project = nil
        self.buffers = [:]
        self.selectedFile = nil
        self.consoleOutput = ""
        editor.closeAll()

        // Load root as a sub-project if it has its own config
        let rootHasConfig = fm.fileExists(atPath: canonical.appendingPathComponent(ProjectLoader.configFileName).path)
        if rootHasConfig {
            if let rootModel = try? ProjectLoader.load(from: canonical) {
                subprojects[canonical] = rootModel
            }
        }

        // Walk for nested sub-projects under the root
        for subRoot in ProjectLoader.discoverSubprojects(at: canonical) where subRoot != canonical {
            if let model = try? ProjectLoader.load(from: subRoot) {
                subprojects[subRoot] = model
            }
        }

        // Scan all displayable files for the tree
        displayFiles = ProjectLoader.scanForDisplay(at: canonical)

        // Workspace state lives at the workspace root, not per sub-project
        let wsState = loadWorkspaceState(at: canonical)
        self.workspace = wsState
        self.activeConfig = wsState.activeConfig.isEmpty ? "Debug" : wsState.activeConfig

        // Restore tab buffers + active tab
        let restoredTabs: [URL] = wsState.openTabs.compactMap { rel in
            let u = canonical.appendingPathComponent(rel)
            return fm.fileExists(atPath: u.path) ? u : nil
        }
        for u in restoredTabs {
            editor.open(u)
            if buffers[u] == nil { buffers[u] = makeBuffer(for: u) }
        }
        if let activeRel = wsState.activeTab {
            let u = canonical.appendingPathComponent(activeRel)
            if fm.fileExists(atPath: u.path) {
                selectFile(u)
            }
        }

        // Initial active project pick
        if selectedFile == nil {
            if let rootProj = subprojects[canonical] {
                // Single-project mode — pick its preferred main file
                let preferred = rootProj.sourceFiles.first(where: { $0.lastPathComponent == "main.c" })
                    ?? rootProj.assemblyFiles.first(where: { $0.lastPathComponent == "main.s" })
                    ?? rootProj.sourceFiles.first
                    ?? rootProj.assemblyFiles.first
                if let p = preferred {
                    selectFile(p)
                } else {
                    self.project = rootProj
                }
            }
            // In workspace-with-only-nested-subprojects mode, do nothing
            // until the user clicks a file.
        }

        ensureLSPStarted()
        for u in restoredTabs { lspDidOpen(u) }
        startWatching(canonical)

        statusMessage = describeOpened(canonical)
    }

    private func describeOpened(_ root: URL) -> String {
        let name = root.lastPathComponent
        if subprojects.count == 0 {
            return "Opened \(name) (browse only — no msp430.toml)"
        } else if subprojects.count == 1, subprojects.keys.first == root {
            return "Opened \(name)"
        } else {
            return "Opened \(name) — \(subprojects.count) sub-projects"
        }
    }

    /// Returns the sub-project whose root is the closest ancestor of
    /// `fileURL`. Used to auto-switch the build context when the user
    /// selects a file in workspace mode.
    func enclosingProject(for fileURL: URL) -> ProjectModel? {
        let canonicalFile = URL(fileURLWithPath: (fileURL.path as NSString).resolvingSymlinksInPath).path
        var best: (URL, Int)?
        for subRoot in subprojects.keys {
            let prefix = subRoot.path + "/"
            if canonicalFile == subRoot.path || canonicalFile.hasPrefix(prefix) {
                let depth = subRoot.path.count
                if best == nil || depth > best!.1 {
                    best = (subRoot, depth)
                }
            }
        }
        return best.flatMap { subprojects[$0.0] }
    }

    func refreshSources() {
        guard let root = workspaceRoot else { return }
        displayFiles = ProjectLoader.scanForDisplay(at: root)
        // Reload each subproject's source list
        for (k, _) in subprojects {
            if let updated = try? ProjectLoader.load(from: k) {
                subprojects[k] = updated
            }
        }
        if let active = selectedFile {
            project = enclosingProject(for: active) ?? project
        }
    }

    /// Scaffolds an msp430.toml in the given folder and re-discovers
    /// sub-projects. Shows an alert if the folder already has one, since
    /// this is always invoked from a direct user action.
    @discardableResult
    func createProjectConfig(at folderURL: URL) -> Bool {
        let configURL = folderURL.appendingPathComponent(ProjectLoader.configFileName)
        if FileManager.default.fileExists(atPath: configURL.path) {
            let alert = NSAlert()
            alert.messageText = "msp430.toml already exists in \(folderURL.lastPathComponent)/"
            alert.informativeText = "\(configURL.path)\n\nEdit it directly or delete it first if you want to regenerate."
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return false
        }
        let toml = """
        [project]
        name = "\(folderURL.lastPathComponent)"
        mcu  = "msp430g2553"
        mode = "native"

        [flash]
        driver = "tilib"
        env    = { DYLD_LIBRARY_PATH = "~/.local/lib" }

        [defaults]
        cflags = ["-Wall", "-Wextra", "-g"]

        # Source discovery is automatic by default. Narrow it explicitly
        # if this folder contains multiple unrelated source sets:
        # [sources]
        # include = ["main.c", "hal/leds.c"]
        # exclude = ["**/*.asm"]
        """
        do {
            try toml.write(to: configURL, atomically: true, encoding: .utf8)
            appendConsole("✓ Created \(configURL.path)\n")
            // Re-discover sub-projects without re-opening (preserve tabs etc.)
            if let model = try? ProjectLoader.load(from: folderURL) {
                subprojects[folderURL] = model
                if let sel = selectedFile {
                    project = enclosingProject(for: sel) ?? project
                } else {
                    project = model
                }
            }
            // Re-scan to pick up the new toml in display files (no-op for content,
            // but refreshes sub-project recognition in the tree).
            if let root = workspaceRoot {
                displayFiles = ProjectLoader.scanForDisplay(at: root)
            }
            ensureLSPStarted()
            return true
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't create msp430.toml"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return false
        }
    }

    /// File → Create Project Config Here…
    ///
    /// "Here" = the folder of the currently active file. Falls back to
    /// the workspace root if no file is selected. This matches the user
    /// model that "here" means the thing in focus, not the entire tree.
    func createProjectConfigHere() {
        let target: URL?
        if let selected = selectedFile {
            target = selected.deletingLastPathComponent()
        } else {
            target = workspaceRoot
        }
        guard let target else { return }
        createProjectConfig(at: target)
    }

    @discardableResult
    func closeProject() -> Bool {
        guard workspaceRoot != nil else { return true }

        let dirtyBuffers = buffers.values.filter { $0.isDirty }
        if !dirtyBuffers.isEmpty {
            let alert = NSAlert()
            if dirtyBuffers.count == 1, let buf = dirtyBuffers.first {
                alert.messageText = "Save changes to \(buf.url.lastPathComponent)?"
            } else {
                alert.messageText = "Save changes to \(dirtyBuffers.count) files?"
            }
            alert.informativeText = "Your changes will be lost if you don't save them."
            alert.addButton(withTitle: "Save All")
            alert.addButton(withTitle: "Don't Save")
            alert.addButton(withTitle: "Cancel")
            let resp = alert.runModal()
            switch resp {
            case .alertFirstButtonReturn:
                for buf in dirtyBuffers {
                    do {
                        try buf.text.write(to: buf.url, atomically: true, encoding: .utf8)
                        buf.markClean()
                    } catch {
                        appendConsole("Save failed for \(buf.url.lastPathComponent): \(error.localizedDescription)\n")
                    }
                }
            case .alertSecondButtonReturn:
                break
            default:
                return false
            }
        }

        persistTask?.cancel()      // flush immediately — don't defer on close
        persistWorkspaceStateNow()

        stopWatching()
        for url in editor.openTabs { lspDidClose(url) }
        if let lsp { Task { await lsp.stop() } }
        lspRootURL = nil
        lspOpenDocs = []
        lspDiagnostics = [:]
        bufferObservers = [:]

        editor.closeAll()
        buffers = [:]
        selectedFile = nil
        project = nil
        workspaceRoot = nil
        subprojects = [:]
        displayFiles = []
        workspace = WorkspaceState()
        activeConfig = "Debug"
        consoleOutput = ""
        statusMessage = "Ready"
        return true
    }

    // MARK: - Tabs / buffers

    func selectFile(_ url: URL) {
        editor.open(url)
        selectedFile = url
        if buffers[url] == nil {
            buffers[url] = makeBuffer(for: url)
        }
        lspDidOpen(url)
        // Auto-switch active project to the sub-project enclosing this file.
        if let proj = enclosingProject(for: url) {
            project = proj
            if let resolvedConfig = workspace.activeConfig.isEmpty ? proj.configNames.first : workspace.activeConfig {
                if proj.configs[resolvedConfig] != nil {
                    activeConfig = resolvedConfig
                } else {
                    activeConfig = proj.configNames.first ?? "Debug"
                }
            }
        }
        persistWorkspaceState()
    }

    func closeTab(_ url: URL) {
        if let buf = buffers[url], buf.isDirty {
            let alert = NSAlert()
            alert.messageText = "Save changes to \(url.lastPathComponent)?"
            alert.informativeText = "Your changes will be lost if you don't save them."
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Don't Save")
            alert.addButton(withTitle: "Cancel")
            let resp = alert.runModal()
            switch resp {
            case .alertFirstButtonReturn:
                try? buf.text.write(to: url, atomically: true, encoding: .utf8)
                buf.markClean()
            case .alertThirdButtonReturn:
                return
            default:
                break
            }
        }
        lspDidClose(url)
        editor.close(url)
        buffers.removeValue(forKey: url)
        selectedFile = editor.activeTab
        if let active = selectedFile {
            project = enclosingProject(for: active) ?? project
        }
        persistWorkspaceState()
    }

    func closeAllTabs() {
        for url in editor.openTabs {
            if let buf = buffers[url], buf.isDirty {
                try? buf.text.write(to: url, atomically: true, encoding: .utf8)
                buf.markClean()
            }
        }
        for url in editor.openTabs { lspDidClose(url) }
        editor.closeAll()
        buffers = [:]
        selectedFile = nil
        persistWorkspaceState()
    }

    func nextTab() {
        editor.nextTab()
        selectedFile = editor.activeTab
        if let active = selectedFile {
            project = enclosingProject(for: active) ?? project
        }
        persistWorkspaceState()
    }

    func prevTab() {
        editor.prevTab()
        selectedFile = editor.activeTab
        if let active = selectedFile {
            project = enclosingProject(for: active) ?? project
        }
        persistWorkspaceState()
    }

    func selectTabAt(_ index: Int) {
        editor.selectIndex(index)
        selectedFile = editor.activeTab
        if let active = selectedFile {
            project = enclosingProject(for: active) ?? project
        }
        persistWorkspaceState()
    }

    func reopenLastClosed() {
        guard let url = editor.reopenLastClosed() else { return }
        if buffers[url] == nil, FileManager.default.fileExists(atPath: url.path) {
            buffers[url] = makeBuffer(for: url)
        }
        lspDidOpen(url)
        selectedFile = url
        project = enclosingProject(for: url) ?? project
        persistWorkspaceState()
    }

    func saveCurrent() {
        guard let url = selectedFile, let buf = buffers[url] else { return }
        do {
            try buf.text.write(to: url, atomically: true, encoding: .utf8)
            buf.markClean()
            statusMessage = "Saved \(url.lastPathComponent)"
        } catch {
            appendConsole("Save failed: \(error.localizedDescription)\n")
        }
    }

    func saveAll() {
        for (url, buf) in buffers where buf.isDirty {
            do {
                try buf.text.write(to: url, atomically: true, encoding: .utf8)
                buf.markClean()
            } catch {
                appendConsole("Save failed for \(url.lastPathComponent): \(error.localizedDescription)\n")
            }
        }
    }

    // MARK: - Configs

    func setActiveConfig(_ name: String) {
        guard project?.configs[name] != nil else { return }
        activeConfig = name
        persistWorkspaceState()
        statusMessage = "Active config: \(name)"
    }

    // MARK: - Workspace state persistence

    private var persistTask: Task<Void, Never>?

    /// Schedules a workspace state write, debounced to at most once per second.
    /// Call sites that fire on every tab-click use this; closeProject() calls
    /// the immediate variant directly so state is never lost on close.
    private func persistWorkspaceState() {
        persistTask?.cancel()
        persistTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.persistWorkspaceStateNow()
        }
    }

    private func workspaceStateURL(for root: URL) -> URL {
        root.appendingPathComponent(".msp430ide/workspace.json")
    }

    private func loadWorkspaceState(at root: URL) -> WorkspaceState {
        let url = workspaceStateURL(for: root)
        guard let data = try? Data(contentsOf: url),
              var state = try? JSONDecoder().decode(WorkspaceState.self, from: data) else {
            return WorkspaceState()
        }
        if state.openTabs.isEmpty, !state.openFiles.isEmpty {
            state.openTabs = state.openFiles
        }
        if state.activeTab == nil, let legacy = state.selectedFile {
            state.activeTab = legacy
        }
        return state
    }

    private func persistWorkspaceStateNow() {
        guard let root = workspaceRoot else { return }
        let snap = snapshotForWorkspace(root: root)
        workspace.activeConfig = activeConfig
        workspace.openTabs = snap.openTabs
        workspace.activeTab = snap.activeTab
        workspace.selectedFile = snap.activeTab
        workspace.openFiles = snap.openTabs

        let url = workspaceStateURL(for: root)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(workspace) {
            try? data.write(to: url)
        }
    }

    private func snapshotForWorkspace(root: URL) -> (openTabs: [String], activeTab: String?) {
        let prefix = root.path + "/"
        let rel: (URL) -> String = { url in
            url.path.hasPrefix(prefix) ? String(url.path.dropFirst(prefix.count)) : url.path
        }
        return (editor.openTabs.map(rel), editor.activeTab.map(rel))
    }

    // MARK: - Console

    func appendConsole(_ s: String) { consoleOutput += s }
    func clearConsole() {
        consoleOutput = ""
        buildDiagnostics = [:]
        diagnosticsDirty = true
        refreshDisplayedDiagnostics()
    }

    // MARK: - Debugger

    // Published state — views bind to these; DebugSession writes them via callbacks.
    @Published var debugSessionState: DebugSessionState = .idle
    @Published var breakpoints: [URL: Set<Int>] = [:]
    @Published var debugCurrentFile: URL? = nil
    @Published var debugCurrentLine: Int? = nil
    @Published var debugStack: [StackFrame] = []
    @Published var debugLocals: [LocalVariable] = []
    @Published var debugConsole: String = ""
    @Published var isDebugging: Bool = false
    @Published var debugRegisters: [RegisterValue] = []
    @Published var debugPanelTab: Int = 0
    /// Total breakpoints across all files — maintained incrementally to avoid O(n) scans.
    @Published var breakpointCount: Int = 0

    var onDebuggerStopped: (() -> Void)?

    private lazy var debugSession: DebugSession = {
        var s = DebugSession()
        s.callbacks.onStateChanged       = { [weak self] state  in self?.debugSessionState = state }
        s.callbacks.onIsDebuggingChanged = { [weak self] v      in self?.isDebugging = v }
        s.callbacks.onDebugActiveChanged = { [weak self] v      in self?.onDebugActiveChanged?(v) }
        s.callbacks.onCurrentLocation    = { [weak self] f, l   in self?.debugCurrentFile = f; self?.debugCurrentLine = l }
        s.callbacks.onStackChanged       = { [weak self] frames in self?.debugStack = frames }
        s.callbacks.onLocalsChanged      = { [weak self] locals in self?.debugLocals = locals }
        s.callbacks.onRegistersChanged   = { [weak self] regs   in self?.debugRegisters = regs }
        s.callbacks.onPanelTabChanged    = { [weak self] tab    in self?.debugPanelTab = tab }
        s.callbacks.onConsoleOutput      = { [weak self] text   in self?.appendDebugConsole(text) }
        s.callbacks.onSelectFile         = { [weak self] url    in self?.selectFile(url) }
        s.callbacks.onJumpToLine         = { url, line in
            NotificationCenter.default.post(name: .msp430EditorJumpToLine, object: nil,
                                            userInfo: ["url": url, "line": line, "column": 1])
        }
        s.callbacks.onStopped = { [weak self] in self?.onDebuggerStopped?() }
        return s
    }()

    /// Fired when a debug session starts (true) or ends (false).
    var onDebugActiveChanged: ((Bool) -> Void)?

    func appendDebugConsole(_ s: String) {
        debugConsole += s
        appendConsole(s)
    }

    func isBreakpointConfirmed(file: URL, line: Int) -> Bool {
        debugSession.isBreakpointConfirmed(file: file, line: line, isDebugging: isDebugging)
    }

    func toggleBreakpoint(file: URL, line: Int) {
        var lines = breakpoints[file] ?? []
        if lines.contains(line) {
            lines.remove(line)
            if lines.isEmpty { breakpoints.removeValue(forKey: file) } else { breakpoints[file] = lines }
            breakpointCount -= 1
            debugSession.syncBreakpoint(file: file, line: line, added: false)
        } else {
            let limit = project?.hardwareBreakpointLimit ?? 2
            guard breakpointCount < limit else {
                statusMessage = "Breakpoint limit (\(limit)) reached for \(project?.mcu ?? "this device")"
                return
            }
            lines.insert(line)
            breakpoints[file] = lines
            breakpointCount += 1
            debugSession.syncBreakpoint(file: file, line: line, added: true)
        }
    }

    func jumpToBreakpoint(file: URL, line: Int) {
        selectFile(file)
        NotificationCenter.default.post(name: .msp430EditorJumpToLine, object: nil,
                                        userInfo: ["url": file, "line": line, "column": 1])
    }

    func startDebugging() async {
        guard let proj = project else {
            appendDebugConsole("✗ No active project.\n"); return
        }
        await debugSession.start(project: proj, toolchain: toolchain, breakpoints: breakpoints)
    }

    func stopDebugging() async     { await debugSession.stop() }
    func debugContinue()           { debugSession.resume() }
    func debugPause()              { debugSession.pause() }
    func debugStepIn()             { debugSession.stepIn() }
    func debugStepOver()           { debugSession.stepOver() }
    func debugStepOut()            { debugSession.stepOut() }
    func debugStepInstruction()    { debugSession.stepInstruction() }
    func debugNextInstruction()    { debugSession.nextInstruction() }
    func selectDebugFrame(_ frame: StackFrame) { debugSession.selectFrame(frame) }

    /// Recompute the displayed `diagnostics`/`diagnosticsInOrder` by merging
    /// build and live (clangd) diagnostics. For files clangd is tracking,
    /// its diagnostics win (they reflect the current buffer); other files
    /// fall back to the last build's output.
    private func refreshDisplayedDiagnostics() {
        guard diagnosticsDirty else { return }
        diagnosticsDirty = false
        var merged = buildDiagnostics
        for (url, diags) in lspDiagnostics { merged[url] = diags }
        let cleaned = merged.filter { !$0.value.isEmpty }
        diagnostics = cleaned
        diagnosticsInOrder = cleaned
            .sorted { $0.key.path < $1.key.path }
            .flatMap { entry in
                entry.value.sorted { ($0.line, $0.column ?? 0) < ($1.line, $1.column ?? 0) }
            }
    }

    /// Re-parse a slice of the console for diagnostics; called after each
    /// build so the new errors/warnings appear in the gutter and the
    /// console becomes clickable.
    func ingestDiagnostics(fromOffset offset: Int, projectRoot: URL?) {
        guard offset >= 0, offset <= consoleOutput.count else { return }
        let startIndex = consoleOutput.index(consoleOutput.startIndex, offsetBy: offset)
        let slice = String(consoleOutput[startIndex...])
        let newDiags = DiagnosticParser.parse(output: slice, projectRoot: projectRoot)
        var byFile: [URL: [Diagnostic]] = [:]
        for diag in newDiags {
            byFile[diag.file, default: []].append(diag)
        }
        buildDiagnostics = byFile
        diagnosticsDirty = true
        refreshDisplayedDiagnostics()
        onDiagnosticsUpdated?(newDiags)
    }

    /// Jump to the source location of a diagnostic. Opens the file as a
    /// tab if needed; tells any live editor coordinator to scroll & select.
    func jumpTo(diagnostic: Diagnostic) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: diagnostic.file.path) else {
            appendConsole("Couldn't open \(diagnostic.file.path)\n")
            return
        }
        selectFile(diagnostic.file)
        // Defer until the editor view has had a chance to (re)build after
        // selectFile flipped state.
        let line = diagnostic.line
        let column = diagnostic.column ?? 1
        let url = diagnostic.file
        Task { @MainActor in
            NotificationCenter.default.post(
                name: .msp430EditorJumpToLine,
                object: nil,
                userInfo: [
                    "url": url,
                    "line": line,
                    "column": column
                ]
            )
        }
    }

    func cleanBuild() {
        guard let proj = project else { return }
        let sys = proj.buildSystem(toolchain: toolchain, configName: activeConfig)
        Task { await sys.clean { [weak self] line in Task { @MainActor [weak self] in self?.appendConsole(line) } } }
    }

    // MARK: - Build / Flash

    func build() async {
        guard let proj = project else {
            appendConsole("✗ No active project. Click a file inside a sub-project (one whose folder has msp430.toml), or right-click a folder in the tree → Create Project Config Here.\n")
            statusMessage = "No active project"
            return
        }
        if proj.mode == .native, toolchain.gccPath == nil, proj.toolchainOverride.gccPath == nil {
            appendConsole("✗ msp430-elf-gcc not found.\n")
            statusMessage = "Build failed"
            return
        }
        saveAll()
        if !consoleOutput.isEmpty && !consoleOutput.hasSuffix("\n\n") { appendConsole("\n") }
        appendConsole("────────────────────────────────────────\n")
        appendConsole("→ Build [\(activeConfig)] \(proj.name) for \(proj.mcu) (\(proj.mode.rawValue) mode)\n")
        isBuilding = true
        let outputStart = consoleOutput.count
        defer {
            isBuilding = false
            ingestDiagnostics(fromOffset: outputStart, projectRoot: proj.rootURL)
        }
        let sys = proj.buildSystem(toolchain: toolchain, configName: activeConfig)
        let result = await sys.build { [weak self] line in
            Task { @MainActor [weak self] in self?.appendConsole(line) }
        }
        switch result {
        case .success(let elf):
            appendConsole("✓ Built \(elf?.lastPathComponent ?? proj.name)\n")
            statusMessage = "Build succeeded"
        case .failure(let err):
            appendConsole("✗ \(err.localizedDescription)\n")
            statusMessage = "Build failed"
        }
    }

    func flash() async {
        guard let proj = project else {
            appendConsole("✗ No active project to flash.\n")
            statusMessage = "No active project"
            return
        }
        isFlashing = true
        defer { isFlashing = false }
        let sys = proj.buildSystem(toolchain: toolchain, configName: activeConfig)
        let result = await sys.flash { [weak self] line in
            Task { @MainActor [weak self] in self?.appendConsole(line) }
        }
        switch result {
        case .success:
            appendConsole("✓ Flashed.\n")
            statusMessage = "Flash succeeded"
        case .failure(let err):
            appendConsole("✗ \(err.localizedDescription)\n")
            statusMessage = "Flash failed"
        }
    }
}
