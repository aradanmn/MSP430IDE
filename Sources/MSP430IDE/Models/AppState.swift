import SwiftUI
import AppKit

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

    init() {
        self.toolchain = Toolchain.detect()
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

            if let rel = ws.selectedFile {
                let candidate = proj.rootURL.appendingPathComponent(rel)
                if FileManager.default.fileExists(atPath: candidate.path) {
                    selectFile(candidate)
                }
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

    // MARK: - Buffers

    func selectFile(_ url: URL) {
        selectedFile = url
        if buffers[url] == nil {
            buffers[url] = TextBuffer.load(from: url)
        }
        if let proj = project {
            let prefix = proj.rootURL.path + "/"
            if url.path.hasPrefix(prefix) {
                workspace.selectedFile = String(url.path.dropFirst(prefix.count))
                persistWorkspace()
            }
        }
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
        workspace.activeConfig = activeConfig
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
