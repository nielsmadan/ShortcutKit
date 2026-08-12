import AppKit
import ShortcutField

/// A comparable trigger key shared by discrete and continuous shortcuts.
struct TriggerSignature: Hashable {
    let kind: DiscreteShortcut.Kind
    let modifiers: NSEvent.ModifierFlags

    init(_ shortcut: Shortcut) {
        switch shortcut {
        case let .discrete(discrete):
            kind = discrete.steps[0].kind
            modifiers = discrete.steps[0].modifiers
        case let .continuous(continuous):
            kind = continuous.kind.asDiscreteKind
            modifiers = continuous.modifiers
        }
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(kind)
        hasher.combine(modifiers.rawValue)
    }

    static func == (lhs: TriggerSignature, rhs: TriggerSignature) -> Bool {
        lhs.kind == rhs.kind && lhs.modifiers == rhs.modifiers
    }
}
