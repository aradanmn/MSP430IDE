import SwiftUI

/// Stop-sign breakpoint indicator shared by the editor gutter and the
/// Breakpoints panel. `armed == false` means the breakpoint exceeds the
/// hardware slot limit and is not set on the target.
struct BreakpointGlyph: View {
    var armed: Bool = true
    var size: CGFloat = 12

    var body: some View {
        ZStack {
            if armed {
                // Red fill + white inner ring = recognisable stop-sign shape
                Image(systemName: "octagon.fill")
                    .foregroundStyle(.red)
                Image(systemName: "octagon")
                    .foregroundStyle(.white)
                    .scaleEffect(0.68)
            } else {
                // Hollow octagon, dimmed — hardware slot not available
                Image(systemName: "octagon")
                    .foregroundStyle(Color.red.opacity(0.45))
            }
        }
        .font(.system(size: size, weight: .semibold))
        .frame(width: size + 1, height: size + 1)
    }
}
