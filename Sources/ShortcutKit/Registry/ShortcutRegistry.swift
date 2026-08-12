import AppKit
import Combine
import Foundation
import os.log
import ShortcutField

/// Owns shortcut contexts, persistence, conflict analysis, and event routing.
@MainActor
public final class ShortcutRegistry: ObservableObject, RegistryOverrideSource {
    @Published public private(set) var conflicts: [Conflict] = []
    @Published public private(set) var keyBindings: KeyBindings = .init()
    public let actionFired: AnyPublisher<ActionFiredEvent, Never>

    /// The user's hint-visibility override, or the app default when unset.
    @Published public private(set) var hintsEnabled: Bool = true

    private let defaultHintsEnabled: Bool
    private var hintsEnabledOverride: Bool?

    /// The user's hint-frequency override, or the app default when unset.
    @Published public private(set) var hintFrequency: HintPolicy = .oncePerSession

    /// The app's default hint frequency.
    public let defaultHintFrequency: HintPolicy
    private var hintFrequencyOverride: HintPolicy?

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
    var activeMatchers: [UUID: any ContextMatching] = [:]
    let coalescer = ContinuousCoalescer()

    public init(
        contexts: [any AnyShortcutContext],
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

        // Overrides can introduce multi-step bindings after initialization.
        ShortcutTracking.installBeepSuppression()

        for context in contexts {
            attach(context: context)
        }

        var loaded: RawState
        do { loaded = try store.load() } catch {
            Self.logger.error("load failed: \(String(describing: error)); resetting")
            loaded = RawState()
        }

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
        hintFrequencyOverride = loaded.preferences.hintFrequency
        hintFrequency = hintFrequencyOverride ?? defaultHintFrequency
        reanalyzeConflicts()
        checkDefaultLevelConflicts()
        rebuildKeyBindings()
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
    /// Unsaved in-memory overrides are discarded. On failure, logs the error,
    /// retains the current state, and returns `false`.
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
        hintFrequencyOverride = loaded.preferences.hintFrequency
        hintFrequency = hintFrequencyOverride ?? defaultHintFrequency

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
        for matcher in activeMatchers.values {
            matcher.rebuild()
        }
        reanalyzeConflicts()
        return true
    }

    private func attach(context: any AnyShortcutContext) {
        guard let attachable = context as? RegistryAttachable else { return }
        attachable.__attach(registry: self)
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
                preferences: Preferences(
                    hintsEnabled: hintsEnabledOverride,
                    hintFrequency: hintFrequencyOverride
                )
            ))
        } catch {}
    }

    /// Persists pending changes immediately, bypassing the 250 ms debounce.
    /// Does nothing when no save is pending.
    public func flushPendingSave() {
        pendingSave?.cancel()
        pendingSave = nil
        flushSave()
    }

    // swiftlint:disable identifier_name
    func __flushPendingSave() {
        flushPendingSave()
    }

    var __activeContextIDs: [String] {
        router.__currentStackIDs
    }

    var __router: RegistryEventRouter { router }
    // swiftlint:enable identifier_name
}

// swiftlint:disable identifier_name
@MainActor protocol RegistryAttachable: AnyObject {
    func __attach(registry: any RegistryOverrideSource)
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
