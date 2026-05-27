@testable import ShortcutKit
import Testing

@Suite("ShortcutAction") struct ShortcutActionTests {
    enum SampleAction: String, ShortcutAction {
        case save, quit
        var definition: ShortcutActionDefinition {
            switch self {
            case .save: .init("Save", "cmd+s")
            case .quit: .init("Quit", kind: .discrete)
            }
        }
    }

    @Test("definition carries displayName, kind, and defaultShortcuts")
    func definitionFields() {
        let save = SampleAction.save.definition
        #expect(save.displayName == "Save")
        #expect(save.kind == .discrete)
        let expected: Shortcut = "cmd+s"
        #expect(save.defaultShortcuts == [expected])
    }

    @Test("kind defaults to .discrete when no shortcut is given")
    func defaultsToDiscrete() {
        let quit = SampleAction.quit.definition
        #expect(quit.kind == .discrete)
        #expect(quit.defaultShortcuts.isEmpty)
    }

    @Test("raw value is the stable persistence ID")
    func rawValueIsID() {
        #expect(SampleAction.save.rawValue == "save")
    }

    @Test("multi-default same-kind action keeps defaults and kind")
    func multipleDefaultsSameKindAreAccepted() {
        let def = ShortcutActionDefinition(
            "Undo", defaults: [Shortcut("cmd+z"), Shortcut("ctrl+z")]
        )
        #expect(def.kind == .discrete)
        #expect(def.defaultShortcuts.count == 2)
    }
}
