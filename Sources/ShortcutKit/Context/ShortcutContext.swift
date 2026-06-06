import Combine
import Foundation
import ShortcutField

/// Activation scope for a context. `.local` contexts only fire while activated
/// via `.activeShortcutContext`; `.global` contexts are always candidates for
/// system-wide hotkey registration (Phase 3 consumes this).
public enum ContextScope: Sendable, Hashable { case local, global }

/// Type-erased context so a registry can hold a heterogeneous list. Public for
/// the registry's `contexts:` parameter; the package-internal surface drives
/// activation and override notifications (see same-package extensions).
@MainActor public protocol AnyShortcutContext: AnyObject {
    var id: String { get }
    var scope: ContextScope { get }
    var includeInSettings: Bool { get }

    /// Human-facing context name shown in settings pickers and legends.
    /// Resolves to an explicit value if the adopter set one, otherwise a
    /// title-cased rendering of `id` (e.g. `"canvas.shared"` → `"Canvas / Shared"`).
    var displayName: LocalizedStringResource { get }
}

/// Title-cases a context `id` for display when no explicit `displayName` is
/// set. Splits on `.` so a dotted id like `canvas.shared` becomes
/// `Canvas / Shared`; the id is the stable persistence key, so adopters
/// shouldn't bake display strings into it.
func deriveContextDisplayName(fromID id: String) -> String {
    id.split(separator: ".")
        .map { segment -> String in
            let s = String(segment)
            guard let first = s.first else { return s }
            return first.uppercased() + s.dropFirst()
        }
        .joined(separator: " / ")
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
    /// Stable persistence key for this context. Immutable (`let`): overrides are
    /// stored under this id forever, so renaming it would orphan persisted data —
    /// go through a declared migration instead. Not user-facing; see `displayName`.
    public let id: String

    /// Activation scope, fixed at construction (`.local` via `init(_:)`, `.global`
    /// via `init(global:dispatch:)`). Immutable (`let`): scope determines the
    /// activation mechanism and allowed grammar, so it can't change after the
    /// context is built.
    public let scope: ContextScope

    /// Whether `KeyBindingsView`'s settings UI lists this context. Read at render
    /// time but **not** `@Published`: mutating it at runtime won't refresh a live
    /// `KeyBindingsView` picker. Treat it as a construction-time choice; if you
    /// need it to flip reactively, drive visibility from your own observable state.
    public var includeInSettings: Bool

    /// Explicit adopter-set name, or `nil` to fall back to a title-cased `id`.
    private let displayNameOverride: LocalizedStringResource?

    public var displayName: LocalizedStringResource {
        displayNameOverride ?? LocalizedStringResource(stringLiteral: deriveContextDisplayName(fromID: id))
    }

    /// `.global` contexts set this at init (required — system-wide hotkeys
    /// must work whether or not any view is mounted). `.local` contexts leave
    /// it `nil` and supply their handler at `.activeShortcutContext(_:dispatch:)`
    /// time.
    private let globalDispatchClosure: (@MainActor (Action, ShortcutDispatch) -> Void)?

    /// The currently-active handler set by `.activeShortcutContext(_:dispatch:)`.
    /// Set on view appear, cleared on view disappear. Only meaningful for `.local`
    /// contexts; `.global` contexts ignore this and use `globalDispatchClosure`.
    private var activeHandler: (@MainActor (Action, ShortcutDispatch) -> Void)?

    /// One subject per observed action, holding the full bindings array.
    private var changeSubjects: [String: CurrentValueSubject<[Shortcut], Never>] = [:]

    // Set by the registry when this context is added. Not exposed publicly.
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

    /// Adopter-driven dispatch. Invokes the handler with the kind that matches
    /// the action's declared kind (`.discrete` for discrete actions,
    /// `.continuous(magnitude: 1.0)` for continuous ones — "fire once"
    /// programmatic semantics), then emits `actionFired` with `source: .programmatic`.
    /// No-op if no handler is currently bound (local context not activated; global
    /// context without dispatch — though the latter is unreachable by construction).
    ///
    /// Note for continuous actions: a real gesture streams many ticks with varying
    /// magnitudes (and a terminal `.continuous(magnitude: 0)`); `dispatch(_:)` sends
    /// exactly one tick at magnitude `1.0`. It exists for tests and macro/replay,
    /// not to simulate a live gesture — production continuous input arrives through
    /// the matcher path, not here.
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

    /// Adopter-driven notify. Emits `actionFired` only; handler is not called.
    public func notify(_ action: Action) {
        registry?.recordActionFired(.init(
            contextID: id, actionID: action.rawValue, source: .programmatic
        ))
    }

    /// Route to whichever handler is currently in scope: a view-bound
    /// `activeHandler` for `.local` contexts, or the construction-time
    /// `globalDispatchClosure` for `.global`. No-op if neither is set.
    private func invokeHandler(_ action: Action, kind: ShortcutDispatch) {
        if let handler = activeHandler {
            handler(action, kind)
        } else if let handler = globalDispatchClosure {
            handler(action, kind)
        }
        // else: shortcut fired but no handler bound — silent no-op.
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

    /// Called by `ContextMatcher` after a matcher-driven match. Invokes the
    /// currently-bound handler with the supplied `kind` and emits `actionFired`
    /// with `source: .shortcut`. The matcher is only on the stack when the
    /// context is activated, so for `.local` contexts a handler is guaranteed
    /// present here. `.global` contexts always have one.
    func dispatchFromMatcher(_ action: Action, kind: ShortcutDispatch) {
        invokeHandler(action, kind: kind)
        registry?.recordActionFired(.init(
            contextID: id, actionID: action.rawValue, source: .shortcut
        ))
    }

    // swiftlint:disable identifier_name

    /// Test seam + internal modifier hook — set the view-bound handler that
    /// `.activeShortcutContext(_:dispatch:)` provides.
    func __setActiveHandler(_ handler: @escaping @MainActor (Action, ShortcutDispatch) -> Void) {
        activeHandler = handler
    }

    /// Test seam + internal modifier hook — clear the view-bound handler.
    func __clearActiveHandler() {
        activeHandler = nil
    }

    // swiftlint:enable identifier_name

    /// Called by the registry when an override changes for this context.
    /// Pushes the new effective bindings array through `shortcutsChanges(for:)`
    /// (and via derivation, `shortcutChanges(for:)`).
    func notifyOverrideChange(actionID: String) {
        guard let subject = changeSubjects[actionID] else { return }
        guard let action = Action.allCases.first(where: { $0.rawValue == actionID })
        else { return }
        subject.send(shortcuts(for: action))
    }
}

/// Internal abstraction the registry conforms to so `ShortcutContext` can
/// look up overrides without a concrete reference to `ShortcutRegistry`.
/// Declared here so test doubles can stand in for the registry.
@MainActor protocol RegistryOverrideSource: AnyObject {
    func overrides(contextID: String, actionID: String) -> [Shortcut]?
    func setShortcuts(_ shortcuts: [Shortcut], contextID: String, actionID: String)
    func reset(contextID: String, actionID: String)
    func resetAll(contextID: String)
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
    /// Typed back-reference to the registry this context was attached to, if any.
    /// Used by `ShortcutKitUI` inline mode to invoke the type-erased override
    /// helpers (`setShortcuts(_:contextID:actionID:)` etc.) without requiring
    /// adopters to pass the registry alongside the context.
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
