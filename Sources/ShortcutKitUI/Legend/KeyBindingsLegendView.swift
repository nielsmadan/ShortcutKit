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
/// `LegendOptions` controls columns, cell order, and font size — the default is
/// a compact, content-sized, multi-column grid with the shortcut leading each
/// cell. Pass a `label` closure to show a different (e.g. shorter) text for an
/// entry than its `displayName`; return `nil` to fall back to `displayName`.
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

private struct LegendBody: View {
    let bindings: KeyBindings
    let style: LegendStyle
    let options: LegendOptions
    let label: (KeyBindings.Entry) -> String?

    var body: some View {
        switch style {
        case .modal: ModalLegend(bindings: bindings, options: options, label: label)
        case .sidebar: SidebarLegend(bindings: bindings, options: options, label: label)
        case .compact: CompactLegend(bindings: bindings, options: options, label: label)
        }
    }
}

/// Grouped grid of entries shared by the vertical styles. **Content-sized** — no
/// forced height — so the legend is only as tall as its entries. Columns, cell
/// order, and font come from `options`.
private struct LegendGrid: View {
    let bindings: KeyBindings
    let options: LegendOptions
    let label: (KeyBindings.Entry) -> String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(bindings.groups) { group in
                Text(group.displayName)
                    .font(.system(size: options.fontSize + 2, weight: .bold))
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: legendGridItems(options.columns), alignment: .leading, spacing: 4) {
                    ForEach(group.entries) { entry in
                        LegendEntryCell(entry: entry, options: options, label: label, fillWidth: true)
                    }
                }
            }
        }
    }
}

/// One legend row: shortcut + label in `options.entryLayout` order at
/// `options.fontSize`. `fillWidth` adds a spacer for grid cells; the compact
/// strip passes `false` for a tight inline cell.
private struct LegendEntryCell: View {
    let entry: KeyBindings.Entry
    let options: LegendOptions
    let label: (KeyBindings.Entry) -> String?
    let fillWidth: Bool

    var body: some View {
        let shortcut = entry.effectiveShortcuts.first?.displayString ?? ""
        if case .shortcutLeading = options.entryLayout {
            HStack(spacing: 6) {
                shortcutText(shortcut)
                labelText
                if fillWidth { Spacer(minLength: 0) }
            }
        } else {
            HStack(spacing: 4) {
                labelText
                if fillWidth { Spacer(minLength: 4) }
                shortcutText(shortcut)
            }
        }
    }

    private func shortcutText(_ shortcut: String) -> some View {
        Text(shortcut)
            .font(.system(size: options.fontSize, design: .monospaced))
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var labelText: some View {
        if let override = label(entry) {
            Text(override).font(.system(size: options.fontSize))
        } else {
            Text(entry.displayName).font(.system(size: options.fontSize))
        }
    }
}

private struct SidebarLegend: View {
    let bindings: KeyBindings
    let options: LegendOptions
    let label: (KeyBindings.Entry) -> String?

    var body: some View {
        LegendGrid(bindings: bindings, options: options, label: label)
            .padding(8)
            .background(.thinMaterial)
    }
}

private struct ModalLegend: View {
    let bindings: KeyBindings
    let options: LegendOptions
    let label: (KeyBindings.Entry) -> String?

    var body: some View {
        ScrollView {
            LegendGrid(bindings: bindings, options: options, label: label)
                .padding()
        }
    }
}

private struct CompactLegend: View {
    let bindings: KeyBindings
    let options: LegendOptions
    let label: (KeyBindings.Entry) -> String?

    var body: some View {
        FlowLayout(spacing: 12, lineSpacing: 4) {
            ForEach(bindings.groups) { group in
                ForEach(group.entries) { entry in
                    LegendEntryCell(entry: entry, options: options, label: label, fillWidth: false)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}

/// Wrapping flow: places its subviews left-to-right and wraps to a new line when
/// the next would overflow the available width — so the compact legend reflows
/// instead of scrolling off-screen. Placement math lives in `legendFlowLayout`.
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
