import ShortcutKit
import SwiftUI

@MainActor
public struct KeyBindingsLegendView: View {
    public let bindings: KeyBindings
    public let style: LegendStyle

    /// Renders a legend / cheat-sheet. Only bound actions are shown — unbound
    /// entries are dropped via `KeyBindings.boundOnly()`.
    public init(bindings: KeyBindings, style: LegendStyle) {
        self.bindings = bindings.boundOnly()
        self.style = style
    }

    var styleForTest: LegendStyle { style }

    public var body: some View {
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
