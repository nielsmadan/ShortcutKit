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

    @Test func modalRendersAtLeastOneEntry() throws {
        let legend = sampleLegend()
        let view = KeyBindingsLegendView(bindings: legend, style: .modal)
        #expect(view.styleForTest == .modal)
        #expect(legend.groups.isEmpty == false)
        #expect(legend.groups.first?.entries.isEmpty == false)
    }

    @Test func sidebarBuilds() {
        let legend = sampleLegend()
        let view = KeyBindingsLegendView(bindings: legend, style: .sidebar)
        #expect(view.styleForTest == .sidebar)
    }

    @Test func compactStripBuilds() {
        let legend = sampleLegend()
        let view = KeyBindingsLegendView(bindings: legend, style: .compactStrip)
        #expect(view.styleForTest == .compactStrip)
    }

    @Test func registryBasedInitBuilds() {
        let ctx = ShortcutContext<Act>("editor")
        let registry = ShortcutRegistry(contexts: [ctx])
        let view = KeyBindingsLegendView(registry: registry, style: .sidebar)
        #expect(view.styleForTest == .sidebar)
    }
}
