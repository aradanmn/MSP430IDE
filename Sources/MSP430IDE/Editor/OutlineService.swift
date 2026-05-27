import Foundation

/// Skeleton — fills in during E2 (per-language outline).
/// For ASM, derived from `label` tokens. For C, derived from clangd's `documentSymbol` request.
struct OutlineItem: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let line: Int
    let kind: Kind

    enum Kind {
        case label
        case function
        case define
        case section
    }
}

@MainActor
final class OutlineService: ObservableObject {
    @Published var items: [OutlineItem] = []

    func recompute(for url: URL, text: String) {
        // TODO E2: dispatch on extension; ASM scan for labels, C calls clangd.
        items = []
    }
}
