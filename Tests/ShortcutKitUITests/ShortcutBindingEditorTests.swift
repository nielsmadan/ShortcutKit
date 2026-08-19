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

    @Test("editor uses its container's vertical spacing")
    func usesContainerVerticalSpacing() {
        let ctx = ShortcutContext<Act>("editor")
        let registry = ShortcutRegistry(contexts: [ctx])
        let editor = ShortcutBindingEditor(.save, in: ctx)
        #expect(editor.rowView?.verticalPadding == 0)
        _ = registry
    }

    @Test("editor places an enabled description inside its shortcut row")
    func forwardsDescriptionToRow() {
        let ctx = ShortcutContext<Act>("editor")
        let registry = ShortcutRegistry(contexts: [ctx])
        let editor = ShortcutBindingEditor(.save, in: ctx, showsDescription: true)
        #expect(editor.rowView?.subtitleText == "Write the document to disk.")
        _ = registry
    }

    // Swift Testing cannot exercise the unattached-context assertion without aborting the runner.
}
