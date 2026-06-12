import AppKit
import Combine
import Foundation
import os.log
import ShortcutField

/// The hub: owns contexts, persistence, conflicts, and routing. `@MainActor`
/// throughout (meta-spec concurrency decision). Contexts always live inside a
/// registry; single-context apps still construct one.
@MainActor
public final class ShortcutRegistry: ObservableObject, RegistryOverrideSource {
    // Public outputs — empty here, populated by Tasks 12 (conflicts) and 15 (table).
    @Published public private(set) var conflicts: [Conflict] = []
    @Published public private(set) var keyBindings: KeyBindings = .init()
    public let actionFired: AnyPublisher<ActionFiredEvent, Never>

    /// Effective hint-visibility state: the user's override if set, else the
    /// app author's `defaultHintsEnabled`. The HUD reads this; the preferences
    /// UI flips it via `setHintsEnabled(_:)`.
    @Published public private(set) var hintsEnabled: Bool = true

    private let defaultHintsEnabled: Bool
    /// `nil` until the user diverges from `defaultHintsEnabled`; persisted then.
    private var hintsEnabledOverride: Bool?

    // Stored for Tasks 7/8/12/15 to consume.
    let contexts: [any AnyShortcutContext]
    let mutuallyExclusiveContexts: [Set<String>]
    let migrations: [ShortcutMigration]
    let store: any ShortcutBindingsStore
    let systemShortcutsProvider: any SystemShortcutsProvider

    static let logger = Logger(
        subsystem: "com.nielsmadan.shortcutkit",
        category: "registry"
    )

    private let actionFiredSubject = PassthroughSubject<ActionFiredEvent, Never>()
    var overrides: [String: [String: [Shortcut]]] = [:]
    private var pendingSave: DispatchWorkItem?
    let router = RegistryEventRouter()
    var matchers: [String: any ContextMatching] = [:]
    let coalescer = ContinuousCoalescer()

    public init(
        contexts: [any AnyShortcutContext],
        mutuallyExclusiveContexts: [Set<String>] = [],
        migrations: [ShortcutMigration] = [],
        store: any ShortcutBindingsStore = UserDefaultsStore(),
        systemShortcutsProvider: any SystemShortcutsProvider = CarbonSystemShortcuts(),
        defaultHintsEnabled: Bool = true
    ) {
        let contextIDs = contexts.map(\.id)
        precondition(
            Set(contextIDs).count == contextIDs.count,
            "ShortcutRegistry: duplicate context IDs in `contexts`: \(contextIDs)."
        )
        precondition(
            !contextIDs.contains("preferences"),
            "ShortcutRegistry: \"preferences\" is a reserved context id (the persisted preferences section)."
        )
        let knownIDs = Set(contextIDs)
        for set in mutuallyExclusiveContexts {
            let unknown = set.subtracting(knownIDs)
            precondition(
                unknown.isEmpty,
                "ShortcutRegistry: `mutuallyExclusiveContexts` references unknown context IDs: \(unknown)."
            )
        }
        self.contexts = contexts
        self.mutuallyExclusiveContexts = mutuallyExclusiveContexts
        // Always prepend the Phase 1.5 wrap-single-bindings breadcrumb; the
        // shape upgrade itself happens at the decoder boundary.
        self.migrations = [WrapSingleBindingsMigration.entry] + migrations
        self.store = store
        self.systemShortcutsProvider = systemShortcutsProvider
        self.defaultHintsEnabled = defaultHintsEnabled
        actionFired = actionFiredSubject.eraseToAnyPublisher()

        for context in contexts {
            attach(context: context)
        }

        // Load — log + reset on corruption.
        var loaded: RawState
        do { loaded = try store.load() } catch {
            Self.logger.error("load failed: \(String(describing: error)); resetting")
            loaded = RawState()
        }

        // Apply migrations; persist only if anything changed.
        let before = loaded
        ShortcutMigrationApplier.apply(migrations, to: &loaded)
        if loaded != before {
            do { try store.save(loaded) } catch {
                Self.logger.error("post-migration save failed: \(String(describing: error))")
            }
        }
        overrides = loaded.overrides
        hintsEnabledOverride = loaded.preferences.hintsEnabled
        hintsEnabled = hintsEnabledOverride ?? defaultHintsEnabled
        reanalyzeConflicts()
        checkDefaultLevelConflicts()
        rebuildKeyBindings()
    }

