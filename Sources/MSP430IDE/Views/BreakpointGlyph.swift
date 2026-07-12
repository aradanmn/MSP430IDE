import SwiftUI

/// Stop-sign breakpoint indicator shared by the editor gutter and the
/// Breakpoints panel. `armed == false` means the breakpoint exceeds the
/// hardware slot limit and is not set on the target.
///
/// The ring is built from stacked filled octagons rather than an outline
/// symbol under `.scaleEffect`, so its width stays >1 device pixel on 1x
/// displays, and every layer is resized to fit inside `size` exactly so the
/// glyph never bleeds outside its frame.
struct BreakpointGlyph: View {
    var armed: Bool = true
    var size: CGFloat = 12

    var body: some View {
        ZStack {
            // Dimmed but still solid when unarmed — a set breakpoint must
            // always be clearly visible in the gutter.
            octagon(.red.opacity(armed ? 1 : 0.55), scale: 1)
            if armed {
                octagon(.white, scale: 0.72)
                octagon(.red, scale: 0.48)
            }
        }
        .frame(width: size, height: size)
    }

    private func octagon(_ color: Color, scale: CGFloat) -> some View {
        Image(systemName: "octagon.fill")
            .resizable()
            .scaledToFit()
            .foregroundStyle(color)
            .frame(width: size * scale, height: size * scale)
    }
}
