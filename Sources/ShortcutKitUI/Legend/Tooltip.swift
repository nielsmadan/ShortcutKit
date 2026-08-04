import AppKit
import SwiftUI

/// True when `text` rendered in `font` would exceed `width`. Uses the AppKit
/// text-sizing path so it's synchronous + testable. Not pixel-identical to
/// SwiftUI `Text` (kerning + hinting differ slightly), but close enough to gate
/// a tooltip. Takes the same `NSFont` the caller renders with — measuring in a
/// different font than the view draws is how this gate silently goes wrong.
func legendTextIsTruncated(_ text: String, font: NSFont, width: CGFloat) -> Bool {
    guard !text.isEmpty, width > 0 else { return false }
    let attributes: [NSAttributedString.Key: Any] = [.font: font]
    return (text as NSString).size(withAttributes: attributes).width > width
}

/// The legend hover-tooltip string for an entry's label: `"Label — description"`
/// when the action carries a `description`, else `nil` (no description → the tooltip
/// falls back to its truncation-only behavior). `description` is adopter content, so
/// it resolves against the adopter's bundle, not ShortcutKitUI's chrome bundle.
func legendTooltipText(label: String, description: LocalizedStringResource?) -> String? {
    guard let description else { return nil }
    return "\(label) — \(String(localized: description))"
}

/// Custom hover tooltip. SwiftUI's `.help(...)` uses the macOS system tooltip
/// which honors `NSInitialToolTipDelay` (default ~2s) and can't be tuned; this
/// modifier renders a small overlay after a caller-supplied `delay`, gated by
/// `isEnabled` so callers only present it when the underlying text truncated.
struct TooltipModifier: ViewModifier {
    let text: String
    let isEnabled: Bool
    let delay: Duration

    @State private var isShowing = false
    @State private var pendingTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                pendingTask?.cancel()
                pendingTask = nil
                guard isEnabled else {
                    isShowing = false
                    return
                }
                if hovering {
                    pendingTask = Task { @MainActor in
                        try? await Task.sleep(for: delay)
                        if !Task.isCancelled { isShowing = true }
                    }
                } else {
                    isShowing = false
                }
            }
            .overlay(alignment: .top) {
                if isShowing {
                    Text(text)
                        .font(.system(size: 11))
                        .foregroundStyle(.primary)
                        // Bound the width so a long description (the tooltip can now
                        // carry an action's full `description`) wraps instead of
                        // running a single line off the window edge.
                        .frame(maxWidth: 320, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.regularMaterial)
                                .shadow(radius: 2, y: 1)
                        )
                        .offset(y: -22)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.12), value: isShowing)
            .onDisappear {
                pendingTask?.cancel()
                pendingTask = nil
            }
    }
}

extension View {
    /// Attach a hover tooltip that appears after `delay` when `isEnabled` is
    /// true. Unlike SwiftUI's `.help(...)`, the delay is tunable. Internal — a
    /// legend-only helper, not adopter-facing API.
    func tooltip(
        _ text: String,
        isEnabled: Bool = true,
        delay: Duration = .milliseconds(300)
    ) -> some View {
        modifier(TooltipModifier(text: text, isEnabled: isEnabled, delay: delay))
    }
}

/// A single-line `Text` in a fixed or flexible frame that automatically
/// attaches a hover tooltip *only when the text truncated*. Owns its own frame
/// so its `GeometryReader` measures the applied frame, not the Text's
/// intrinsic size — modifier order is significant.
struct TruncatableLabel: View {
    enum Sizing: Equatable {
        case fixed(CGFloat)
        case flexible
    }

    let text: String
    let font: NSFont
    let sizing: Sizing
    /// When set, the tooltip shows this instead of `text` and is always enabled
    /// (used to surface an action's description). `nil` keeps the truncation-only
    /// behavior — tooltip shows `text`, and only when it's actually clipped.
    var tooltipOverrideText: String?

    @State private var frameWidth: CGFloat = 0

    var body: some View {
        framed
            .background(GeometryReader { proxy in
                Color.clear
                    .onAppear { frameWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { new in frameWidth = new }
            })
            .contentShape(Rectangle())
            .tooltip(
                tooltipOverrideText ?? text,
                isEnabled: tooltipOverrideText != nil
                    || legendTextIsTruncated(text, font: font, width: frameWidth)
            )
    }

    @ViewBuilder
    private var framed: some View {
        let base = Text(text)
            .font(Font(font))
            .lineLimit(1)
            .truncationMode(.tail)
        switch sizing {
        case let .fixed(width):
            base.frame(width: width, alignment: .leading)
        case .flexible:
            base.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
