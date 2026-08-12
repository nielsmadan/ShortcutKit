import AppKit
import SwiftUI

func legendTextIsTruncated(_ text: String, font: NSFont, width: CGFloat) -> Bool {
    guard !text.isEmpty, width > 0 else { return false }
    let attributes: [NSAttributedString.Key: Any] = [.font: font]
    return (text as NSString).size(withAttributes: attributes).width > width
}

func legendTooltipText(label: String, description: LocalizedStringResource?) -> String? {
    guard let description else { return nil }
    return "\(label) — \(String(localized: description))"
}

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
    func tooltip(
        _ text: String,
        isEnabled: Bool = true,
        delay: Duration = .milliseconds(300)
    ) -> some View {
        modifier(TooltipModifier(text: text, isEnabled: isEnabled, delay: delay))
    }
}

struct TruncatableLabel: View {
    enum Sizing: Equatable {
        case fixed(CGFloat)
        case flexible
    }

    let text: String
    let font: NSFont
    let sizing: Sizing
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
