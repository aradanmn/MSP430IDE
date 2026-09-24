import SwiftUI
import AppKit

/// Shared chrome for the app's hand-rolled tab strips — editor tabs
/// (TabBar), dock tabs (DockRegionView), and floating-group tabs
/// (FloatingGroupView). One implementation of the selection highlight,
/// hover wash, active underline, and horizontal inset, so the three strips
/// can't drift onto different metrics again.
extension View {
    func tabChrome(active: Bool, hovering: Bool) -> some View {
        self
            .padding(.horizontal, Metrics.spacingM)
            .frame(maxHeight: .infinity)
            .background {
                if active {
                    Color(nsColor: .selectedContentBackgroundColor)
                        .opacity(Metrics.tabSelectionOpacity)
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
}
