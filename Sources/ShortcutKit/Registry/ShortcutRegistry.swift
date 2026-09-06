import AppKit
import Combine
import Foundation
import os.log
import ShortcutField

/// Owns shortcut contexts, persistence, conflict analysis, and event routing.
@MainActor
public final class ShortcutRegistry: ObservableObject, RegistryOverrideSource {
    /// Opaque, migration-prepared registry state ready for an infallible live swap.
    public struct PreparedState: Sendable {
        fileprivate let rawState: RawState
    }

    /// A prepared state and its optional migrated persistence representation.
    public struct Preparation: Sendable {
        public let preparedState: PreparedState
        public let persistenceWriteback: RawState?

        public var requiresPersistenceWriteback: Bool { persistenceWriteback != nil }
    }

    @Published public private(set) var conflicts: [Conflict] = []
    @Published public private(set) var keyBindings: KeyBindings = .init()
    public let actionFired: AnyPublisher<ActionFiredEvent, Never>
    /// Emits after each registry-initiated store write succeeds or fails.
    public let saveResults: AnyPublisher<ShortcutSaveResult, Never>

    /// Per-keystroke outcomes, for answering "why didn't my shortcut fire".
    ///
    /// Emits only while ``isDebugRecording`` is `true`. Nothing is stored — keep
    /// whatever history you need on the observing side.
    ///
    /// Key events routed through active contexts only: global (Carbon) hotkeys
    /// bypass the router, and with no context active the router is unregistered
    /// and there is nothing to observe. An empty ``activationSnapshot`` is the
    /// explanation for a silent stream.
    public let debugEvents: AnyPublisher<ShortcutDebugEvent, Never>

    /// Whether ``debugEvents`` is emitting. `false` by default; while off the
    /// event path pays a single optional test per keystroke.
    public var isDebugRecording: Bool = false {
        didSet {
            guard isDebugRecording != oldValue else { return }
            router.onDebugEvent = isDebugRecording
                ? { [weak self] event in self?.debugEventSubject.send(event) }
                : nil
        }
    }

