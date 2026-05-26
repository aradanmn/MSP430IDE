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

            if let proj = appState.project {
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
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }
}
