import Carbon.HIToolbox

@MainActor
final class CarbonHotKey {
    let id: UInt32
    let combo: CarbonHotKeyCombo
    let onKeyDown: () -> Void

    var eventHotKeyRef: EventHotKeyRef?

    init(id: UInt32, combo: CarbonHotKeyCombo, onKeyDown: @escaping () -> Void) {
        self.id = id
        self.combo = combo
        self.onKeyDown = onKeyDown
    }
}
