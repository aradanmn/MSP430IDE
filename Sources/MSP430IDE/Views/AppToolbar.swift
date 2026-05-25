import SwiftUI

struct AppToolbar: ToolbarContent {
    @EnvironmentObject var appState: AppState

    var body: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            if let proj = appState.project {
                Menu {
                    ForEach(proj.configNames, id: \.self) { name in
                        Button {
                            appState.setActiveConfig(name)
                        } label: {
                            HStack {
                                Text(name)
                                if name == appState.activeConfig {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "slider.horizontal.3")
                        Text(proj.mode == .external ? "external" : appState.activeConfig)
                    }
                }
                .disabled(proj.mode == .external)
                .help(proj.mode == .external
                      ? "External-mode projects defer config to the Makefile"
                      : "Active build configuration")
                .fixedSize()
            }
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                Task { await appState.build() }
            } label: {
                Label("Build", systemImage: "hammer.fill")
            }
            .disabled(appState.project == nil || appState.isBuilding)
            .help("Compile (⌘B)")

            Button {
                Task { await appState.flash() }
            } label: {
                Label("Flash", systemImage: "bolt.fill")
            }
            .disabled(appState.project == nil || appState.isFlashing)
            .help("Flash to device (⌘R)")
        }
    }
}
