import SwiftUI
import AppKit

/// Vertical split with the bottom pane defaulting to `defaultFraction` of
/// the total height. Drag the divider to resize. Unlike VSplitView, the
/// initial proportion is deterministic.
struct ResizableVerticalSplit<Top: View, Bottom: View>: View {
    let defaultFraction: CGFloat
    let minTopHeight: CGFloat
    let minBottomHeight: CGFloat
    @ViewBuilder let top: () -> Top
    @ViewBuilder let bottom: () -> Bottom

    @State private var bottomHeight: CGFloat? = nil
    @State private var dragAnchor: CGFloat = 0

    private let dividerHeight: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            let available = geo.size.height - dividerHeight
            let effective = bottomHeight ?? max(minBottomHeight, available * defaultFraction)
            let clamped = min(max(effective, minBottomHeight), max(minBottomHeight, available - minTopHeight))
            let topHeight = max(minTopHeight, available - clamped)

            VStack(spacing: 0) {
                top()
                    .frame(height: topHeight)
                    .frame(maxWidth: .infinity)

                divider()

                bottom()
                    .frame(height: clamped)
                    .frame(maxWidth: .infinity)
            }
            .onAppear {
                if bottomHeight == nil {
                    bottomHeight = max(minBottomHeight, available * defaultFraction)
                }
            }
        }
    }

    private func divider() -> some View {
        ZStack {
            Color(nsColor: .separatorColor)
                .frame(height: 1)
                .frame(maxWidth: .infinity)
            Color.clear
                .frame(height: dividerHeight)
                .contentShape(Rectangle())
        }
        .frame(height: dividerHeight)
        .onHover { hovering in
            if hovering {
                NSCursor.resizeUpDown.push()
            } else {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture(coordinateSpace: .global)
                .onChanged { value in
                    if dragAnchor == 0 {
                        dragAnchor = bottomHeight ?? minBottomHeight
                    }
                    let proposed = dragAnchor - value.translation.height
                    bottomHeight = max(minBottomHeight, proposed)
                }
                .onEnded { _ in
                    dragAnchor = 0
                }
        )
    }
}
