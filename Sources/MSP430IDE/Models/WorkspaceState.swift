import Foundation

struct WorkspaceState: Codable, Equatable {
    var activeConfig: String = "Debug"
    var openTabs: [String] = []
    var activeTab: String?
    // Legacy fields retained for backward-compatibility with workspace files
    // written by older builds. New code reads/writes openTabs/activeTab.
    var openFiles: [String] = []
    var selectedFile: String?

    static func load(for project: ProjectModel) -> WorkspaceState {
        let url = project.workspaceFile
        guard let data = try? Data(contentsOf: url),
              var state = try? JSONDecoder().decode(WorkspaceState.self, from: data) else {
            return WorkspaceState()
        }
        // Migrate legacy fields if the new ones are empty
        if state.openTabs.isEmpty, !state.openFiles.isEmpty {
            state.openTabs = state.openFiles
        }
        if state.activeTab == nil, let legacy = state.selectedFile {
            state.activeTab = legacy
        }
        return state
    }

    func save(for project: ProjectModel) {
        let dir = project.workspaceDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(self) {
            try? data.write(to: project.workspaceFile)
        }
    }
}
