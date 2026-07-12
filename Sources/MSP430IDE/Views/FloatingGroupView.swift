import SwiftUI
import AppKit

/// Contents of a floating panel window: a tab strip across the top (one tab
/// per panel in the group) and the active panel below. Tabs can be torn out
/// or dropped onto other floating windows to re-group.
struct FloatingGroupView: View {
    @ObservedObject var group: FloatingGroup
    @EnvironmentObject var panels: PanelManager

    var body: some View {
        VStack(spacing: 0) {
            tabStrip
            Group {
                PanelContentView(id: group.active)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 240, minHeight: 160)
    }

    private var tabStrip: some View {
        HStack(spacing: 0) {
            ForEach(group.panels) { id in
                FloatingTab(group: group, id: id)
            }
            Spacer(minLength: 8)
            Button {
                panels.dockGroup(group.id)
            } label: {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
            }
            .buttonStyle(.borderless)
            .padding(.trailing, 10)
            .help("Dock these panels back into the main window")
        }
        .frame(height: 30)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color(nsColor: .separatorColor)).frame(height: 1)
        }
    }
}

private struct FloatingTab: View {
    @ObservedObject var group: FloatingGroup
    let id: PanelID
    @EnvironmentObject var panels: PanelManager
    @State private var hovering = false
    @State private var torn = false

    var body: some View {
        let active = group.active == id
        Button {
            group.active = id
        } label: {
            HStack(spacing: 6) {
                Image(systemName: id.systemImage)
                    .font(.caption)
                    .foregroundStyle(active ? .primary : .secondary)
                Text(id.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(active ? .primary : .secondary)
            }
            .padding(.horizontal, 12)
            .frame(maxHeight: .infinity)
            .background {
                if active {
                    Color(nsColor: .selectedContentBackgroundColor).opacity(0.18)
                } else if hovering {
                    Color(nsColor: .windowBackgroundColor).opacity(0.5)
                }
            }
            .overlay(alignment: .bottom) {
                if active {
                    Rectangle().fill(Color.accentColor).frame(height: 2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 16, coordinateSpace: .global)
                .onChanged { value in
                    let pulledAway = abs(value.translation.height) > 22 || abs(value.translation.width) > 80
                    if !torn && pulledAway {
                        torn = true
                        panels.beginTearPreview(id)
                    }
                    if torn { panels.moveTearPreview(to: NSEvent.mouseLocation) }
                }
                .onEnded { _ in
                    if torn {
                        panels.endTear(commit: true, id: id, at: NSEvent.mouseLocation)
                        torn = false
                    }
                }
        )
    }
}
