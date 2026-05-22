import Combine
import ShortcutField

/// Type-erased context so a registry can hold a heterogeneous list. Public for
/// the registry's `contexts:` parameter; the package-internal surface drives
/// activation and override notifications (see same-package extensions).
@MainActor public protocol AnyShortcutContext: AnyObject {
    var id: String { get }
}

/// A named group of actions with a single dispatch closure.
///
/// At construction time the context is standalone — `shortcut(for:)` returns
/// each action's default, `isCustomized` is `false`. Adding it to a
/// `ShortcutRegistry` (Task 5) wires the override path; the registry calls
/// `__attach(registry:)` and `__notifyOverrideChange(actionID:)` through
/// internal helpers in this file.
@MainActor
public final class ShortcutContext<Action: ShortcutAction>: AnyShortcutContext {
    public let id: String

    private let dispatchClosure: @MainActor (Action, ShortcutDispatch) -> Void
    private var changeSubjects: [String: CurrentValueSubject<Shortcut?, Never>] = [:]

    // Set by the registry when this context is added. Not exposed publicly.
    weak var registry: (any RegistryOverrideSource)?

    public init(
        _ id: String,
        dispatch: @escaping @MainActor (Action, ShortcutDispatch) -> Void
    ) {
        self.id = id
        dispatchClosure = dispatch
    }

    // MARK: - Invocation

    /// Adopter-driven dispatch. Invokes the closure with `.discrete`, then
    /// emits `actionFired` with `viaShortcut: false`.
    public func dispatch(_ action: Action) {
        dispatchClosure(action, .discrete)
        registry?.recordActionFired(.init(
            contextID: id, actionID: action.rawValue, viaShortcut: false
        ))
    }

    /// Adopter-driven notify. Emits `actionFired` only; closure is not called.
    public func notify(_ action: Action) {
        registry?.recordActionFired(.init(
            contextID: id, actionID: action.rawValue, viaShortcut: false
        ))
    }

    // MARK: - Lookup

    public func shortcut(for action: Action) -> Shortcut? {
        registry?.override(contextID: id, actionID: action.rawValue)
            ?? action.definition.defaultShortcut
    }

    public func displayString(for action: Action) -> String? {
        shortcut(for: action)?.displayString
    }

    public func isCustomized(_ action: Action) -> Bool {
        registry?.override(contextID: id, actionID: action.rawValue) != nil
    }

    public func shortcutChanges(for action: Action) -> AnyPublisher<Shortcut?, Never> {
        let key = action.rawValue
        if let existing = changeSubjects[key] {
            return existing.eraseToAnyPublisher()
        }
        let subject = CurrentValueSubject<Shortcut?, Never>(shortcut(for: action))
        changeSubjects[key] = subject
        return subject.eraseToAnyPublisher()
    }

    // MARK: - Internal hooks (called by the registry)

    /// Called by `ContextMatcher` after a matcher-driven match. Invokes the
    /// closure with the supplied `kind` and emits `actionFired` with
    /// `viaShortcut: true`.
    func dispatchFromMatcher(_ action: Action, kind: ShortcutDispatch) {
        dispatchClosure(action, kind)
        registry?.recordActionFired(.init(
            contextID: id, actionID: action.rawValue, viaShortcut: true
        ))
    }

    /// Called by the registry when an override changes for this context.
    /// Pushes the new effective shortcut through `shortcutChanges(for:)`.
    func notifyOverrideChange(actionID: String) {
        guard let subject = changeSubjects[actionID] else { return }
        guard let action = Action.allCases.first(where: { $0.rawValue == actionID })
        else { return }
        subject.send(shortcut(for: action))
    }
}

/// Internal abstraction the registry conforms to so `ShortcutContext` can
/// look up overrides without a concrete reference to `ShortcutRegistry`.
/// Declared here so test doubles can stand in for the registry.
@MainActor protocol RegistryOverrideSource: AnyObject {
    func override(contextID: String, actionID: String) -> Shortcut?
    func recordActionFired(_ event: ActionFiredEvent)
    func activateContext(id: String)
    func deactivateContext(id: String)
}

/// Internal: same-module hook called by `.activeShortcutContext`.
@MainActor protocol ContextActivation: AnyObject {
    // swiftlint:disable identifier_name
    func __activate()
    func __deactivate()
    // swiftlint:enable identifier_name
}

extension ShortcutContext: RegistryAttachable {
    // swiftlint:disable:next identifier_name
    func __attach(registry: any RegistryOverrideSource) {
        self.registry = registry
    }

    // swiftlint:disable:next identifier_name
    func __notifyOverrideChange(actionID: String) {
        notifyOverrideChange(actionID: actionID)
    }

    // swiftlint:disable:next identifier_name
    func __buildMatcher(coalescer: ContinuousCoalescer) -> any ContextMatching {
        ContextMatcher(context: self, coalescer: coalescer)
    }
}

extension ShortcutContext: ContextActivation {
    // swiftlint:disable identifier_name
    func __activate() { registry?.activateContext(id: id) }
    func __deactivate() { registry?.deactivateContext(id: id) }
    // swiftlint:enable identifier_name
}
