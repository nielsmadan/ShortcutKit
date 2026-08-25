import Combine
import ShortcutKit
import SwiftUI

@MainActor
struct ShortcutHintHUD<Toast: View>: ViewModifier {
    let presenter: ShortcutHintPresenter
    let options: HintHUDOptions
    let toast: (HintToastContext) -> Toast

    @StateObject private var host: HintHUDHost

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.font) private var font
    @Environment(\.controlSize) private var controlSize
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.shortcutHintStyle) private var hintStyle

    init(
        presenter: ShortcutHintPresenter,
        options: HintHUDOptions = .default,
        @ViewBuilder toast: @escaping (HintToastContext) -> Toast
    ) {
        self.presenter = presenter
        self.options = options
        self.toast = toast
        _host = StateObject(wrappedValue: HintHUDHost(options: options))
    }

    func body(content: Content) -> some View {
        let viewPresentation = host.current.flatMap { presentation in
            presentation.options.presentation == .view ? presentation : nil
        }
        content
            .overlay {
                HintHUDToastOverlay(presentation: viewPresentation, toast: toast)
            }
            .background {
                HintHUDAnchorReader(
                    host: host,
                    presenter: presenter,
                    options: options,
                    environment: environment,
                    renderer: { context in AnyView(toast(context)) }
                )
            }
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case let .active(point): host.cursorPoint = point
                case .ended: host.cursorPoint = nil
                @unknown default: break
                }
            }
    }

    private var environment: HintHUDEnvironment {
        HintHUDEnvironment(
            colorScheme: colorScheme,
            locale: locale,
            layoutDirection: layoutDirection,
            font: font,
            controlSize: controlSize,
            dynamicTypeSize: dynamicTypeSize,
            reduceMotion: reduceMotion,
            hintStyle: hintStyle
        )
    }
}

@MainActor
struct HintHUDToastOverlay<Toast: View>: View {
    let presentation: HintHUDHost.Presentation?
    let toast: (HintToastContext) -> Toast

    @State private var toastSize: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            if let presentation {
                let measured = toast(presentation.context)
                    .fixedSize()
                    .background(
                        GeometryReader { sizeProxy in
                            Color.clear.preference(key: ToastSizeKey.self, value: sizeProxy.size)
                        }
                    )
                    .transition(presentation.options.transition.swiftUITransition(
                        reduceMotion: presentation.environment.reduceMotion
                    ))

                if presentation.options.placement == .cursor, let point = presentation.cursorPoint {
                    measured.position(clampedToastCenter(
                        cursor: point, container: proxy.size, toast: toastSize
                    ))
                } else {
                    measured
                        .padding()
                        .frame(
                            width: proxy.size.width,
                            height: proxy.size.height,
                            alignment: presentation.options.placement.alignment
                        )
                }
            }
        }
        .onPreferenceChange(ToastSizeKey.self) { toastSize = $0 }
        .allowsHitTesting(false)
    }
}

@MainActor
private struct OwnedShortcutHintHUD<Toast: View>: ViewModifier {
    @StateObject private var owner: ShortcutHintPresenterOwner
    let registry: ShortcutRegistry
    let options: HintHUDOptions
    let toast: (HintToastContext) -> Toast

    init(
        registry: ShortcutRegistry,
        options: HintHUDOptions,
        @ViewBuilder toast: @escaping (HintToastContext) -> Toast
    ) {
        _owner = StateObject(wrappedValue: ShortcutHintPresenterOwner(registry: registry))
        self.registry = registry
        self.options = options
        self.toast = toast
    }

    func body(content: Content) -> some View {
        content
            .modifier(ShortcutHintHUD(presenter: owner.presenter, options: options, toast: toast))
            .onChange(of: ObjectIdentifier(registry)) { _ in
                owner.update(registry: registry)
            }
    }
}

@MainActor
final class ShortcutHintPresenterOwner: ObservableObject {
    @Published private(set) var presenter: ShortcutHintPresenter
    private var registry: ShortcutRegistry

    init(registry: ShortcutRegistry) {
        self.registry = registry
        presenter = ShortcutHintPresenter(registry: registry)
    }

    func update(registry: ShortcutRegistry) {
        guard self.registry !== registry else { return }
        self.registry = registry
        presenter = ShortcutHintPresenter(registry: registry)
    }
}

public extension View {
    /// Adds the built-in shortcut hint HUD.
    /// Hints follow the registry's persisted enabled and frequency preferences.
    func shortcutHintHUD(
        registry: ShortcutRegistry,
        options: HintHUDOptions = .default
    ) -> some View {
        modifier(OwnedShortcutHintHUD(registry: registry, options: options) { context in
            StyledShortcutHint(configuration: context)
        })
    }

    /// Adds a shortcut hint HUD rendered by `toast`.
    /// Gating, frequency, placement, and duration match the built-in variant.
    func shortcutHintHUD(
        registry: ShortcutRegistry,
        options: HintHUDOptions = .default,
        @ViewBuilder toast: @escaping (HintToastContext) -> some View
    ) -> some View {
        modifier(OwnedShortcutHintHUD(registry: registry, options: options, toast: toast))
    }

    /// Adds the built-in shortcut hint HUD using a shared presentation domain.
    func shortcutHintHUD(
        presenter: ShortcutHintPresenter,
        options: HintHUDOptions = .default
    ) -> some View {
        modifier(ShortcutHintHUD(presenter: presenter, options: options) { context in
            StyledShortcutHint(configuration: context)
        })
    }

    /// Adds a custom shortcut hint HUD using a shared presentation domain.
    func shortcutHintHUD(
        presenter: ShortcutHintPresenter,
        options: HintHUDOptions = .default,
        @ViewBuilder toast: @escaping (HintToastContext) -> some View
    ) -> some View {
        modifier(ShortcutHintHUD(presenter: presenter, options: options, toast: toast))
    }
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

struct ToastSizeKey: PreferenceKey {
    static let defaultValue = CGSize.zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

extension HintHUDTransition {
    func swiftUITransition(reduceMotion: Bool) -> AnyTransition {
        switch self {
        case .automatic:
            reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96, anchor: .center))
        case .fade:
            .opacity
        case .scale:
            .scale(scale: 0.96, anchor: .center)
        case let .move(edge):
            .move(edge: edge)
        case .none:
            .identity
        }
    }

    func animation(_ animation: Animation) -> Animation? {
        switch self {
        case .none:
            nil
        default:
            animation
        }
    }
}