    /// Set the user's hint-visibility preference. Persists through the store as
    /// an override only when it diverges from `defaultHintsEnabled` (matching how
    /// binding overrides are stored only when customized).
    public func setHintsEnabled(_ value: Bool) {
        hintsEnabledOverride = (value == defaultHintsEnabled) ? nil : value
        hintsEnabled = value
        scheduleSave()
    }

    /// Re-read the store and apply any out-of-band changes (a hand-edited config
    /// file, a sync or restore) to the live registry: bindings, the hint
    /// preference, conflicts, and the published `keyBindings` all refresh, and
    /// subscribers to `shortcutsChanges(for:)` see the new values. Unsaved
    /// in-memory overrides are discarded in favor of the store.
    ///
    /// Returns `true` when the store was re-read and applied, `false` when the
    /// load failed — in which case the error is logged and the current state is
    /// left untouched (unlike `init`, a transient read error doesn't reset state).
    @discardableResult
    public func reload() -> Bool {
        let loaded: RawState
        do { loaded = try store.load() } catch {
            Self.logger.error("reload failed: \(String(describing: error)); keeping current state")
            return false
        }
        let previous = overrides
        overrides = loaded.overrides
        hintsEnabledOverride = loaded.preferences.hintsEnabled
        hintsEnabled = hintsEnabledOverride ?? defaultHintsEnabled

        // Push the new bindings to every action whose effective value could have
        // changed (the union of before/after override keys), then rebuild the
        // live matchers and derived outputs.
        var affected: Set<ActionRef> = []
        for (contextID, perAction) in previous {
            for actionID in perAction.keys {
                affected.insert(.init(contextID: contextID, actionID: actionID))
            }
        }
        for (contextID, perAction) in overrides {
            for actionID in perAction.keys {
                affected.insert(.init(contextID: contextID, actionID: actionID))
            }
        }
        for ref in affected {
            (contexts.first(where: { $0.id == ref.contextID }) as? RegistryAttachable)?
                .__notifyOverrideChange(actionID: ref.actionID)
        }
        for matcher in matchers.values {
            matcher.rebuild()
        }
        reanalyzeConflicts()
        return true
    }

    private func attach(context: any AnyShortcutContext) {
        guard let attachable = context as? RegistryAttachable else { return }
        attachable.__attach(registry: self)
        matchers[context.id] = attachable.__buildMatcher(coalescer: coalescer)
    }

    // MARK: - RegistryOverrideSource

    func overrides(contextID: String, actionID: String) -> [Shortcut]? {
        overrides[contextID]?[actionID]
    }

    func recordActionFired(_ event: ActionFiredEvent) {
        actionFiredSubject.send(event)
    }

    func activateContext(id: String) {
        guard let matcher = matchers[id] else { return }
        router.push(matcher)
    }

    func deactivateContext(id: String) {
        router.remove(contextID: id)
    }

    // MARK: - Assertion seam

    /// Test seam: replace to intercept assertion-trap messages. Production
    /// builds use `Swift.assertionFailure`.
    nonisolated(unsafe) static var assertionFunction: @MainActor (String) -> Void = { message in
        Swift.assertionFailure(message)
    }

    // MARK: - Conflict analysis

    func reanalyzeConflicts() {
        var occurrences: [Occurrence] = []
        for context in contexts {
            if let p = context as? RegistryAttachable {
                occurrences.append(contentsOf: p.__currentOccurrences())
            }
        }
        conflicts = ConflictAnalyzer.analyze(
            bindings: occurrences,
            mutuallyExclusiveContexts: mutuallyExclusiveContexts,
            systemShortcuts: systemShortcutsProvider.currentSystemShortcuts(),
            contextScopes: contextScopes()
        )
        rebuildKeyBindings()
    }

