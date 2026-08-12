import AppKit
import Combine
import ShortcutField

@MainActor
final class ShortcutKitMenuItem<A: ShortcutAction>: NSMenuItem {
    private let actionValue: A
    private let context: ShortcutContext<A>
    private var cancellable: AnyCancellable?

    init(action: A, context: ShortcutContext<A>, title: String?) {
        actionValue = action
        self.context = context
        super.init(
            title: title ?? String(localized: action.definition.displayName),
            action: #selector(performShortcut),
            keyEquivalent: ""
        )
        target = self
        apply(context.shortcuts(for: action).first)
        cancellable = context.shortcutsChanges(for: action).map(\.first).sink { [weak self] shortcut in
            self?.apply(shortcut)
        }
    }

    @available(*, unavailable) required init(coder _: NSCoder) { fatalError("init(coder:) unavailable") }

    @objc private func performShortcut() {
        context.dispatch(actionValue)
    }

    private func apply(_ shortcut: Shortcut?) {
        guard case let .discrete(discrete) = shortcut,
              discrete.steps.count == 1,
              case let .key(keyCode) = discrete.steps[0].kind,
              let character = MenuKeyMapping.character(for: keyCode)
        else {
            keyEquivalent = ""
            keyEquivalentModifierMask = []
            return
        }
        keyEquivalent = character
        keyEquivalentModifierMask = discrete.steps[0].modifiers
    }
}

public extension NSMenuItem {
    /// Creates a menu item that dispatches `action` through `context`.
    ///
    /// Its key equivalent tracks a single-step keyboard binding. Other binding
    /// types produce a clickable menu item without a displayed shortcut.
    @MainActor
    static func shortcutKitItem<A>(
        _ action: A,
        in context: ShortcutContext<A>,
        title: String? = nil
    ) -> NSMenuItem {
        ShortcutKitMenuItem(action: action, context: context, title: title)
    }
}
