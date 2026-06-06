import ShortcutField
@testable import ShortcutKit
@testable import ShortcutKitUI
import SwiftUI
import Testing

@MainActor
struct KeyBindingsViewTests {
    enum Act: String, ShortcutAction {
        case save, new
        var definition: ShortcutActionDefinition {
            switch self {
            case .save: .init("Save", Shortcut("cmd+s"))
            case .new: .init("New", Shortcut("cmd+n"))
            }
        }
    }

    private func makeRegistry(contextCount: Int) -> ShortcutRegistry {
        let contexts = (0 ..< contextCount).map { i in
            ShortcutContext<Act>("ctx\(i)")
        }
        return ShortcutRegistry(contexts: contexts)
    }

    @Test func fullModeBindsToRegistry() {
        let view = KeyBindingsView(registry: makeRegistry(contextCount: 2))
        #expect(view.__modeIsFull)
    }

    @Test func fullModeSearchEnabledByDefault() {
        let view = KeyBindingsView(registry: makeRegistry(contextCount: 1))
        #expect(view.__searchEnabledForTest == true)
    }

    @Test func fullModeSearchOptOut() {
        let view = KeyBindingsView(registry: makeRegistry(contextCount: 1), searchEnabled: false)
        #expect(view.__searchEnabledForTest == false)
    }

    @Test func fullModeDefaultsToStackedLayout() {
        let view = KeyBindingsView(registry: makeRegistry(contextCount: 2))
        #expect(view.__contextLayoutForTest == .stacked)
    }

    @Test func fullModePickerLayoutOptIn() {
        let view = KeyBindingsView(registry: makeRegistry(contextCount: 5), contextLayout: .picker)
        #expect(view.__contextLayoutForTest == .picker)
    }

    @Test func inlineModeHasNoContextLayout() {
        let ctx = ShortcutContext<Act>("editor")
        let registry = ShortcutRegistry(contexts: [ctx])
        let view = KeyBindingsView(context: ctx)
        #expect(view.__contextLayoutForTest == nil)
        _ = registry
    }

    @Test func inlineModeHidesPicker() {
        let ctx = ShortcutContext<Act>("editor")
        let registry = ShortcutRegistry(contexts: [ctx])
        let view = KeyBindingsView(context: ctx)
        #expect(view.__modeIsFull == false)
        _ = registry
    }

    @Test func inlineModeDefaultsSearchOff() {
        let ctx = ShortcutContext<Act>("editor")
        let registry = ShortcutRegistry(contexts: [ctx])
        let view = KeyBindingsView(context: ctx)
        #expect(view.__searchEnabledForTest == false)
        _ = registry
    }

    @Test func inlineModeSearchOptIn() {
        let ctx = ShortcutContext<Act>("editor")
        let registry = ShortcutRegistry(contexts: [ctx])
        let view = KeyBindingsView(context: ctx, searchEnabled: true)
        #expect(view.__searchEnabledForTest == true)
        _ = registry
    }
}