    private func contextScopes() -> [String: ContextScope] {
        var result: [String: ContextScope] = [:]
        for context in contexts {
            result[context.id] = context.scope
        }
        return result
    }

    func rebuildKeyBindings() {
        let byAction = conflictsByActionFQN()
        var groups: [KeyBindings.Group] = []
        for context in contexts {
            guard let p = context as? RegistryAttachable else { continue }
            let entries = p.__currentEntries { actionID in
                byAction["\(context.id).\(actionID)"] ?? []
            }
            groups.append(.init(
                contextID: context.id, displayName: context.displayName, entries: entries
            ))
        }
        keyBindings = .init(groups: groups)
    }

    /// Bindings for every currently-active local context (those pushed onto the
    /// router by `.activeShortcutContext`) plus every `.global`-scoped context.
    /// Adopters who want a specific set use `bindings(for:)`. For a legend /
    /// cheat-sheet, chain `.boundOnly()`.
    public func activeBindings() -> KeyBindings {
        var ids = Set(router.__currentStackIDs)
        for context in contexts where context.scope == .global {
            ids.insert(context.id)
        }
        return bindings(for: ids)
    }

    /// Bindings for the given context IDs, in registration order. Includes
    /// unbound actions; chain `.boundOnly()` for a legend.
    public func bindings(for contextIDs: Set<String>) -> KeyBindings {
        var groups: [KeyBindings.Group] = []
        let byAction = conflictsByActionFQN()
        for context in contexts where contextIDs.contains(context.id) {
            guard let p = context as? RegistryAttachable else { continue }
            let entries = p.__currentEntries { actionID in
                byAction["\(context.id).\(actionID)"] ?? []
            }
            groups.append(.init(
                contextID: context.id, displayName: context.displayName, entries: entries
            ))
        }
        return KeyBindings(groups: groups)
    }

    private func conflictsByActionFQN() -> [String: [Conflict]] {
        var result: [String: [Conflict]] = [:]
        for conflict in conflicts {
            for fqn in touchedActionFQNs(in: conflict) {
                result[fqn, default: []].append(conflict)
            }
        }
        return result
    }

    private func touchedActionFQNs(in conflict: Conflict) -> [String] {
        switch conflict {
        case let .duplicate(occurrences):
            occurrences.map { "\($0.contextID).\($0.actionID)" }
        case let .unreachablePrefix(blocker, blocked):
            ["\(blocker.contextID).\(blocker.actionID)", "\(blocked.contextID).\(blocked.actionID)"]
        case let .systemShared(action):
            ["\(action.contextID).\(action.actionID)"]
        case let .menuCollision(action, _):
            ["\(action.contextID).\(action.actionID)"]
        case let .shadowedByGlobal(local, global):
            ["\(local.contextID).\(local.actionID)", "\(global.contextID).\(global.actionID)"]
        case let .unsupportedInScope(occurrence, _):
            ["\(occurrence.contextID).\(occurrence.actionID)"]
        }
    }

    public func menuCollisions(in menu: NSMenu? = NSApp.mainMenu) -> [Conflict] {
        guard let menu else { return [] }
        let menuShortcuts = MenuShortcutWalker.shortcuts(in: menu)
        var occurrences: [Occurrence] = []
        for context in contexts {
            if let p = context as? RegistryAttachable {
                occurrences.append(contentsOf: p.__currentOccurrences())
            }
        }
        var collisions: [Conflict] = []
        for occurrence in occurrences {
            guard case let .discrete(d) = occurrence.shortcut,
                  d.steps.count == 1,
                  case let .key(keyCode) = d.steps[0].kind else { continue }
            let key = SystemHotKey(keyCode: keyCode, modifiers: d.steps[0].modifiers)
            if let title = menuShortcuts[key] {
                collisions.append(.menuCollision(action: occurrence, menuItemTitle: title))
            }
        }
        return collisions
    }

