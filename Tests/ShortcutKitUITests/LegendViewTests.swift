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

    private func sampleLegend() -> KeyBindingsLegend {
        let ctx = ShortcutContext<Act>("editor") { _, _ in }
        let reg = ShortcutRegistry(contexts: [ctx])
        return reg.legend(for: ["editor"])
    }

    @Test func modalRendersAtLeastOneEntry() throws {
        let legend = sampleLegend()
        let view = KeyBindingsLegendView(legend: legend, style: .modal)
        #expect(view.styleForTest == .modal)
        #expect(legend.groups.isEmpty == false)
        #expect(legend.groups.first?.entries.isEmpty == false)
    }

    @Test func sidebarBuilds() {
        let legend = sampleLegend()
        let view = KeyBindingsLegendView(legend: legend, style: .sidebar)
        #expect(view.styleForTest == .sidebar)
    }

    @Test func compactStripBuilds() {
        let legend = sampleLegend()
        let view = KeyBindingsLegendView(legend: legend, style: .compactStrip)
        #expect(view.styleForTest == .compactStrip)
    }
}
