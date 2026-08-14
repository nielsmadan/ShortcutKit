import ShortcutKit
import SwiftUI

/// A read-only legend of bound shortcuts.
///
/// Actions are grouped by context in declaration order and show only their primary
/// binding. Unbound actions are omitted.
///
/// ``LegendStyle`` controls the container and ``LegendOptions`` controls layout and
/// appearance. The `label` closure can replace an entry's display name; return `nil`
/// to use the original name.
///
/// Initialize with a registry for live updates or with `KeyBindings` for a fixed snapshot.
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
        case .panel:
            content.padding(8).background(.thinMaterial)
        case .sheet:
            ScrollView { content.padding() }
        case .embedded:
            content
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

private struct LegendGrid: View {
    let bindings: KeyBindings
    let options: LegendOptions
    let label: (KeyBindings.Entry) -> String?

    var body: some View {
        let fonts = LegendResolvedFonts(options: options)
        VStack(alignment: .leading, spacing: options.metrics.sectionSpacing) {
            ForEach(bindings.groups) { group in
                VStack(alignment: .leading, spacing: options.metrics.headerToRows) {
                    LegendSectionHeader(title: group.displayName, options: options)
                    switch options.columns {
                    case .single:
                        VStack(alignment: .leading, spacing: options.metrics.rowSpacing) {
                            ForEach(group.entries) { cell($0, fonts) }
                        }
                    case let .fixed(count):
                        let items: [GridItem] = {
                            if case .flexible = effectiveLabelWidth(for: options) {
                                return legendFlexibleGridItems(
                                    count: count,
                                    minCellWidth: resolvedCellWidth(for: options),
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
                            ForEach(group.entries) { cell($0, fonts) }
                        }
                    case let .auto(minWidth):
                        FlowLayout(
                            spacing: options.metrics.columnSpacing,
                            lineSpacing: options.metrics.rowSpacing,
                            minCellWidth: minWidth
                        ) {
                            ForEach(group.entries) { cell($0, fonts) }
                        }
                    }
                }
            }
        }
    }

    private func cell(_ entry: KeyBindings.Entry, _ fonts: LegendResolvedFonts) -> some View {
        LegendEntryCell(entry: entry, options: options, fonts: fonts, label: label, mode: .columns)
    }
}

// AppKit does not cache failed font lookups.
struct LegendResolvedFonts {
    let shortcut: NSFont
    let label: NSFont

    init(options: LegendOptions) {
        shortcut = options.appearance.shortcutNSFont(defaultSize: options.metrics.entryFont)
        label = options.appearance.labelNSFont(defaultSize: options.metrics.entryFont)
    }
}

private struct LegendSectionHeader: View {
    let title: LocalizedStringResource
    let options: LegendOptions

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(Font(options.appearance.headerNSFont(defaultSize: options.metrics.headerFont)))
                .foregroundStyle(options.appearance.headerForeground)
                .textCase(.uppercase)
                .kerning(0.6)
            Divider().opacity(0.6)
        }
    }
}

private struct LegendEntryCell: View {
    let entry: KeyBindings.Entry
    let options: LegendOptions
    let fonts: LegendResolvedFonts
    let label: (KeyBindings.Entry) -> String?
    let mode: Mode

    enum Mode: Equatable { case columns, inline }

    private var primaryShortcut: Shortcut? { entry.effectiveShortcuts.first }
    private var shortcut: String { primaryShortcut?.displayString ?? "" }
    private var labelString: String { label(entry) ?? String(localized: entry.displayName) }

    private var descriptionTooltip: String? {
        legendTooltipText(label: labelString, description: entry.description)
    }

    private var effectiveStyle: ShortcutLabelStyle {
        legendShortcutStyle(override: options.shortcutStyle)
    }

    @ViewBuilder
    private var shortcutContent: some View {
        if effectiveStyle == .compact, let primaryShortcut {
            ShortcutLabel(primaryShortcut, style: .compact)
        } else {
            Text(shortcut)
        }
    }

    private var shortcutDisplay: some View {
        shortcutContent
            .font(Font(fonts.shortcut))
            .foregroundStyle(options.appearance.shortcutForeground)
    }

    var body: some View {
        switch mode {
        case .columns: columnsRow
        case .inline: inlineRow
        }
    }

    private var columnsRow: some View {
        let m = options.metrics
        let widths = legendColumnWidths(for: options)
        let shortcutColumn = shortcutDisplay
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: widths.shortcut, alignment: .trailing)
            .clipped()
            .tooltip(
                shortcut,
                isEnabled: effectiveStyle == .text
                    && legendTextIsTruncated(shortcut, font: fonts.shortcut, width: widths.shortcut)
            )
        let sizing: TruncatableLabel.Sizing = switch effectiveLabelWidth(for: options) {
        case .size: .fixed(widths.label)
        case .flexible: .flexible
        case let .fixed(width): .fixed(width)
        }
        let labelColumn = TruncatableLabel(
            text: labelString, font: fonts.label, sizing: sizing,
            tooltipOverrideText: descriptionTooltip
        )
        .foregroundStyle(options.appearance.labelForeground)
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

    private var inlineRow: some View {
        let shortcutView = shortcutDisplay
            .fixedSize(horizontal: true, vertical: false)
        let labelText = Text(labelString)
            .font(Font(fonts.label))
            .foregroundStyle(options.appearance.labelForeground)
            .tooltip(descriptionTooltip ?? labelString, isEnabled: descriptionTooltip != nil)
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
        .truncationMode(.tail)
    }
}

private struct CompactStrip: View {
    let bindings: KeyBindings
    let options: LegendOptions
    let label: (KeyBindings.Entry) -> String?

    var body: some View {
        let fonts = LegendResolvedFonts(options: options)
        FlowLayout(spacing: options.metrics.columnSpacing, lineSpacing: options.metrics.rowSpacing) {
            ForEach(bindings.groups) { group in
                ForEach(group.entries) { entry in
                    LegendEntryCell(entry: entry, options: options, fonts: fonts, label: label, mode: .inline)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

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
        let layout = legendFlowLayout(
            sizes: sizes, maxWidth: bounds.width,
            spacing: spacing, lineSpacing: lineSpacing, minCellWidth: minCellWidth
        )
        for (index, subview) in subviews.enumerated() {
            let position = layout.positions[index]
            let itemSize = layout.itemSizes[index]
            subview.place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: ProposedViewSize(itemSize)
            )
        }
    }
}
