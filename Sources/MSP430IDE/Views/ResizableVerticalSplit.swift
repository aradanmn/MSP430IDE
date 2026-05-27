import SwiftUI
import AppKit

/// Vertical split with the bottom pane defaulting to `defaultFraction` of
/// the total height. Drag the divider to resize.
///
/// Unlike VSplitView, the initial proportion is deterministic: every
/// render computes the default bottom height from the live GeometryReader
/// size. Only an explicit user drag pins the bottom to a fixed pixel
/// height; until that happens we follow the fraction as the window
/// resizes.
struct ResizableVerticalSplit<Top: View, Bottom: View>: View {
    let defaultFraction: CGFloat
    let minTopHeight: CGFloat
    let minBottomHeight: CGFloat
    @ViewBuilder let top: () -> Top
    @ViewBuilder let bottom: () -> Bottom

    /// User-pinned bottom height. nil means "follow defaultFraction".
    @State private var manualBottomHeight: CGFloat? = nil
    /// Captured bottom height at the start of a drag, so deltas are stable.
    @State private var dragAnchor: CGFloat? = nil

    private let dividerHeight: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            let available = max(0, geo.size.height - dividerHeight)
            let unclamped = manualBottomHeight ?? max(minBottomHeight, available * defaultFraction)
            let maxBottom = max(minBottomHeight, available - minTopHeight)
            let bottomHeight = min(max(unclamped, minBottomHeight), maxBottom)
            let topHeight = max(minTopHeight, available - bottomHeight)

            VStack(spacing: 0) {
                top()
                    .frame(width: geo.size.width, height: topHeight)
                divider(currentHeight: bottomHeight, available: available)
                bottom()
                    .frame(width: geo.size.width, height: bottomHeight)
            }
        }
    }

    private func divider(currentHeight: CGFloat, available: CGFloat) -> some View {
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
            DragGesture()
                .onChanged { value in
                    if dragAnchor == nil {
                        dragAnchor = currentHeight
                    }
                    let proposed = (dragAnchor ?? currentHeight) - value.translation.height
                    let maxBottom = max(minBottomHeight, available - minTopHeight)
                    manualBottomHeight = min(max(proposed, minBottomHeight), maxBottom)
                }
                .onEnded { _ in
                    dragAnchor = nil
                }
        )
    }
}
