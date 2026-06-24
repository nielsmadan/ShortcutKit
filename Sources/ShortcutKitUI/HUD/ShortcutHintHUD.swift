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
/// `HintHUDOptions` controls placement + per-toast duration; the `toast` builder
/// renders each hint (the default overload supplies the built-in `HintToast`).
@MainActor
struct ShortcutHintHUD<Toast: View>: ViewModifier {
    @ObservedObject var registry: ShortcutRegistry
    let policy: HintPolicy
    let options: HintHUDOptions
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
        options: HintHUDOptions = .default,
        @ViewBuilder toast: @escaping (HintToastContext) -> Toast
    ) {
        self.registry = registry
        self.policy = policy
        self.options = options
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
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .center)))

                if options.placement == .cursor, let point = currentCursor {
                    measured.position(clampedToastCenter(
                        cursor: point, container: proxy.size, toast: toastSize
                    ))
                } else {
                    measured
                        .padding()
                        .frame(
                            width: proxy.size.width,
                            height: proxy.size.height,
                            alignment: options.placement.alignment
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
        withAnimation(.easeOut(duration: 0.2)) {
            current = context
            currentCursor = options.placement == .cursor ? tracker.point : nil
        }
        Task {
            try? await Task.sleep(for: options.duration)
            // Guard ensures the timer doesn't clear a newer hint that has since
            // replaced the one we set.
            if current == context {
                withAnimation(.easeIn(duration: 0.3)) { current = nil }
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
    /// `options` controls placement and per-toast duration.
    func shortcutHintHUD(
        registry: ShortcutRegistry,
        policy: HintPolicy = .oncePerSession,
        options: HintHUDOptions = .default
    ) -> some View {
        modifier(ShortcutHintHUD(registry: registry, policy: policy, options: options) { context in
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
        options: HintHUDOptions = .default,
        @ViewBuilder toast: @escaping (HintToastContext) -> some View
    ) -> some View {
        modifier(ShortcutHintHUD(registry: registry, policy: policy, options: options, toast: toast))
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

/// The built-in hint toast. Inverts the app's theme — dark text on a light pill
/// in a dark app, light-on-dark in a light app — so the cue reads as a distinct
/// overlay rather than blending into the window chrome (the Superhuman style).
/// Adopters who want a different look pass their own via the custom-toast overload.
private struct HintToast: View {
    let text: String
    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        Text(text)
            .foregroundStyle(isDark ? Color.black : Color.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                isDark ? Color(white: 0.97) : Color(white: 0.12),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
    }
}
