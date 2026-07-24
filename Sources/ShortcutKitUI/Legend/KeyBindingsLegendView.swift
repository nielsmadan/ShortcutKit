import ShortcutKit
import SwiftUI

/// A read-only legend / cheat-sheet of bound shortcuts. Only bound actions
/// appear (unbound entries are dropped via `KeyBindings.boundOnly()`), and each
/// entry shows its **primary** binding — an action bound to several shortcuts
/// shows only the first, to keep the legend compact.
///
/// Entries render in the action enum's `Action.allCases` declaration order,
/// grouped by context (the registry's context order). Reorder the enum cases to
/// reorder the legend.
///
/// `LegendStyle` chooses the container (a material `.panel` or a scrolling
/// `.sheet`); `LegendOptions` controls the entry layout — columns, cell order,
/// size, and a `compact` flag that collapses to a dense headerless strip. The
/// default is a grouped table of fixed-width, aligned columns (shortcut then label,
/// long values tail-truncated with the full text on hover). Shortcuts render with
/// ShortcutField's `.compact` symbol labels by default in both layouts
/// (gestures/scroll as icons, mouse clicks abbreviated, each with a hover tooltip);
/// set `options.shortcutStyle = .text` for verbose words. Pass a `label` closure to
/// show a different (e.g. shorter) text for an entry than its `displayName`; return
/// `nil` to fall back to it.
///
/// Two ways to feed it:
/// - `init(registry:style:contextIDs:options:label:)` — observes the registry
///   and updates live as bindings change. Renders the currently-active contexts,
///   or `contextIDs` if given.
/// - `init(bindings:style:options:label:)` — a fixed snapshot you compute.
@MainActor
public struct KeyBindingsLegendView: View {
    private enum Backing {
        case snapshot(KeyBindings)
        case live(ShortcutRegistry, contextIDs: Set<String>?)
    }

    private let backing: Backing
    public let style: LegendStyle
    private let options: LegendOptions
    private let label: (KeyBindings.Entry) -> String?

    /// Snapshot legend from a fixed `KeyBindings` value.
    public init(
        bindings: KeyBindings,
        style: LegendStyle,
        options: LegendOptions = .default,
        label: @escaping (KeyBindings.Entry) -> String? = { _ in nil }
    ) {
        backing = .snapshot(bindings.boundOnly())
        self.style = style
        self.options = options
        self.label = label
    }

    /// Live legend bound to a registry — updates as bindings change. Renders the
    /// currently-active + global contexts (`activeBindings()`), or just
    /// `contextIDs` when provided.
    public init(
        registry: ShortcutRegistry,
        style: LegendStyle,
        contextIDs: Set<String>? = nil,
        options: LegendOptions = .default,
        label: @escaping (KeyBindings.Entry) -> String? = { _ in nil }
    ) {
        backing = .live(registry, contextIDs: contextIDs)
        self.style = style
        self.options = options
        self.label = label
    }

    var styleForTest: LegendStyle { style }

    public var body: some View {
        switch backing {
        case let .snapshot(bindings):
            LegendBody(bindings: bindings, style: style, options: options, label: label)
        case let .live(registry, contextIDs):
            LiveLegend(registry: registry, contextIDs: contextIDs, style: style, options: options, label: label)
        }
    }
}

/// Observes the registry and recomputes the legend on every binding change.
private struct LiveLegend: View {
    @ObservedObject var registry: ShortcutRegistry
    let contextIDs: Set<String>?
    let style: LegendStyle
    let options: LegendOptions
    let label: (KeyBindings.Entry) -> String?

    var body: some View {
        let bindings = (contextIDs.map { registry.bindings(for: $0) } ?? registry.activeBindings())
            .boundOnly()
        LegendBody(bindings: bindings, style: style, options: options, label: label)
    }
}

/// Wraps the entry content (grouped grid or compact strip, per `options.compact`)
/// in the container chosen by `style`: a material card (`.panel`) or a scrolling,
/// chrome-free region (`.sheet`).
private struct LegendBody: View {
    let bindings: KeyBindings
    let style: LegendStyle
    let options: LegendOptions
    let label: (KeyBindings.Entry) -> String?

