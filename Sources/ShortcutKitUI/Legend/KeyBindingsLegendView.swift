import ShortcutKit
import SwiftUI

/// A read-only legend / cheat-sheet of bound shortcuts. Only bound actions
/// appear (unbound entries are dropped via `KeyBindings.boundOnly()`), and each
/// entry shows its **primary** binding — an action bound to several shortcuts
/// shows only the first, to keep the legend compact.
///
/// Two ways to feed it:
/// - `init(registry:style:contextIDs:)` — observes the registry and updates
///   live as bindings change (parallel to how `KeyBindingsView` takes a
///   registry). Renders the currently-active contexts, or `contextIDs` if given.
/// - `init(bindings:style:)` — a fixed snapshot you compute yourself.
@MainActor
public struct KeyBindingsLegendView: View {
    private enum Backing {
        case snapshot(KeyBindings)
        case live(ShortcutRegistry, contextIDs: Set<String>?)
    }

    private let backing: Backing
    public let style: LegendStyle

    /// Snapshot legend from a fixed `KeyBindings` value.
    public init(bindings: KeyBindings, style: LegendStyle) {
        backing = .snapshot(bindings.boundOnly())
        self.style = style
    }

    /// Live legend bound to a registry — updates as bindings change. Renders
    /// the currently-active + global contexts (`activeBindings()`), or just
    /// `contextIDs` when provided.
    public init(registry: ShortcutRegistry, style: LegendStyle, contextIDs: Set<String>? = nil) {
        backing = .live(registry, contextIDs: contextIDs)
        self.style = style
    }

    var styleForTest: LegendStyle { style }

    public var body: some View {
        switch backing {
        case let .snapshot(bindings):
            LegendBody(bindings: bindings, style: style)
        case let .live(registry, contextIDs):
            LiveLegend(registry: registry, contextIDs: contextIDs, style: style)
        }
    }
}

/// Observes the registry and recomputes the legend on every binding change.
private struct LiveLegend: View {
    @ObservedObject var registry: ShortcutRegistry
    let contextIDs: Set<String>?
    let style: LegendStyle

    var body: some View {
        let bindings = (contextIDs.map { registry.bindings(for: $0) } ?? registry.activeBindings())
            .boundOnly()
        LegendBody(bindings: bindings, style: style)
    }
}

private struct LegendBody: View {
    let bindings: KeyBindings
    let style: LegendStyle

    var body: some View {
        switch style {
        case .modal: ModalLegend(bindings: bindings)
        case .sidebar: SidebarLegend(bindings: bindings)
        case .compactStrip: CompactStripLegend(bindings: bindings)
        }
    }
}

private struct SidebarLegend: View {
    let bindings: KeyBindings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(bindings.groups) { group in
                Text(group.displayName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)
                ForEach(group.entries) { entry in
                    HStack {
                        Text(entry.displayName)
                            .font(.system(size: 13))
                        Spacer()
                        Text(entry.effectiveShortcuts.first?.displayString ?? "")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                Divider().padding(.vertical, 2)
            }
        }
        .padding(8)
        .frame(maxWidth: 240, maxHeight: .infinity, alignment: .top)
        .background(.thinMaterial)
    }
}

private struct CompactStripLegend: View {
    let bindings: KeyBindings

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(bindings.groups.enumerated()), id: \.element.id) { groupIdx, group in
                    ForEach(group.entries) { entry in
                        HStack(spacing: 4) {
                            Text(entry.effectiveShortcuts.first?.displayString ?? "")
                                .font(.system(size: 13, design: .monospaced))
                            Text(entry.displayName)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 6)
                    }
                    if groupIdx < bindings.groups.count - 1 {
                        Divider().frame(height: 14)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .lineLimit(1)
    }
}

private struct ModalLegend: View {
    let bindings: KeyBindings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(bindings.groups) { group in
                    Section {
                        ForEach(group.entries) { entry in
                            HStack {
                                Text(entry.displayName)
                                Spacer()
                                Text(entry.effectiveShortcuts.first?.displayString ?? "").monospaced()
                            }
                        }
                    } header: {
                        Text(group.displayName).font(.headline)
                    }
                }
            }
            .padding()
        }
    }
}
