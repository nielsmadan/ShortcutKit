import Combine
import ShortcutKit
import SwiftUI

/// View modifier backing `View.shortcutHintHUD(...)`. Observes a registry's
/// `actionFired` publisher and surfaces a transient
/// "Tip: <action> is bound to <shortcut>" toast when an action fires via a
/// non-shortcut path AND has at least one effective binding.
///
/// Suppression is governed by:
///   - `HintPolicy` (developer-set upper bound on frequency)
///   - `registry.hintsEnabled` (the user preference, persisted through the
///     registry's store; default from `ShortcutRegistry(defaultHintsEnabled:)`)
///
/// `HintHUDStyle` controls placement + per-toast duration; the `toast` builder
/// renders each hint (the default overload supplies the built-in `HintToast`).
@MainActor
struct ShortcutHintHUD<Toast: View>: ViewModifier {
    @ObservedObject var registry: ShortcutRegistry
    let policy: HintPolicy
    let style: HintHUDStyle
    let toast: (HintToastContext) -> Toast

    @State private var gate: HintPolicyGate
    @State private var current: HintToastContext?
    /// Pointer location captured at fire time (only for `.cursor` placement).
    @State private var currentCursor: CGPoint?
    /// Measured size of the rendered toast, used to clamp cursor placement.
    @State private var toastSize: CGSize = .zero
    /// Last in-bounds pointer location. A reference box so `onContinuousHover`
    /// updates don't invalidate the body on every mouse move.
    @State private var tracker = CursorTracker()

    init(
        registry: ShortcutRegistry,
        policy: HintPolicy = .oncePerSession,
        style: HintHUDStyle = .default,
        @ViewBuilder toast: @escaping (HintToastContext) -> Toast
    ) {
        self.registry = registry
        self.policy = policy
        self.style = style
        self.toast = toast
        _gate = State(initialValue: HintPolicyGate(policy: policy))
    }

    func body(content: Content) -> some View {
        content
            .overlay { overlay }
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case let .active(point): tracker.point = point
                case .ended: tracker.point = nil
                @unknown default: break
                }
            }
            .onReceive(registry.actionFired) { handle(event: $0) }
    }

    private var overlay: some View {
        GeometryReader { proxy in
            if let context = current {
                let measured = toast(context)
                    .fixedSize()
                    .background(
                        GeometryReader { sizeProxy in
                            Color.clear.preference(key: ToastSizeKey.self, value: sizeProxy.size)
                        }
                    )
                    .transition(.opacity)

                if style.placement == .cursor, let point = currentCursor {
                    measured.position(clampedToastCenter(
                        cursor: point, container: proxy.size, toast: toastSize
                    ))
                } else {
                    measured
                        .padding()
                        .frame(
                            width: proxy.size.width,
                            height: proxy.size.height,
                            alignment: style.placement.alignment
                        )
                }
            }
        }
        .onPreferenceChange(ToastSizeKey.self) { toastSize = $0 }
    }

    private func handle(event: ActionFiredEvent) {
        guard registry.hintsEnabled, event.source == .programmatic else { return }
        guard let entry = entryFor(event: event),
              let firstBinding = entry.effectiveShortcuts.first
        else { return }
        guard gate.shouldShow(actionID: event.actionID) else { return }
        gate.markShown(actionID: event.actionID)
        // displayName is adopter content — resolve it against the adopter's bundle.
        let name = String(localized: entry.displayName)
        let shortcut = firstBinding.displayString
        // The template is ShortcutKit chrome — resolve against the package bundle.
        // Translators get "Tip: %@ is bound to %@".
        let text = uiString("Tip: \(name) is bound to \(shortcut)")
        let context = HintToastContext(actionName: name, shortcut: shortcut, text: text)
        withAnimation {
            current = context
            currentCursor = style.placement == .cursor ? tracker.point : nil
        }
        Task {
            try? await Task.sleep(for: style.duration)
            // Guard ensures the timer doesn't clear a newer hint that has since
            // replaced the one we set.
            if current == context {
                withAnimation { current = nil }
            }
        }
    }

    private func entryFor(event: ActionFiredEvent) -> KeyBindings.Entry? {
        for group in registry.keyBindings.groups where group.contextID == event.contextID {
            return group.entries.first(where: { $0.actionID == event.actionID })
        }
        return nil
    }
}

public extension View {
    /// Attach the discoverability HUD with the built-in toast. Gated by
    /// `registry.hintsEnabled` (the user preference, persisted through the
    /// registry's store); `policy` is the developer-set upper bound on frequency;
    /// `style` controls placement and per-toast duration.
    func shortcutHintHUD(
        registry: ShortcutRegistry,
        policy: HintPolicy = .oncePerSession,
        style: HintHUDStyle = .default
    ) -> some View {
        modifier(ShortcutHintHUD(registry: registry, policy: policy, style: style) { context in
            HintToast(text: context.text)
        })
    }

    /// Attach the discoverability HUD with a custom toast. The builder receives a
    /// `HintToastContext` (localized text plus the action name and shortcut
    /// components) and returns the view to show; everything else (gating, policy,
    /// placement, duration) behaves as the built-in variant.
    func shortcutHintHUD(
        registry: ShortcutRegistry,
        policy: HintPolicy = .oncePerSession,
        style: HintHUDStyle = .default,
        @ViewBuilder toast: @escaping (HintToastContext) -> some View
    ) -> some View {
        modifier(ShortcutHintHUD(registry: registry, policy: policy, style: style, toast: toast))
    }
}

/// Reference box so high-frequency `onContinuousHover` updates don't invalidate
/// the SwiftUI body — the point is read only when a hint fires.
@MainActor
final class CursorTracker {
    var point: CGPoint?
}

/// Centre position for a cursor-anchored toast: offset down-right of the pointer
/// by a small gap, then clamped so the toast's box stays inside the container.
/// Containers too small to fit the toast fall back to the container centre.
func clampedToastCenter(
    cursor: CGPoint,
    container: CGSize,
    toast: CGSize,
    gap: CGFloat = 12,
    inset: CGFloat = 8
) -> CGPoint {
    let halfWidth = toast.width / 2
    let halfHeight = toast.height / 2
    let minX = inset + halfWidth
    let maxX = container.width - halfWidth - inset
    let minY = inset + halfHeight
    let maxY = container.height - halfHeight - inset
    let x = maxX >= minX ? min(max(cursor.x + gap + halfWidth, minX), maxX) : container.width / 2
    let y = maxY >= minY ? min(max(cursor.y + gap + halfHeight, minY), maxY) : container.height / 2
    return CGPoint(x: x, y: y)
}

private struct ToastSizeKey: PreferenceKey {
    static let defaultValue = CGSize.zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

private struct HintToast: View {
    let text: String
    var body: some View {
        Text(text)
            .padding(8)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