    var body: some View {
        switch style {
        case .panel:
            content.padding(8).background(.thinMaterial)
        case .sheet:
            ScrollView { content.padding() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if options.compact {
            CompactStrip(bindings: bindings, options: options, label: label)
        } else {
            LegendGrid(bindings: bindings, options: options, label: label)
        }
    }
}

/// Grouped table of entries. **Content-sized** — no forced height — so the legend
/// is only as tall as its entries. Each group is a section header hugging its rows,
/// and the entries are fixed-width cells (so the shortcut / label columns line up)
/// arranged per `options.columns`: a `VStack` for `.single`, a `LazyVGrid` of fixed
/// columns for `.fixed(n)`, or a wrapping `FlowLayout` for `.auto`.
private struct LegendGrid: View {
    let bindings: KeyBindings
    let options: LegendOptions
    let label: (KeyBindings.Entry) -> String?

    var body: some View {
        VStack(alignment: .leading, spacing: options.metrics.sectionSpacing) {
            ForEach(bindings.groups) { group in
                VStack(alignment: .leading, spacing: options.metrics.headerToRows) {
                    LegendSectionHeader(title: group.displayName, options: options)
                    switch options.columns {
                    case .single:
                        VStack(alignment: .leading, spacing: options.metrics.rowSpacing) {
                            ForEach(group.entries) { cell($0) }
                        }
                    case let .fixed(count):
                        let items: [GridItem] = {
                            if case .flexible = effectiveLabelWidth(for: options) {
                                return legendFlexibleGridItems(
                                    count: count,
                                    minCellWidth: options.metrics.cellWidth,
                                    spacing: options.metrics.columnSpacing
                                )
                            }
                            return legendGridItems(
                                count: count,
                                cellWidth: resolvedCellWidth(for: options),
                                spacing: options.metrics.columnSpacing
                            )
                        }()
                        LazyVGrid(columns: items, alignment: .leading, spacing: options.metrics.rowSpacing) {
                            ForEach(group.entries) { cell($0) }
                        }
                    case let .auto(minWidth):
                        FlowLayout(
                            spacing: options.metrics.columnSpacing,
                            lineSpacing: options.metrics.rowSpacing,
                            minCellWidth: minWidth
                        ) {
                            ForEach(group.entries) { cell($0) }
                        }
                    }
                }
            }
        }
    }

    private func cell(_ entry: KeyBindings.Entry) -> some View {
        LegendEntryCell(entry: entry, options: options, label: label, mode: .columns)
    }
}

/// A section title: uppercased, tracked, and underscored by a thin rule so it
/// reads as a header distinct from the (sentence-case) entries beneath it.
private struct LegendSectionHeader: View {
    let title: LocalizedStringResource
    let options: LegendOptions

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: options.metrics.headerFont))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(0.6)
            Divider().opacity(0.6)
        }
    }
}

/// One legend entry, shortcut + label in `options.entryLayout` order at the size's
/// entry font. `.columns` renders each as a fixed-width column (shortcut trailing,
/// label leading), single-line and tail-truncated, with the full value on hover —
/// so entries line up into a table. `.inline` is the compact strip's content-sized,
/// single-line pair (no fixed width, no truncation).
private struct LegendEntryCell: View {
    let entry: KeyBindings.Entry
    let options: LegendOptions
    let label: (KeyBindings.Entry) -> String?
    let mode: Mode

    enum Mode: Equatable { case columns, inline }

    private var primaryShortcut: Shortcut? { entry.effectiveShortcuts.first }
    private var shortcut: String { primaryShortcut?.displayString ?? "" }
    private var labelString: String { label(entry) ?? String(localized: entry.displayName) }

    /// Both layouts default to ShortcutField's `.compact` symbols;
    /// `options.shortcutStyle` overrides to verbose text.
    private var effectiveStyle: ShortcutLabelStyle {
        legendShortcutStyle(override: options.shortcutStyle)
    }

