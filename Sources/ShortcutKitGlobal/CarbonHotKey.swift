import Carbon.HIToolbox

/// One global hotkey registration. Created and owned by `CarbonHotKeyCenter`,
/// which assigns the `id`, performs the `RegisterEventHotKey` call, and stores
/// the resulting `EventHotKeyRef` back into `eventHotKeyRef`.
@MainActor
final class CarbonHotKey {
    /// Process-unique id, also used as the Carbon `EventHotKeyID.id`.
    let id: UInt32
    let combo: CarbonHotKeyCombo
    /// Invoked on `kEventHotKeyPressed` (and the menu-mode raw-key fallback).
    let onKeyDown: () -> Void

    /// Live Carbon registration handle; `nil` while paused (menu mode) or
    /// before registration.
    var eventHotKeyRef: EventHotKeyRef?

    init(id: UInt32, combo: CarbonHotKeyCombo, onKeyDown: @escaping () -> Void) {
        self.id = id
        self.combo = combo
        self.onKeyDown = onKeyDown
    }
}
