import Combine
import Foundation
import ShortcutField

/// Activation scope for a context.
///
/// Local contexts fire only while activated with `.activeShortcutContext`.
/// Global contexts are candidates for system-wide hotkey registration.
public enum ContextScope: Sendable, Hashable { case local, global }

/// A type-erased shortcut context accepted by `ShortcutRegistry`.
@MainActor public protocol AnyShortcutContext: AnyObject {
    var id: String { get }
    var scope: ContextScope { get }
    var includeInSettings: Bool { get }

    /// Human-facing context name shown in settings pickers and legends.
    /// Resolves to an explicit value if the adopter set one, otherwise a
    /// title-cased rendering of `id` (e.g. `"canvas.shared"` → `"Canvas / Shared"`).
    var displayName: LocalizedStringResource { get }
}

func deriveContextDisplayName(fromID id: String) -> String {
    id.split(separator: ".")
        .map { segment -> String in
            let s = String(segment)
            guard let first = s.first else { return s }
            return first.uppercased() + s.dropFirst()
        }
        .joined(separator: " / ")
}

/// A named group of actions with a shared dispatch closure.
///
/// Before the context is added to a registry, lookups return declared defaults
/// and `isCustomized(_:)` returns `false`.
@MainActor
public final class ShortcutContext<Action: ShortcutAction>: AnyShortcutContext {
    /// Stable persistence key. Rename it only through a declared migration.
    public let id: String

    /// Activation scope, fixed at construction.
    public let scope: ContextScope

    /// Whether `KeyBindingsView` lists this context.
    ///
    /// This value is not published; treat it as a construction-time choice.
    public var includeInSettings: Bool

    private let displayNameOverride: LocalizedStringResource?

    public var displayName: LocalizedStringResource {
        displayNameOverride ?? LocalizedStringResource(stringLiteral: deriveContextDisplayName(fromID: id))
    }

    private let globalDispatchClosure: (@MainActor (Action, ShortcutDispatch) -> Void)?

    private var activeHandler: (@MainActor (Action, ShortcutDispatch) -> Void)?

    private var changeSubjects: [String: CurrentValueSubject<[Shortcut], Never>] = [:]

    weak var registry: (any RegistryOverrideSource)?

    /// Local context. Handler is supplied at `.activeShortcutContext(_:dispatch:)`;
    /// firing a shortcut while no view has activated the context is a no-op.
    /// `displayName` defaults to a title-cased rendering of `id`.
    public init(
        _ id: String,
        displayName: LocalizedStringResource? = nil,
        includeInSettings: Bool = true
    ) {
        self.id = id
        scope = .local
        displayNameOverride = displayName
        self.includeInSettings = includeInSettings
        globalDispatchClosure = nil
    }

    /// Global context — registered system-wide via Carbon. Handler runs whenever
    /// the OS routes the shortcut to this app, regardless of view state, so it
    /// must be provided at construction. Use `ShortcutKitGlobal`'s
    /// `CarbonGlobalActivator` to activate.
    public init(
        global id: String,
        displayName: LocalizedStringResource? = nil,
        includeInSettings: Bool = true,
        dispatch: @escaping @MainActor (Action, ShortcutDispatch) -> Void
    ) {
        self.id = id
        scope = .global
        displayNameOverride = displayName
        self.includeInSettings = includeInSettings
        globalDispatchClosure = dispatch
    }

    // MARK: - Invocation

    /// Dispatches an action programmatically and emits an `actionFired` event.
    ///
    /// This is a no-op when no local handler is active. Discrete actions receive
    /// `.discrete`; continuous actions receive one tick at magnitude `1.0`.
    ///
    /// This does not simulate a continuous gesture stream, including its terminal
    /// zero-magnitude event.
    public func dispatch(_ action: Action) {
        let dispatchKind: ShortcutDispatch = switch action.definition.kind {
        case .discrete: .discrete
        case .continuous: .continuous(magnitude: 1.0)
        }
        invokeHandler(action, kind: dispatchKind)
        registry?.recordActionFired(.init(
            contextID: id, actionID: action.rawValue, source: .programmatic
        ))
    }

    /// Emits an `actionFired` event without invoking the action's handler.
    public func notify(_ action: Action) {
        registry?.recordActionFired(.init(
            contextID: id, actionID: action.rawValue, source: .programmatic
        ))
    }

    private func invokeHandler(_ action: Action, kind: ShortcutDispatch) {
        if let handler = activeHandler {
            handler(action, kind)
        } else if let handler = globalDispatchClosure {
            handler(action, kind)
        }
    }

    // MARK: - Lookup

    public func shortcuts(for action: Action) -> [Shortcut] {
        if let overrides = registry?.overrides(contextID: id, actionID: action.rawValue) {
            return overrides
        }
        return action.definition.defaultShortcuts
    }

    /// Display strings for every binding, in slot order (primary first).
    /// Empty if `action` has no effective bindings.
    public func displayStrings(for action: Action) -> [String] {
        shortcuts(for: action).map(\.displayString)
    }

