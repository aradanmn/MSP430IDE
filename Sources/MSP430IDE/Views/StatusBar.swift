import SwiftUI

struct StatusBar: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 12) {
            if appState.isBuilding || appState.isFlashing {
                ProgressView().controlSize(.small)
            }
            Text(appState.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(-1)

            Spacer(minLength: 8)

            if appState.workspaceRoot != nil, appState.project == nil {
                Label("no active project", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .layoutPriority(1)
                    .help("Click a file inside a sub-project (one whose folder contains msp430.toml), or right-click a folder in the tree to create one.")
                Divider().frame(height: 12)
            }
            if let proj = appState.project {
                if appState.subprojects.count > 1 {
                    Label(proj.name, systemImage: "folder.badge.gearshape")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .layoutPriority(1)
                    Divider().frame(height: 12)
                }
                Label(proj.mcu, systemImage: "cpu")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .layoutPriority(1)

                Divider().frame(height: 12)

                Label(proj.mode == .external ? "external" : appState.activeConfig,
                      systemImage: "slider.horizontal.3")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 4)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }
}
