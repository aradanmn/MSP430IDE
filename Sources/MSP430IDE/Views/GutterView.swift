import SwiftUI
import AppKit

final class GutterState: ObservableObject {
    struct VisibleLine: Identifiable, Equatable {
        let number: Int
        let y: CGFloat
        var id: Int { number }
    }

    @Published var visibleLines: [VisibleLine] = []
    @Published var totalLines: Int = 1

    var width: CGFloat {
        let digits = max(2, String(totalLines).count)
        return CGFloat(digits) * 8 + 14
    }
}

struct GutterView: View {
    @ObservedObject var state: GutterState

    private let font = NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular)

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(nsColor: .textBackgroundColor)

            ForEach(state.visibleLines) { line in
                Text("\(line.number)")
                    .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                    .frame(width: state.width - 8, alignment: .trailing)
                    .offset(x: 0, y: line.y)
            }
        }
        .frame(maxHeight: .infinity)
        .frame(width: state.width)
        .clipped()
        .overlay(alignment: .trailing) {
            Divider()
        }
    }
}
