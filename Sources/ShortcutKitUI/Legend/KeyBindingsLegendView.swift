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
/// default is a grouped, content-sized, multi-column grid with the shortcut
/// leading each cell. Pass a `label` closure to show a different (e.g. shorter)
/// text for an entry than its `displayName`; return `nil` to fall back to it.
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

/// Grouped grid of entries shared by the vertical styles. **Content-sized** — no
/// forced height — so the legend is only as tall as its entries. Each group is a
/// section header hugging its rows (header-to-rows gap < gap between groups), and
/// the entries flow into even, content-sized columns under `.auto`, or a fixed
/// `LazyVGrid` under `.single` / `.fixed`.
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
                    case let .auto(minWidth):
                        FlowLayout(spacing: options.metrics.columnSpacing, lineSpacing: options.metrics.rowSpacing) {
                            ForEach(group.entries) { entry in
                                LegendEntryCell(
                                    entry: entry,
                                    options: options,
                                    label: label,
                                    fit: .flow(minWidth: minWidth)
                                )
                            }
                        }
                    case .single, .fixed:
                        LazyVGrid(
                            columns: legendGridItems(options.columns, spacing: options.metrics.columnSpacing),
                            alignment: .leading,
                            spacing: options.metrics.rowSpacing
                        ) {
                            ForEach(group.entries) { entry in
                                LegendEntryCell(entry: entry, options: options, label: label, fit: .fill)
                            }
                        }
                    }
                }
            }
        }
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
                .font(.system(size: options.metrics.headerFont, weight: .heavy))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(0.6)
            Divider().opacity(0.6)
        }
    }
}

/// One legend row: shortcut + label in `options.entryLayout` order at the size's
/// entry font. `fit` decides sizing: `.fill` stretches across a grid column (a
/// spacer pushes the pair apart); `.flow` sizes to content with an optional
/// `minWidth` floor so flowed cells line up into loose columns.
private struct LegendEntryCell: View {
    let entry: KeyBindings.Entry
    let options: LegendOptions
    let label: (KeyBindings.Entry) -> String?
    let fit: Fit

    enum Fit: Equatable {
        case fill
        case flow(minWidth: CGFloat)
    }

    var body: some View {
        let shortcut = entry.effectiveShortcuts.first?.displayString ?? ""
        row(shortcut).modifier(FitModifier(fit: fit))
    }

    @ViewBuilder
    private func row(_ shortcut: String) -> some View {
        if case .shortcutLeading = options.entryLayout {
            HStack(spacing: 6) {
                shortcutText(shortcut)
                labelText
                if fit == .fill { Spacer(minLength: 0) }
            }
        } else {
            HStack(spacing: 4) {
                labelText
                if fit == .fill { Spacer(minLength: 4) }
                shortcutText(shortcut)
            }
        }
    }

    private func shortcutText(_ shortcut: String) -> some View {
        Text(shortcut)
            .font(.system(size: options.metrics.entryFont, design: .monospaced))
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var labelText: some View {
        if let override = label(entry) {
            Text(override).font(.system(size: options.metrics.entryFont))
        } else {
            Text(entry.displayName).font(.system(size: options.metrics.entryFont))
        }
    }
}

/// Applies `LegendEntryCell.Fit`: `.flow` clamps the cell to a single line at its
/// intrinsic width (floored at `minWidth`); `.fill` leaves it to stretch.
private struct FitModifier: ViewModifier {
    let fit: LegendEntryCell.Fit

    func body(content: Content) -> some View {
        switch fit {
        case .fill:
            content
        case let .flow(minWidth):
            content
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: minWidth, alignment: .leading)
        }
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
                    LegendEntryCell(entry: entry, options: options, label: label, fit: .flow(minWidth: 0))
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

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        return legendFlowLayout(
            sizes: sizes, maxWidth: proposal.width ?? .infinity,
            spacing: spacing, lineSpacing: lineSpacing
        ).size
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let positions = legendFlowLayout(
            sizes: sizes, maxWidth: bounds.width,
            spacing: spacing, lineSpacing: lineSpacing
        ).positions
        for (subview, position) in zip(subviews, positions) {
            subview.place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }
}
