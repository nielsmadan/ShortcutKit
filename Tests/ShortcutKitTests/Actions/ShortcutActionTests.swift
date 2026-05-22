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

    @Test("definition carries displayName, kind, and defaultShortcut")
    func definitionFields() {
        let save = SampleAction.save.definition
        #expect(save.displayName == "Save")
        #expect(save.kind == .discrete)
        let expected: Shortcut = "cmd+s"
        #expect(save.defaultShortcut == expected)
    }

    @Test("kind defaults to .discrete when no shortcut is given")
    func defaultsToDiscrete() {
        let quit = SampleAction.quit.definition
        #expect(quit.kind == .discrete)
        #expect(quit.defaultShortcut == nil)
    }

    @Test("raw value is the stable persistence ID")
    func rawValueIsID() {
        #expect(SampleAction.save.rawValue == "save")
    }
}