    public func isCustomized(_ action: Action) -> Bool {
        registry?.overrides(contextID: id, actionID: action.rawValue) != nil
    }

    // MARK: - Override mutation

    /// Set (replace) the override bindings for one action in this context.
    public func setShortcuts(_ shortcuts: [Shortcut], for action: Action) {
        registry?.setShortcuts(shortcuts, contextID: id, actionID: action.rawValue)
    }

    /// Reset one action to its declared defaults.
    public func reset(_ action: Action) {
        registry?.reset(contextID: id, actionID: action.rawValue)
    }

    /// Reset every action in this context to its declared defaults.
    public func resetAll() {
        registry?.resetAll(contextID: id)
    }

    /// Publisher that emits the action's current bindings whenever they change
    /// (defaults applied, override set/cleared/reset). Replays the current
    /// value on subscribe. For primary-only consumers, chain `.map(\.first)`.
    public func shortcutsChanges(for action: Action) -> AnyPublisher<[Shortcut], Never> {
        subject(for: action).eraseToAnyPublisher()
    }

    private func subject(for action: Action) -> CurrentValueSubject<[Shortcut], Never> {
        let key = action.rawValue
        if let existing = changeSubjects[key] {
            return existing
        }
        let fresh = CurrentValueSubject<[Shortcut], Never>(shortcuts(for: action))
        changeSubjects[key] = fresh
        return fresh
    }

    // MARK: - Internal hooks (called by the registry)

    func dispatchFromMatcher(_ action: Action, kind: ShortcutDispatch) {
        invokeHandler(action, kind: kind)
        registry?.recordActionFired(.init(
            contextID: id, actionID: action.rawValue, source: .shortcut
        ))
    }

    // swiftlint:disable identifier_name

    func __setActiveHandler(_ handler: @escaping @MainActor (Action, ShortcutDispatch) -> Void) {
        activeHandler = handler
    }

    func __clearActiveHandler() {
        activeHandler = nil
    }

    // swiftlint:enable identifier_name

    func notifyOverrideChange(actionID: String) {
        guard let subject = changeSubjects[actionID] else { return }
        guard let action = Action.allCases.first(where: { $0.rawValue == actionID })
        else { return }
        subject.send(shortcuts(for: action))
    }
}

@MainActor protocol RegistryOverrideSource: AnyObject {
    func overrides(contextID: String, actionID: String) -> [Shortcut]?
    func setShortcuts(_ shortcuts: [Shortcut], contextID: String, actionID: String)
    func reset(contextID: String, actionID: String)
    func resetAll(contextID: String)
    func recordActionFired(_ event: ActionFiredEvent)
    func activateContext(id: String)
    func deactivateContext(id: String)
}

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

    // swiftlint:disable:next identifier_name
    func __currentOccurrences() -> [Occurrence] {
        Action.allCases.flatMap { action -> [Occurrence] in
            self.shortcuts(for: action).map {
                Occurrence(contextID: id, actionID: action.rawValue, shortcut: $0)
            }
        }
    }

    // swiftlint:disable:next identifier_name
    func __defaultOccurrences() -> [Occurrence] {
        Action.allCases.flatMap { action -> [Occurrence] in
            action.definition.defaultShortcuts.map { shortcut in
                Occurrence(contextID: id, actionID: action.rawValue, shortcut: shortcut)
            }
        }
    }

    // swiftlint:disable:next identifier_name
    func __dispatchFromMatcher(actionID: String) {
        guard let action = Action.allCases.first(where: { $0.rawValue == actionID })
        else { return }
        dispatchFromMatcher(action, kind: .discrete)
    }

    // swiftlint:disable:next identifier_name
    func __dispatchProgrammatic(actionID: String) -> Bool {
        guard let action = Action.allCases.first(where: { $0.rawValue == actionID })
        else { return false }
        dispatch(action)
        return true
    }

    // swiftlint:disable:next identifier_name
    func __notifyProgrammatic(actionID: String) -> Bool {
        guard let action = Action.allCases.first(where: { $0.rawValue == actionID })
        else { return false }
        notify(action)
        return true
    }

    // swiftlint:disable:next identifier_name
    func __currentEntries(
        conflictsForAction: (String) -> [Conflict]
    ) -> [KeyBindings.Entry] {
        Action.allCases.map { action in
            KeyBindings.Entry(
                contextID: id,
                actionID: action.rawValue,
                displayName: action.definition.displayName,
                description: action.definition.description,
                kind: action.definition.kind,
                effectiveShortcuts: shortcuts(for: action),
                isCustomized: isCustomized(action),
                conflicts: conflictsForAction(action.rawValue)
            )
        }
    }
}

package extension ShortcutContext {
    var attachedRegistry: ShortcutRegistry? {
        registry as? ShortcutRegistry
    }
}

extension ShortcutContext: ContextActivation {
    // swiftlint:disable identifier_name
    func __activate() { registry?.activateContext(id: id) }
    func __deactivate() { registry?.deactivateContext(id: id) }
    // swiftlint:enable identifier_name
}
