import SwiftUI
import AppKit
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var project: ProjectModel?
    @Published var workspace: WorkspaceState = WorkspaceState()
    @Published var activeConfig: String = "Debug"
    @Published var selectedFile: URL?
    @Published var buffers: [URL: TextBuffer] = [:]
    @Published var consoleOutput: String = ""
    @Published var isBuilding: Bool = false
    @Published var isFlashing: Bool = false
    @Published var statusMessage: String = "Ready"
    @Published var toolchain: Toolchain

    let editor = EditorService()
    private var editorSubscription: AnyCancellable?

    init() {
        self.toolchain = Toolchain.detect()
        // Forward editor changes through AppState so SwiftUI views observing
        // AppState re-render when tabs change.
        editorSubscription = editor.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.objectWillChange.send()
            }
        }
    }

    // MARK: - Project lifecycle

    func promptOpenProject() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open Project"
        panel.message = "Choose an MSP430 project folder"
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
        do {
            let proj = try ProjectLoader.load(from: url)
            self.project = proj
            let ws = WorkspaceState.load(for: proj)
            self.workspace = ws
            self.activeConfig = proj.configs[ws.activeConfig] != nil ? ws.activeConfig : (proj.configNames.first ?? "Debug")
            self.buffers = [:]
            self.selectedFile = nil

            editor.restore(workspace: ws, project: proj)
            for url in editor.openTabs where buffers[url] == nil {
                buffers[url] = TextBuffer.load(from: url)
            }
            if let active = editor.activeTab {
                selectedFile = active
            }

            if selectedFile == nil {
                let preferred = proj.sourceFiles.first(where: { $0.lastPathComponent == "main.c" })
                    ?? proj.assemblyFiles.first(where: { $0.lastPathComponent == "main.s" })
                    ?? proj.sourceFiles.first
                    ?? proj.assemblyFiles.first
                if let p = preferred { selectFile(p) }
            }
            statusMessage = "Opened \(proj.name)"
        } catch {
            appendConsole("Failed to open project: \(error.localizedDescription)\n")
            statusMessage = "Open failed"
        }
    }

    func refreshSources() {
        guard var proj = project else { return }
        ProjectLoader.scanSources(into: &proj)
        self.project = proj
    }

    /// Scaffolds an msp430.toml in the current project's root folder and
    /// reloads. Useful when the user opens a plain folder and wants to
    /// turn it into a buildable project. Will not overwrite an existing
    /// msp430.toml.
    func createProjectConfigHere() {
        guard let proj = project else { return }
        let configURL = proj.rootURL.appendingPathComponent(ProjectLoader.configFileName)
        guard !FileManager.default.fileExists(atPath: configURL.path) else {
            appendConsole("msp430.toml already exists at \(configURL.path)\n")
            return
        }
        let toml = """
        [project]
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
            openProject(at: proj.rootURL)
        } catch {
            appendConsole("Failed to write msp430.toml: \(error.localizedDescription)\n")
        }
    }

    /// Closes the current project. Prompts once if any buffer is dirty.
    /// Returns true if the project was closed; false if the user cancelled.
    @discardableResult
    func closeProject() -> Bool {
        guard project != nil else { return true }

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

        if let proj = project {
            let snap = editor.snapshot(for: proj)
            workspace.activeConfig = activeConfig
            workspace.openTabs = snap.openTabs
            workspace.activeTab = snap.activeTab
            workspace.selectedFile = snap.activeTab
            workspace.openFiles = snap.openTabs
            workspace.save(for: proj)
        }

        editor.closeAll()
        buffers = [:]
        selectedFile = nil
        project = nil
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
            buffers[url] = TextBuffer.load(from: url)
        }
        persistWorkspace()
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
        editor.close(url)
        buffers.removeValue(forKey: url)
        selectedFile = editor.activeTab
        persistWorkspace()
    }

    func closeAllTabs() {
        for url in editor.openTabs {
            if let buf = buffers[url], buf.isDirty {
                try? buf.text.write(to: url, atomically: true, encoding: .utf8)
                buf.markClean()
            }
        }
        editor.closeAll()
        buffers = [:]
        selectedFile = nil
        persistWorkspace()
    }

    func nextTab() {
        editor.nextTab()
        selectedFile = editor.activeTab
        persistWorkspace()
    }

    func prevTab() {
        editor.prevTab()
        selectedFile = editor.activeTab
        persistWorkspace()
    }

    func selectTabAt(_ index: Int) {
        editor.selectIndex(index)
        selectedFile = editor.activeTab
        persistWorkspace()
    }

    func reopenLastClosed() {
        guard let url = editor.reopenLastClosed() else { return }
        if buffers[url] == nil, FileManager.default.fileExists(atPath: url.path) {
            buffers[url] = TextBuffer.load(from: url)
        }
        selectedFile = url
        persistWorkspace()
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
        persistWorkspace()
        statusMessage = "Active config: \(name)"
    }

    private func persistWorkspace() {
        guard let proj = project else { return }
        let snap = editor.snapshot(for: proj)
        workspace.activeConfig = activeConfig
        workspace.openTabs = snap.openTabs
        workspace.activeTab = snap.activeTab
        workspace.selectedFile = snap.activeTab  // legacy mirror
        workspace.openFiles = snap.openTabs       // legacy mirror
        workspace.save(for: proj)
    }

    // MARK: - Console

    func appendConsole(_ s: String) { consoleOutput += s }
    func clearConsole() { consoleOutput = "" }

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
        guard let proj = project else { return }
        if proj.isImplicit {
            appendConsole("✗ No msp430.toml in \(proj.rootURL.lastPathComponent)/. This folder is browse-only.\n")
            appendConsole("  Open a specific project folder (one containing main.c or main.s),\n")
            appendConsole("  or run File → Create Project Config Here… to scaffold one.\n")
            statusMessage = "No project config"
            return
        }
        saveAll()
        clearConsole()
        appendConsole("→ Build [\(activeConfig)] for \(proj.mcu) (\(proj.mode.rawValue) mode)\n")
        isBuilding = true
        defer { isBuilding = false }

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
        guard let proj = project else { return }
        if proj.isImplicit {
            appendConsole("✗ Browse-only: no msp430.toml in this folder.\n")
            statusMessage = "No project config"
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
            appendConsole("\n→ Flashing via mspdebug \(proj.flash.driver)\n")
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
