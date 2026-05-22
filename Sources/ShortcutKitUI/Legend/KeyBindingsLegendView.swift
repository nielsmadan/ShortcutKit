import ShortcutKit
import SwiftUI

@MainActor
public struct KeyBindingsLegendView: View {
    public let legend: KeyBindingsLegend
    public let style: LegendStyle

    public init(legend: KeyBindingsLegend, style: LegendStyle) {
        self.legend = legend
        self.style = style
    }

    var styleForTest: LegendStyle { style }

    public var body: some View {
        switch style {
        case .modal: ModalLegend(legend: legend)
        case .sidebar: SidebarLegend(legend: legend)
        case .compactStrip: CompactStripLegend(legend: legend)
        }
    }
}

private struct SidebarLegend: View {
    let legend: KeyBindingsLegend

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(legend.groups.enumerated()), id: \.offset) { _, group in
                if !group.entries.isEmpty {
                    Text(group.contextID)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.secondary)
                    ForEach(Array(group.entries.enumerated()), id: \.offset) { _, entry in
                        HStack {
                            Text(entry.displayName)
                                .font(.system(size: 13))
                            Spacer()
                            Text(entry.shortcut.displayString)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Divider().padding(.vertical, 2)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: 240, maxHeight: .infinity, alignment: .top)
        .background(.thinMaterial)
    }
}

private struct CompactStripLegend: View {
    let legend: KeyBindingsLegend

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(legend.groups.enumerated()), id: \.offset) { groupIdx, group in
                    ForEach(Array(group.entries.enumerated()), id: \.offset) { _, entry in
                        HStack(spacing: 4) {
                            Text(entry.shortcut.displayString)
                                .font(.system(size: 13, design: .monospaced))
                            Text(entry.displayName)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 6)
                    }
                    if groupIdx < legend.groups.count - 1 {
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
    let legend: KeyBindingsLegend

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(legend.groups, id: \.contextID) { group in
                    Section {
                        ForEach(Array(group.entries.enumerated()), id: \.offset) { _, entry in
                            HStack {
                                Text(entry.displayName)
                                Spacer()
                                Text(entry.shortcut.displayString).monospaced()
                            }
                        }
                    } header: {
                        Text(group.contextID).font(.headline)
                    }
                }
            }
            .padding()
        }
    }
}
