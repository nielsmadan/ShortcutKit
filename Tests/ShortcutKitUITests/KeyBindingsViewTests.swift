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
        let view = KeyBindingsView(registry: makeRegistry(contextCount: 1), presentation: .standalone(search: false))
        #expect(view.__searchEnabledForTest == false)
    }

    @Test func fullModeDefaultsToStackedLayout() {
        let view = KeyBindingsView(registry: makeRegistry(contextCount: 2))
        #expect(view.__contextLayoutForTest == .stacked)
    }

    @Test func fullModePickerLayoutOptIn() {
        let view = KeyBindingsView(registry: makeRegistry(contextCount: 5), presentation: .standalone(layout: .picker))
        #expect(view.__contextLayoutForTest == .picker)
    }

    @Test func fullModeDefaultsToStandalonePresentation() {
        let view = KeyBindingsView(registry: makeRegistry(contextCount: 2))
        #expect(view.__presentationForTest == .standalone())
    }

    @Test func embeddedPresentationOptIn() {
        let view = KeyBindingsView(registry: makeRegistry(contextCount: 2), presentation: .embedded)
        #expect(view.__presentationForTest == .embedded)
        #expect(view.__modeIsFull) // embedded is still full mode, just container-agnostic
    }

    @Test func embeddedIgnoresSearchAndLayout() {
        // `.embedded` carries no search/layout — the hooks report the neutral values.
        let view = KeyBindingsView(registry: makeRegistry(contextCount: 2), presentation: .embedded)
        #expect(view.__searchEnabledForTest == false)
        #expect(view.__contextLayoutForTest == nil)
    }

    @Test func test_DocExample_settingsEmbedded() {
        // Mirrors the embedded-in-Form example in UIGettingStarted.md.
        let registry = makeRegistry(contextCount: 2)
        _ = Form {
            KeyBindingsView(registry: registry, presentation: .embedded)
        }
        .formStyle(.grouped)
    }

    @Test func test_DocExample_hintPreferencesInForm() {
        // Mirrors the compose-your-own-settings example in UIGettingStarted.md.
        let registry = makeRegistry(contextCount: 2)
        _ = Form {
            Section("Display") {
                Toggle("Menu bar icon", isOn: .constant(true))
                HintPreferencesView(registry: registry)
            }
            KeyBindingsView(registry: registry, presentation: .embedded)
        }
        .formStyle(.grouped)
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

    @Test func fullModeDescriptionsOffByDefault() {
        let view = KeyBindingsView(registry: makeRegistry(contextCount: 1))
        #expect(view.__showsDescriptionsForTest == false)
    }

    @Test func fullModeDescriptionsOptIn() {
        let view = KeyBindingsView(registry: makeRegistry(contextCount: 1), showsDescriptions: true)
        #expect(view.__showsDescriptionsForTest == true)
    }

    @Test func inlineModeDescriptionsOptIn() {
        let ctx = ShortcutContext<Act>("editor")
        let registry = ShortcutRegistry(contexts: [ctx])
        let view = KeyBindingsView(context: ctx, showsDescriptions: true)
        #expect(view.__showsDescriptionsForTest == true)
        _ = registry
    }
}
