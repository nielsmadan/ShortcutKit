import SwiftUI

/// A reusable visual treatment for shortcut hints.
public protocol ShortcutHintStyle: Sendable {
    associatedtype Body: View
    typealias Configuration = HintToastContext

    @MainActor @ViewBuilder
    func makeBody(configuration: Configuration) -> Body
}

/// Overall scale for a built-in shortcut-hint toast.
public enum ShortcutHintSize: Sendable, Hashable, CaseIterable {
    /// Preserve the surrounding font and the built-in toast geometry.
    case automatic
    case small
    case medium
    case large
    case extraLarge
}

/// Container shape for a built-in shortcut-hint toast.
public enum ShortcutHintContainerStyle: Sendable, Hashable {
    case roundedRectangle
    case capsule
    case rectangle
    case none
}

/// The configurable built-in shortcut-hint toast.
public struct ShortcutHintToastStyle: ShortcutHintStyle, Hashable {
    /// Overall font, padding, and corner scale.
    public var size: ShortcutHintSize
    /// Text font. `nil` uses the selected size's font.
    public var font: Font?
    /// Text color. `nil` uses the built-in adaptive foreground.
    public var textColor: Color?
    /// Container color. `nil` uses the built-in adaptive background.
    public var backgroundColor: Color?
    /// Shape and chrome surrounding the text.
    public var container: ShortcutHintContainerStyle

    public init(
        size: ShortcutHintSize = .automatic,
        font: Font? = nil,
        textColor: Color? = nil,
        backgroundColor: Color? = nil,
        container: ShortcutHintContainerStyle = .roundedRectangle
    ) {
        self.size = size
        self.font = font
        self.textColor = textColor
        self.backgroundColor = backgroundColor
        self.container = container
    }

    @MainActor
    public func makeBody(configuration: Configuration) -> some View {
        BuiltInShortcutHintToast(configuration: configuration, style: self)
    }
}

public extension ShortcutHintStyle where Self == ShortcutHintToastStyle {
    /// The built-in toast with independently overridable appearance values.
    static func toast(
        size: ShortcutHintSize = .automatic,
        font: Font? = nil,
        textColor: Color? = nil,
        backgroundColor: Color? = nil,
        container: ShortcutHintContainerStyle = .roundedRectangle
    ) -> ShortcutHintToastStyle {
        ShortcutHintToastStyle(
            size: size,
            font: font,
            textColor: textColor,
            backgroundColor: backgroundColor,
            container: container
        )
    }
}

private struct ShortcutHintMetrics {
    let font: Font?
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let cornerRadius: CGFloat
}

private extension ShortcutHintSize {
    var metrics: ShortcutHintMetrics {
        switch self {
        case .automatic:
            ShortcutHintMetrics(font: nil, horizontalPadding: 12, verticalPadding: 8, cornerRadius: 8)
        case .small:
            ShortcutHintMetrics(font: .caption, horizontalPadding: 10, verticalPadding: 6, cornerRadius: 6)
        case .medium:
            ShortcutHintMetrics(font: .body, horizontalPadding: 12, verticalPadding: 8, cornerRadius: 8)
        case .large:
            ShortcutHintMetrics(font: .title3, horizontalPadding: 14, verticalPadding: 10, cornerRadius: 10)
        case .extraLarge:
            ShortcutHintMetrics(font: .title2, horizontalPadding: 16, verticalPadding: 12, cornerRadius: 12)
        }
    }
}

struct ShortcutHintColors: Hashable {
    let foreground: Color
    let background: Color
    let border: Color
    let borderWidth: CGFloat
}

extension ShortcutHintToastStyle {
    func resolvedColors(for colorScheme: ColorScheme) -> ShortcutHintColors {
        ShortcutHintColors(
            foreground: textColor ?? (colorScheme == .dark ? .white : Color(white: 0.12)),
            background: backgroundColor ?? Color(white: colorScheme == .dark ? 0.12 : 0.97),
            border: colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.15),
            borderWidth: 1
        )
    }
}

func emphasizedHintText(_ configuration: HintToastContext) -> AttributedString {
    var text = AttributedString(configuration.text)
    for value in [configuration.actionName, configuration.shortcut] where !value.isEmpty {
        if let range = text.range(of: value) {
            text[range].inlinePresentationIntent = .stronglyEmphasized
        }
    }
    return text
}

private struct BuiltInShortcutHintToast: View {
    let configuration: HintToastContext
    let style: ShortcutHintToastStyle

    @Environment(\.colorScheme) private var colorScheme

    private var metrics: ShortcutHintMetrics { style.size.metrics }
    private var colors: ShortcutHintColors { style.resolvedColors(for: colorScheme) }

    @ViewBuilder
    private var text: some View {
        let text = Text(emphasizedHintText(configuration)).foregroundStyle(colors.foreground)
        if let font = style.font ?? metrics.font {
            text.font(font)
        } else {
            text
        }
    }

    private var paddedText: some View {
        text
            .padding(.horizontal, metrics.horizontalPadding)
            .padding(.vertical, metrics.verticalPadding)
    }

    @ViewBuilder
    var body: some View {
        switch style.container {
        case .roundedRectangle:
            paddedText
                .background(colors.background, in: RoundedRectangle(cornerRadius: metrics.cornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: metrics.cornerRadius)
                        .strokeBorder(colors.border, lineWidth: colors.borderWidth)
                }
                .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
        case .capsule:
            paddedText
                .background(colors.background, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(colors.border, lineWidth: colors.borderWidth)
                }
                .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
        case .rectangle:
            paddedText
                .background(colors.background, in: Rectangle())
                .overlay {
                    Rectangle().strokeBorder(colors.border, lineWidth: colors.borderWidth)
                }
                .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
        case .none:
            text
        }
    }
}

struct AnyShortcutHintStyle: Sendable {
    private let body: @MainActor @Sendable (HintToastContext) -> AnyView

    init(_ style: some ShortcutHintStyle) {
        body = { @MainActor configuration in
            AnyView(style.makeBody(configuration: configuration))
        }
    }

    @MainActor
    func makeBody(configuration: HintToastContext) -> AnyView {
        body(configuration)
    }
}

private struct ShortcutHintStyleKey: EnvironmentKey {
    static let defaultValue = AnyShortcutHintStyle(ShortcutHintToastStyle())
}

extension EnvironmentValues {
    var shortcutHintStyle: AnyShortcutHintStyle {
        get { self[ShortcutHintStyleKey.self] }
        set { self[ShortcutHintStyleKey.self] = newValue }
    }
}

struct StyledShortcutHint: View {
    let configuration: HintToastContext

    @Environment(\.shortcutHintStyle) private var style

    var body: some View {
        style.makeBody(configuration: configuration)
    }
}

public extension View {
    /// Applies a reusable appearance to built-in shortcut hints in this hierarchy.
    func shortcutHintStyle(_ style: some ShortcutHintStyle) -> some View {
        environment(\.shortcutHintStyle, AnyShortcutHintStyle(style))
    }
}