    /// The live activation stack, in router order — outermost first, duplicates
    /// preserved. Unlike ``activeBindings()`` this keeps what decides precedence.
    public var activationSnapshot: ActivationSnapshot {
        let byID = Dictionary(
            contexts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }
        )
        return ActivationSnapshot(entries: router.activationOrder.compactMap { entry in
            guard let context = byID[entry.contextID] else { return nil }
            return ActivationSnapshot.Entry(
                activationID: entry.activationID,
                contextID: entry.contextID,
                displayName: context.displayName,
                scope: context.scope
            )
        })
    }

    /// The user's hint-visibility override, or the app default when unset.
    @Published public private(set) var hintsEnabled: Bool = true

    private let defaultHintsEnabled: Bool
    private var hintsEnabledOverride: Bool?

    /// The user's hint-frequency override, or the app default when unset.
    @Published public private(set) var hintFrequency: HintPolicy = .oncePerSession

    /// The app's default hint frequency.
    public let defaultHintFrequency: HintPolicy
    private var hintFrequencyOverride: HintPolicy?

    let contexts: [AnyShortcutContext]
    let mutuallyExclusiveContexts: [Set<String>]
    let migrations: [ShortcutMigration]
    let store: any ShortcutBindingsStore
    let systemShortcutsProvider: any SystemShortcutsProvider

    static let logger = Logger(
        subsystem: "com.nielsmadan.shortcutkit",
        category: "registry"
    )

    private let actionFiredSubject = PassthroughSubject<ActionFiredEvent, Never>()
    private let debugEventSubject = PassthroughSubject<ShortcutDebugEvent, Never>()
    private let saveResultSubject = PassthroughSubject<ShortcutSaveResult, Never>()
    var overrides: [String: [String: [Shortcut]]] = [:]
    private var pendingSave: DispatchWorkItem?
    private var hasUnsavedChanges = false
    let router = RegistryEventRouter()
    var matchers: [String: any ContextMatching] = [:]
    var activeMatchers: [UUID: any ContextMatching] = [:]
    let coalescer = ContinuousCoalescer()

    public init(
        contexts: [AnyShortcutContext],
        mutuallyExclusiveContexts: [Set<String>] = [],
        migrations: [ShortcutMigration] = [],
        store: any ShortcutBindingsStore = UserDefaultsStore(),
        systemShortcutsProvider: any SystemShortcutsProvider = CarbonSystemShortcuts(),
        defaultHintsEnabled: Bool = true,
        defaultHintFrequency: HintPolicy = .oncePerSession
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
        self.migrations = [WrapSingleBindingsMigration.entry] + migrations
        self.store = store
        self.systemShortcutsProvider = systemShortcutsProvider
        self.defaultHintsEnabled = defaultHintsEnabled
        self.defaultHintFrequency = defaultHintFrequency
        actionFired = actionFiredSubject.eraseToAnyPublisher()
        debugEvents = debugEventSubject.eraseToAnyPublisher()
        saveResults = saveResultSubject.eraseToAnyPublisher()

        // Overrides can introduce multi-step bindings after initialization.
        ShortcutTracking.installBeepSuppression()

        for context in contexts {
            attach(context: context)
        }

        let preparation: Preparation
        do {
            preparation = try Self.makePreparation(store.load(), migrations: self.migrations)
        } catch {
            Self.logger.error("load or migration failed: \(String(describing: error)); resetting")
            preparation = .init(preparedState: .init(rawState: RawState()), persistenceWriteback: nil)
        }
        if let writeback = preparation.persistenceWriteback {
            do { try store.save(writeback) } catch {
                Self.logger.error("post-migration save failed: \(String(describing: error))")
                hasUnsavedChanges = true
            }
        }
        let loaded = preparation.preparedState.rawState
        overrides = loaded.overrides
        hintsEnabledOverride = loaded.preferences.hintsEnabled
        hintsEnabled = hintsEnabledOverride ?? defaultHintsEnabled
        hintFrequencyOverride = loaded.preferences.hintFrequency
        hintFrequency = hintFrequencyOverride ?? defaultHintFrequency
        refreshDerivedState()
        checkDefaultLevelConflicts()
    }

    /// Applies the registry's migration sequence without changing live state.
    public func prepare(_ state: RawState) throws -> Preparation {
        try Self.makePreparation(state, migrations: migrations)
    }

    /// Applies a migration sequence without constructing or changing a registry.
    public static func prepare(
        _ state: RawState,
        migrations: [ShortcutMigration] = []
    ) throws -> Preparation {
        try makePreparation(state, migrations: [WrapSingleBindingsMigration.entry] + migrations)
    }

    /// Applies prepared state after every pending mutation has been persisted.
    public func commit(_ preparedState: PreparedState) {
        precondition(
            !hasUnsavedChanges,
            "ShortcutRegistry.commit requires pending changes to be flushed or explicitly discarded."
        )
        apply(preparedState)
    }

    /// Discards a failed pending mutation and restores a prepared valid state.
    public func discardPendingSave(applying preparedState: PreparedState) {
        pendingSave?.cancel()
        pendingSave = nil
        hasUnsavedChanges = false
        apply(preparedState)
    }

    /// Sets the user's hint-visibility preference.
    ///
    /// The store retains an override only while it differs from the app default.
    public func setHintsEnabled(_ value: Bool) {
        hintsEnabledOverride = (value == defaultHintsEnabled) ? nil : value
        hintsEnabled = value
        scheduleSave()
    }

    /// Sets the user's hint-frequency preference.
    ///
    /// The store retains an override only while it differs from the app default.
    public func setHintFrequency(_ value: HintPolicy) {
        hintFrequencyOverride = (value == defaultHintFrequency) ? nil : value
        hintFrequency = value
        scheduleSave()
    }

    /// Reloads out-of-band store changes and refreshes bindings, hint preferences,
    /// conflicts, `keyBindings`, and binding publishers.
    ///
    /// Pending changes are flushed first. On failure, the current state and any
    /// unsaved changes are retained and the method returns `false`.
    @discardableResult
    public func reload() -> Bool {
        guard flushPendingSave() else { return false }
        let preparation: Preparation
        do {
            preparation = try prepare(store.load())
        } catch {
            Self.logger.error("reload or migration failed: \(String(describing: error)); keeping current state")
            return false
        }

        var writebackResult: ShortcutSaveResult?
        if let writeback = preparation.persistenceWriteback {
            do {
                try store.save(writeback)
                writebackResult = .saved(writeback)
            } catch {
                writebackResult = .failed(writeback, error)
            }
        }
        commit(preparation.preparedState)
        if case .failed = writebackResult {
            hasUnsavedChanges = true
        }
        if let writebackResult {
            saveResultSubject.send(writebackResult)
        }
        return true
    }

    private static func makePreparation(
        _ state: RawState,
        migrations: [ShortcutMigration]
    ) throws -> Preparation {
        var migrated = state
        try ShortcutMigrationApplier.apply(migrations, to: &migrated)
        return .init(
            preparedState: .init(rawState: migrated),
            persistenceWriteback: migrated == state ? nil : migrated
        )
    }

    private func apply(_ preparedState: PreparedState) {
        let previous = currentRawState
        let next = preparedState.rawState
        let affected = Self.changedActions(from: previous.overrides, to: next.overrides)

        overrides = next.overrides
        hintsEnabledOverride = next.preferences.hintsEnabled
        hintFrequencyOverride = next.preferences.hintFrequency
        let nextHintsEnabled = hintsEnabledOverride ?? defaultHintsEnabled
        let nextHintFrequency = hintFrequencyOverride ?? defaultHintFrequency
        if hintsEnabled != nextHintsEnabled { hintsEnabled = nextHintsEnabled }
        if hintFrequency != nextHintFrequency { hintFrequency = nextHintFrequency }

        notifyChanges(affected)
    }

    private static func changedActions(
        from previous: [String: [String: [Shortcut]]],
        to next: [String: [String: [Shortcut]]]
    ) -> Set<ActionRef> {
        var affected: Set<ActionRef> = []
        let contextIDs = Set(previous.keys).union(next.keys)
        for contextID in contextIDs {
            let oldActions = previous[contextID] ?? [:]
            let newActions = next[contextID] ?? [:]
            for actionID in Set(oldActions.keys).union(newActions.keys)
                where oldActions[actionID] != newActions[actionID]
            {
                affected.insert(.init(contextID: contextID, actionID: actionID))
            }
        }
        return affected
    }

    private var currentRawState: RawState {
        RawState(
            overrides: overrides,
            preferences: Preferences(
                hintsEnabled: hintsEnabledOverride,
                hintFrequency: hintFrequencyOverride
            )
        )
    }

    private func attach(context: AnyShortcutContext) {
        guard let attachable = context as? RegistryAttachable else { return }
        precondition(
            attachable.__attach(registry: self),
            "ShortcutRegistry: context '\(context.id)' is already attached to another registry."
        )
        matchers[context.id] = attachable.__buildMatcher(coalescer: coalescer, activationID: nil)
    }

    // MARK: - RegistryOverrideSource

    func overrides(contextID: String, actionID: String) -> [Shortcut]? {
        overrides[contextID]?[actionID]
    }

    func recordActionFired(_ event: ActionFiredEvent) {
        actionFiredSubject.send(event)
    }

    func activateContext(id: String, activationID: UUID) {
        guard let context = contexts.first(where: { $0.id == id }) as? RegistryAttachable else { return }
        if activeMatchers[activationID] != nil {
            router.remove(activationID: activationID)
        }
        let matcher = context.__buildMatcher(coalescer: coalescer, activationID: activationID)
        activeMatchers[activationID] = matcher
        router.push(matcher)
    }

    func deactivateContext(activationID: UUID) {
        activeMatchers[activationID] = nil
        router.remove(activationID: activationID)
    }

    // MARK: - Assertion seam

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
    }

    func refreshDerivedState() {
        reanalyzeConflicts()
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
        let byAction = conflictsByActionRef()
        var groups: [KeyBindings.Group] = []
        for context in contexts {
            guard let p = context as? RegistryAttachable else { continue }
            let entries = p.__currentEntries { actionID in
                byAction[ActionRef(contextID: context.id, actionID: actionID)] ?? []
            }
            groups.append(.init(
                contextID: context.id, displayName: context.displayName, entries: entries
            ))
        }
        keyBindings = .init(groups: groups)
    }

    /// Bindings for active local contexts and every global context.
    ///
    /// Chain `.boundOnly()` when unbound actions should be omitted.
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
        let byAction = conflictsByActionRef()
        for context in contexts where contextIDs.contains(context.id) {
            guard let p = context as? RegistryAttachable else { continue }
            let entries = p.__currentEntries { actionID in
                byAction[ActionRef(contextID: context.id, actionID: actionID)] ?? []
            }
            groups.append(.init(
                contextID: context.id, displayName: context.displayName, entries: entries
            ))
        }
        return KeyBindings(groups: groups)
    }

    private func conflictsByActionRef() -> [ActionRef: [Conflict]] {
        var result: [ActionRef: [Conflict]] = [:]
        for conflict in conflicts {
            let refs = Set(conflict.occurrences.map {
                ActionRef(contextID: $0.contextID, actionID: $0.actionID)
            })
            for ref in refs {
                result[ref, default: []].append(conflict)
            }
        }
        return result
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
        case let .layoutExclusiveKey(occurrence, layout):
            return "[\(occurrence.contextID).\(occurrence.actionID)] uses a \(layout)-only key"
        }
    }

    // MARK: - Debounced save

    func scheduleSave() {
        pendingSave?.cancel()
        hasUnsavedChanges = true
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.savePendingChanges() }
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.250, execute: work)
    }

    @discardableResult
    private func savePendingChanges() -> Bool {
        guard hasUnsavedChanges else { return true }
        let state = currentRawState
        do {
            try store.save(state)
            hasUnsavedChanges = false
            pendingSave = nil
            saveResultSubject.send(.saved(state))
            return true
        } catch {
            pendingSave = nil
            saveResultSubject.send(.failed(state, error))
            Self.logger.error("save failed: \(String(describing: error))")
            return false
        }
    }

    /// Whether the registry has a mutation that has not reached its store.
    public var hasPendingSave: Bool { hasUnsavedChanges }

    /// Persists pending changes immediately, bypassing the 250 ms debounce.
    /// Returns `false` when saving fails; the changes remain pending for retry.
    @discardableResult
    public func flushPendingSave() -> Bool {
        guard hasUnsavedChanges else { return true }
        pendingSave?.cancel()
        pendingSave = nil
        return savePendingChanges()
    }

    // swiftlint:disable identifier_name
    var __activeContextIDs: [String] {
        router.__currentStackIDs
    }

    var __router: RegistryEventRouter { router }
    // swiftlint:enable identifier_name
}

// swiftlint:disable identifier_name
@MainActor protocol RegistryAttachable: AnyObject {
    func __attach(registry: any RegistryOverrideSource) -> Bool
    func __notifyOverrideChange(actionID: String)
    func __buildMatcher(coalescer: ContinuousCoalescer, activationID: UUID?) -> any ContextMatching
    func __currentOccurrences() -> [Occurrence]
    func __defaultOccurrences() -> [Occurrence]
    func __currentEntries(conflictsForAction: (String) -> [Conflict]) -> [KeyBindings.Entry]
    func __dispatchFromMatcher(actionID: String)
    func __dispatchProgrammatic(actionID: String) -> Bool
    func __notifyProgrammatic(actionID: String) -> Bool
}

// swiftlint:enable identifier_name
