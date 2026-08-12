import Combine
import ShortcutKit
import SwiftUI

@MainActor
struct ShortcutHintHUD<Toast: View>: ViewModifier {
    @ObservedObject var registry: ShortcutRegistry
    let options: HintHUDOptions
    let toast: (HintToastContext) -> Toast

    @State private var gate: HintPolicyGate
    @State private var current: HintToastContext?
    @State private var currentCursor: CGPoint?
    @State private var toastSize: CGSize = .zero
    @State private var tracker = CursorTracker()

    init(
        registry: ShortcutRegistry,
        options: HintHUDOptions = .default,
        @ViewBuilder toast: @escaping (HintToastContext) -> Toast
    ) {
        self.registry = registry
        self.options = options
        self.toast = toast
        _gate = State(initialValue: HintPolicyGate())
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
        guard gate.shouldShow(actionID: event.actionID, policy: registry.hintFrequency) else { return }
        gate.markShown(actionID: event.actionID)
        // Adopter content and library chrome belong to different localization bundles.
        let name = String(localized: entry.displayName)
        let shortcut = firstBinding.displayString
        let text = uiString("Tip: \(name) is bound to \(shortcut)")
        let context = HintToastContext(actionName: name, shortcut: shortcut, text: text)
        withAnimation(.easeOut(duration: 0.2)) {
            current = context
            currentCursor = options.placement == .cursor ? tracker.point : nil
        }
        Task {
            try? await Task.sleep(for: options.duration)
            // Do not let an older timer dismiss its replacement.
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
    /// Adds the built-in shortcut hint HUD.
    /// Hints follow the registry's persisted enabled and frequency preferences.
    func shortcutHintHUD(
        registry: ShortcutRegistry,
        options: HintHUDOptions = .default
    ) -> some View {
        modifier(ShortcutHintHUD(registry: registry, options: options) { context in
            HintToast(text: context.text)
        })
    }

    /// Adds a shortcut hint HUD rendered by `toast`.
    /// Gating, frequency, placement, and duration match the built-in variant.
    func shortcutHintHUD(
        registry: ShortcutRegistry,
        options: HintHUDOptions = .default,
        @ViewBuilder toast: @escaping (HintToastContext) -> some View
    ) -> some View {
        modifier(ShortcutHintHUD(registry: registry, options: options, toast: toast))
    }
}

@MainActor
final class CursorTracker {
    var point: CGPoint?
}

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