    /// The shortcut portion: a symbol/abbreviation `ShortcutLabel` in `.compact`
    /// style, otherwise the plain monospaced `displayString`.
    @ViewBuilder
    private func shortcutDisplay(fontSize: CGFloat) -> some View {
        if effectiveStyle == .compact, let primaryShortcut {
            ShortcutLabel(primaryShortcut, style: .compact)
                .font(.system(size: fontSize))
                .foregroundStyle(.secondary)
        } else {
            Text(shortcut)
                .font(.system(size: fontSize, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    var body: some View {
        switch mode {
        case .columns: columnsRow
        case .inline: inlineRow
        }
    }

    /// Fixed-width, tail-truncated columns. `.clipped()` keeps a wide shortcut
    /// (multi-step chords in `.compact`) from spilling past its column into the
    /// gutter/label. The `.compact` shortcut relies on `ShortcutLabel`'s own
    /// per-glyph tooltips; the `.text` path gets a column-wide tooltip (gated on a
    /// monospaced truncation measurement) since a truncated word otherwise has no
    /// way to reveal its full value.
    private var columnsRow: some View {
        let m = options.metrics
        let shortcutColumn = shortcutDisplay(fontSize: m.entryFont)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: m.shortcutWidth, alignment: .trailing)
            .clipped()
            .tooltip(
                shortcut,
                isEnabled: effectiveStyle == .text
                    && legendTextIsTruncated(shortcut, fontSize: m.entryFont, width: m.shortcutWidth, monospaced: true)
            )
        let sizing: TruncatableLabel.Sizing = switch effectiveLabelWidth(for: options) {
        case .size: .fixed(m.labelWidth)
        case .flexible: .flexible
        case let .fixed(width): .fixed(width)
        }
        let labelColumn = TruncatableLabel(text: labelString, fontSize: m.entryFont, sizing: sizing)
        return HStack(spacing: m.gutter) {
            if case .shortcutLeading = options.entryLayout {
                shortcutColumn
                labelColumn
            } else {
                labelColumn
                shortcutColumn
            }
        }
    }

    /// Content-sized single-line pair for the compact strip.
    private var inlineRow: some View {
        let m = options.metrics
        let shortcutView = shortcutDisplay(fontSize: m.entryFont)
        let labelText = Text(labelString).font(.system(size: m.entryFont))
        return HStack(spacing: 6) {
            if case .shortcutLeading = options.entryLayout {
                shortcutView
                labelText
            } else {
                labelText
                shortcutView
            }
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }
}

/// The densest form (`options.compact`): one continuous wrap of every entry,
/// no section headers, content-width cells (no column alignment). For a thin
/// strip. The enclosing `LegendBody` container adds the padding / chrome.
private struct CompactStrip: View {
    let bindings: KeyBindings
    let options: LegendOptions
    let label: (KeyBindings.Entry) -> String?

    var body: some View {
        FlowLayout(spacing: options.metrics.columnSpacing, lineSpacing: options.metrics.rowSpacing) {
            ForEach(bindings.groups) { group in
                ForEach(group.entries) { entry in
                    LegendEntryCell(entry: entry, options: options, label: label, mode: .inline)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Wrapping flow: places its subviews left-to-right and wraps to a new line when
/// the next would overflow the available width — so the legend reflows instead of
/// stretching or scrolling off-screen. Placement math lives in `legendFlowLayout`.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 12
    var lineSpacing: CGFloat = 4
    var minCellWidth: CGFloat = 0

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        return legendFlowLayout(
            sizes: sizes, maxWidth: proposal.width ?? .infinity,
            spacing: spacing, lineSpacing: lineSpacing, minCellWidth: minCellWidth
        ).size
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let positions = legendFlowLayout(
            sizes: sizes, maxWidth: bounds.width,
            spacing: spacing, lineSpacing: lineSpacing, minCellWidth: minCellWidth
        ).positions
        for (subview, position) in zip(subviews, positions) {
            subview.place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }
}
