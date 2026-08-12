import ShortcutField

struct CarbonHotKeyCombo: Equatable, Hashable, Sendable {
    let keyCode: UInt32
    let carbonModifiers: UInt32
}

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
