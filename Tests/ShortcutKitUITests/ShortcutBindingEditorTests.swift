import ShortcutField
@testable import ShortcutKit
@testable import ShortcutKitUI
import Testing

@MainActor
struct ShortcutBindingEditorTests {
    enum Act: String, ShortcutAction {
        case save, undo
        var definition: ShortcutActionDefinition {
            switch self {
            case .save: .init("Save", description: "Write the document to disk.", defaults: [Shortcut("cmd+s")])
            case .undo: .init("Undo", defaults: [Shortcut("cmd+z")])
            }
        }
    }

    @Test("editor resolves its entry from the attached registry")
    func resolvesEntry() {
        let ctx = ShortcutContext<Act>("editor")
        let registry = ShortcutRegistry(contexts: [ctx])
        let editor = ShortcutBindingEditor(.save, in: ctx)
        let entry = editor.entry
        #expect(entry?.actionID == "save")
        #expect(entry?.effectiveShortcuts == [Shortcut("cmd+s")])
        _ = registry
    }

    @Test("editor reflects an override written through the registry")
    func reflectsOverride() {
        let ctx = ShortcutContext<Act>("editor")
        let registry = ShortcutRegistry(contexts: [ctx])
        ctx.setShortcuts([Shortcut("cmd+shift+s")], for: .save)
        let editor = ShortcutBindingEditor(.save, in: ctx)
        #expect(editor.entry?.effectiveShortcuts == [Shortcut("cmd+shift+s")])
        #expect(editor.entry?.isCustomized == true)
    }

    // Passing an unattached context is a programmer error: `attachedRegistry(for:)`
    // fires `assertionFailure` in debug (and falls back to an inert empty registry
    // in release). That trap can't be exercised from an in-process Swift Testing
    // case without aborting the runner, so it's verified by code review rather than
    // a test here.
}
