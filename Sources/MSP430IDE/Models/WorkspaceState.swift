import Foundation

struct WorkspaceState: Codable, Equatable {
    var activeConfig: String = "Debug"
    var openFiles: [String] = []
    var selectedFile: String?

    static func load(for project: ProjectModel) -> WorkspaceState {
        let url = project.workspaceFile
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(WorkspaceState.self, from: data) else {
            return WorkspaceState()
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
