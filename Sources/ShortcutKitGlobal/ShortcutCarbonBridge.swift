import ShortcutField

/// A Carbon hotkey combination — what `RegisterEventHotKey` takes.
struct CarbonHotKeyCombo: Equatable, Hashable, Sendable {
    let keyCode: UInt32
    let carbonModifiers: UInt32
}

/// Maps a ShortcutField `Shortcut` to a Carbon combo. Returns `nil` for any
/// shortcut `RegisterEventHotKey` cannot represent: continuous gestures,
/// multi-step chords, and discrete shortcuts whose single step is not a key
/// (mouse button, scroll, etc.).
enum ShortcutCarbonBridge {
    static func combo(for shortcut: Shortcut) -> CarbonHotKeyCombo? {
        guard case let .discrete(discrete) = shortcut,
              discrete.steps.count == 1,
              let step = discrete.steps.first,
              case let .key(keyCode) = step.kind
        else { return nil }
        return CarbonHotKeyCombo(
            keyCode: UInt32(keyCode),
            carbonModifiers: CarbonModifiers.carbon(from: step.modifiers)
        )
    }
}
