import ShortcutField
@testable import ShortcutKit
@testable import ShortcutKitUI
import SwiftUI
import Testing

@MainActor
struct LegendViewTests {
    enum Act: String, ShortcutAction {
        case save, new
        var definition: ShortcutActionDefinition {
            switch self {
            case .save: .init("Save", Shortcut("cmd+s"))
            case .new: .init("New", Shortcut("cmd+n"))
            }
        }
    }

    private func sampleLegend() -> KeyBindings {
        let ctx = ShortcutContext<Act>("editor")
        let reg = ShortcutRegistry(contexts: [ctx])
        return reg.bindings(for: ["editor"]).boundOnly()
    }

    @Test func sheetRendersAtLeastOneEntry() throws {
        let legend = sampleLegend()
        let view = KeyBindingsLegendView(bindings: legend, style: .sheet)
        #expect(view.styleForTest == .sheet)
        #expect(legend.groups.isEmpty == false)
        #expect(legend.groups.first?.entries.isEmpty == false)
    }

    @Test func panelBuilds() {
        let legend = sampleLegend()
        let view = KeyBindingsLegendView(bindings: legend, style: .panel)
        #expect(view.styleForTest == .panel)
    }

    @Test func compactOptionBuilds() {
        let legend = sampleLegend()
        let view = KeyBindingsLegendView(bindings: legend, style: .panel, options: LegendOptions(compact: true))
        #expect(view.styleForTest == .panel)
    }

    @Test func registryBasedInitBuilds() {
        let ctx = ShortcutContext<Act>("editor")
        let registry = ShortcutRegistry(contexts: [ctx])
        let view = KeyBindingsLegendView(registry: registry, style: .panel)
        #expect(view.styleForTest == .panel)
    }

    @Test func optionsAndLabelInitsBuild() {
        let legend = sampleLegend()
        let view = KeyBindingsLegendView(
            bindings: legend,
            style: .panel,
            options: LegendOptions(columns: .fixed(2), entryLayout: .labelLeading, size: .large),
            label: { $0.actionID == "save" ? "Save Doc" : nil }
        )
        #expect(view.styleForTest == .panel)
    }
}
