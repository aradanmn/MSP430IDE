import CoreGraphics

/// Shared UI metrics. One scale for the whole app so views that play the
/// same role (tab strips, headers, row insets, placeholder stacks) can't
/// drift onto different ad-hoc values. Prefer these tokens to new literals;
/// when a view genuinely needs an off-scale number, say why in a comment.
enum Metrics {
    // MARK: Spacing scale

    /// 4pt — tight gaps: icon-to-text inside a row, badge internals.
    static let spacingXS: CGFloat = 4
    /// 8pt — row insets, gaps between related controls.
    static let spacingS: CGFloat = 8
    /// 12pt — tab/label horizontal insets, gaps between control groups.
    static let spacingM: CGFloat = 12
    /// 16pt — section spacing, centered-placeholder stacks.
    static let spacingL: CGFloat = 16
    /// 24pt — large breathing room around hero/empty-state content.
    static let spacingXL: CGFloat = 24

    // MARK: Bars

    /// Every horizontal bar that carries tabs or a file header: editor tab
    /// strip, dock/floating tab strips, editor file header, tear previews.
    static let barHeight: CGFloat = 30

    // MARK: Tabs

    /// Editor tabs elide long filenames instead of growing without bound.
    static let tabMaxWidth: CGFloat = 220
    /// Shared selection-highlight opacity for the hand-rolled tab strips.
    static let tabSelectionOpacity: CGFloat = 0.18

    // MARK: Glyphs

    /// Gutter/panel indicator glyphs (breakpoints, diagnostics, current line).
    static let gutterGlyphSize: CGFloat = 12
    /// Padding inside the corner badges overlaid on file-tree icons.
    static let iconBadgePadding: CGFloat = 2
}