    func checkDefaultLevelConflicts() {
        var occurrences: [Occurrence] = []
        for context in contexts {
            if let p = context as? RegistryAttachable {
                occurrences.append(contentsOf: p.__defaultOccurrences())
            }
        }
        let defaultConflicts = ConflictAnalyzer.analyze(
            bindings: occurrences,
            mutuallyExclusiveContexts: mutuallyExclusiveContexts,
            contextScopes: contextScopes()
        )
        let errors = defaultConflicts.filter { $0.severity == .error }
        guard !errors.isEmpty else { return }
        let descriptions = errors.map(Self.describeConflict).joined(separator: "; ")
        Self.assertionFunction("ShortcutKit: default-level conflicts: \(descriptions)")
    }

    private static func describeConflict(_ conflict: Conflict) -> String {
        switch conflict {
        case let .duplicate(occurrences):
            let label = occurrences.map { "\($0.contextID).\($0.actionID)" }.joined(separator: " / ")
            return "duplicate trigger across [\(label)]"
        case let .unreachablePrefix(blocker, blocked):
            return "[\(blocker.contextID).\(blocker.actionID)] blocks prefix of [\(blocked.contextID).\(blocked.actionID)]"
        case let .systemShared(action):
            return "system collision on [\(action.contextID).\(action.actionID)]"
        case let .menuCollision(action, _):
            return "menu collision on [\(action.contextID).\(action.actionID)]"
        case let .shadowedByGlobal(local, global):
            return "[\(global.contextID).\(global.actionID)] shadows [\(local.contextID).\(local.actionID)]"
        case let .unsupportedInScope(occurrence, reason):
            return "[\(occurrence.contextID).\(occurrence.actionID)] unsupported in scope (\(reason))"
        }
    }

    // MARK: - Debounced save

    func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.flushSave() }
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.250, execute: work)
    }

    private func flushSave() {
        pendingSave = nil
        do {
            try store.save(RawState(
                overrides: overrides,
                preferences: Preferences(hintsEnabled: hintsEnabledOverride)
            ))
        } catch {
            // Best-effort; Task 7 adds os.Logger wiring.
        }
    }

    /// Synchronously persist any pending override changes, bypassing the 250 ms
    /// debounce. Use when you need the on-disk state stable before a follow-up
    /// step (an export-to-file flow, a profile switch, an explicit "Save" button).
    /// A no-op if no save is pending.
    public func flushPendingSave() {
        pendingSave?.cancel()
        pendingSave = nil
        flushSave()
    }

    // swiftlint:disable identifier_name
    /// Test seam — back-compat alias for `flushPendingSave()`.
    func __flushPendingSave() {
        flushPendingSave()
    }

    /// Test hook: the active context IDs in router order (outer → innermost).
    var __activeContextIDs: [String] {
        router.__currentStackIDs
    }

    /// Test hook: the underlying router so tests can drive `handle(_:)` directly.
    var __router: RegistryEventRouter { router }
    // swiftlint:enable identifier_name
}

// swiftlint:disable identifier_name
/// Internal protocol the concrete `ShortcutContext<Action>` implements so the
/// registry can wire its `registry` ref without seeing the generic parameter.
@MainActor protocol RegistryAttachable: AnyObject {
    func __attach(registry: any RegistryOverrideSource)
    func __notifyOverrideChange(actionID: String)
    func __buildMatcher(coalescer: ContinuousCoalescer) -> any ContextMatching
    func __currentOccurrences() -> [Occurrence]
    func __defaultOccurrences() -> [Occurrence]
    func __currentEntries(conflictsForAction: (String) -> [Conflict]) -> [KeyBindings.Entry]
    func __dispatchFromMatcher(actionID: String)
    func __dispatchProgrammatic(actionID: String) -> Bool
    func __notifyProgrammatic(actionID: String) -> Bool
}

// swiftlint:enable identifier_name
