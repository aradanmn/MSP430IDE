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
                appendConsole("✓ Created Blink project at \(url.path)\n")
            } catch {
                appendConsole("Failed to create project: \(error.localizedDescription)\n")
            }
        }
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

        persistWorkspaceState()

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

    private func persistWorkspaceState() {
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
        refreshDisplayedDiagnostics()
    }

    /// Recompute the displayed `diagnostics`/`diagnosticsInOrder` by merging
    /// build and live (clangd) diagnostics. For files clangd is tracking,
    /// its diagnostics win (they reflect the current buffer); other files
    /// fall back to the last build's output.
    private func refreshDisplayedDiagnostics() {
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
        DispatchQueue.main.async {
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
        switch proj.mode {
        case .native:
            try? FileManager.default.removeItem(at: proj.buildDir)
            appendConsole("Cleaned \(proj.buildDir.lastPathComponent)/\n")
        case .external:
            Task { await runExternal(command: proj.external.clean, label: "clean") }
        }
    }

    // MARK: - Build / Flash

    func build() async {
        guard let proj = project else {
            appendConsole("✗ No active project. Click a file inside a sub-project (one whose folder has msp430.toml), or right-click a folder in the tree → Create Project Config Here.\n")
            statusMessage = "No active project"
            return
        }
        saveAll()
        if !consoleOutput.isEmpty && !consoleOutput.hasSuffix("\n\n") {
            appendConsole("\n")
        }
        appendConsole("────────────────────────────────────────\n")
        appendConsole("→ Build [\(activeConfig)] \(proj.name) for \(proj.mcu) (\(proj.mode.rawValue) mode)\n")
        isBuilding = true
        let outputStart = consoleOutput.count
        defer {
            isBuilding = false
            ingestDiagnostics(fromOffset: outputStart, projectRoot: proj.rootURL)
        }

        switch proj.mode {
        case .native:
            guard toolchain.gccPath != nil || proj.toolchainOverride.gccPath != nil else {
                appendConsole("✗ msp430-elf-gcc not found.\n")
                statusMessage = "Build failed"
                return
            }
            let builder = Builder(toolchain: toolchain, project: proj, configName: activeConfig)
            let result = await builder.build { [weak self] line in
                Task { @MainActor [weak self] in self?.appendConsole(line) }
            }
            switch result {
            case .success(let elf):
                appendConsole("✓ Built \(elf.lastPathComponent)\n")
                statusMessage = "Build succeeded"
            case .failure(let err):
                appendConsole("✗ \(err.localizedDescription)\n")
                statusMessage = "Build failed"
            }
        case .external:
            let result = await ExternalBuilder(project: proj, command: proj.external.build).run(label: "build") { [weak self] line in
                Task { @MainActor [weak self] in self?.appendConsole(line) }
            }
            switch result {
            case .success:
                appendConsole("✓ Build succeeded\n")
                statusMessage = "Build succeeded"
            case .failure(let err):
                appendConsole("✗ \(err.localizedDescription)\n")
                statusMessage = "Build failed"
            }
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

        switch proj.mode {
        case .native:
            guard toolchain.mspdebugPath != nil else {
                appendConsole("✗ mspdebug not found.\n")
                statusMessage = "Flash failed"
                return
            }
            let elf = proj.buildDir.appendingPathComponent("\(proj.name).elf")
            guard FileManager.default.fileExists(atPath: elf.path) else {
                appendConsole("✗ No build output. Build first.\n")
                statusMessage = "Flash failed"
                return
            }
            appendConsole("\n→ Flashing \(proj.name) via mspdebug \(proj.flash.driver)\n")
            let result = await Flasher(toolchain: toolchain, project: proj).flash(elf: elf) { [weak self] line in
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
        case .external:
            await runExternal(command: proj.external.flash, label: "flash")
        }
    }

    private func runExternal(command: String, label: String) async {
        guard let proj = project else { return }
        appendConsole("\n→ \(label)\n")
        let result = await ExternalBuilder(project: proj, command: command).run(label: label) { [weak self] line in
            Task { @MainActor [weak self] in self?.appendConsole(line) }
        }
        switch result {
        case .success:
            appendConsole("✓ \(label) succeeded\n")
            statusMessage = "\(label.capitalized) succeeded"
        case .failure(let err):
            appendConsole("✗ \(err.localizedDescription)\n")
            statusMessage = "\(label.capitalized) failed"
        }
    }
}
