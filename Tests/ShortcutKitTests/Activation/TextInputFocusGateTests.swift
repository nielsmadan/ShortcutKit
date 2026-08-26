import AppKit
import Carbon.HIToolbox
@testable import ShortcutField
@testable import ShortcutKit
import Testing

enum FocusGateAction: String, ShortcutAction {
    case search, save, escape, chord

    var definition: ShortcutActionDefinition {
        switch self {
        case .search: .init("Search", "k")
        case .save: .init("Save", "cmd+s")
        case .escape: .init("Escape", "escape")
        case .chord: .init("Chord", "cmd+k s")
        }
    }
}

/// ShortcutField 2.4.0 surrenders bare-key shortcuts to a focused text editor.
/// The gate lives in ShortcutField's matcher, so these assert the behaviour
/// survives the trip through ShortcutKit's own dispatch path — a future change
/// there could silence it for adopters without any ShortcutField test noticing.
///
/// The process has no key window, so `TextInputFocus` reports no focus unless
/// `responderOverride` supplies one.
@MainActor
@Suite("Text-input focus gate") struct TextInputFocusGateTests {
    private func keyDown(_ keyCode: Int, _ modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
        let cg = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: true)!
        cg.flags = CGEventFlags(rawValue: UInt64(modifiers.rawValue))
        return NSEvent(cgEvent: cg)!
    }

    /// An editable field editor, which is what AppKit installs as first
    /// responder for `NSTextField` / `NSSearchField` and their SwiftUI wrappers.
    private func withTextFieldFocus(_ body: () -> Void) {
        let textView = NSTextView(frame: .zero)
        textView.isEditable = true
        TextInputFocus.responderOverride = { textView }
        defer { TextInputFocus.responderOverride = nil }
        body()
    }

    private func fired(_ events: [NSEvent], focused: Bool) -> [FocusGateAction] {
        var fired: [FocusGateAction] = []
        let ctx = ShortcutContext<FocusGateAction>("editor")
        ctx.__setActiveHandler { action, _ in fired.append(action) }
        let matcher = ContextMatcher(context: ctx)
        let run = { for event in events {
            _ = matcher.handle(event).result
        } }
        if focused { withTextFieldFocus(run) } else { run() }
        return fired
    }

    @Test("a bare key does not dispatch while a text field has focus")
    func bareKeyYieldsToTextField() {
        #expect(fired([keyDown(kVK_ANSI_K)], focused: true).isEmpty)
    }

    @Test("the same bare key dispatches when nothing is being edited")
    func bareKeyFiresWithoutFocus() {
        #expect(fired([keyDown(kVK_ANSI_K)], focused: false) == [.search])
    }

    @Test("a command shortcut still dispatches while a text field has focus")
    func commandShortcutFiresInTextField() {
        #expect(fired([keyDown(kVK_ANSI_S, .command)], focused: true) == [.save])
    }

    @Test("escape still dispatches while a text field has focus")
    func escapeFiresInTextField() {
        #expect(fired([keyDown(kVK_Escape)], focused: true) == [.escape])
    }

    @Test("a chord completes on a bare second step even with a text field focused")
    func chordCompletesInTextField() {
        let events = [keyDown(kVK_ANSI_K, .command), keyDown(kVK_ANSI_S)]
        #expect(fired(events, focused: true) == [.chord])
    }
}
