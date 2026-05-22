import AppKit
import Combine
import ShortcutField

/// Internal `NSMenuItem` subclass that re-reads its key equivalent whenever
/// the bound action's effective shortcut changes. Retains a Combine
/// subscription for the item's lifetime.
@MainActor
final class ShortcutKitMenuItem<A: ShortcutAction>: NSMenuItem {
    private let actionValue: A
    private let context: ShortcutContext<A>
    private var cancellable: AnyCancellable?

    init(action: A, context: ShortcutContext<A>, title: String?) {
        actionValue = action
        self.context = context
        super.init(
            title: title ?? action.definition.displayName,
            action: #selector(performShortcut),
            keyEquivalent: ""
        )
        target = self
        apply(context.shortcut(for: action))
        cancellable = context.shortcutChanges(for: action).sink { [weak self] shortcut in
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
    /// Build a menu item wired to dispatch `action` through `context`. The
    /// `keyEquivalent` and modifier mask follow the action's current effective
    /// shortcut when it's a single-step keyboard discrete binding; otherwise
    /// the item still works as a clickable entry with no displayed shortcut.
    /// The displayed key equivalent updates automatically when the binding
    /// changes.
    @MainActor
    static func shortcutKitItem<A>(
        _ action: A,
        in context: ShortcutContext<A>,
        title: String? = nil
    ) -> NSMenuItem {
        ShortcutKitMenuItem(action: action, context: context, title: title)
    }
}
