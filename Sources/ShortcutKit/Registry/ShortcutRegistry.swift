import AppKit
import Combine
import Foundation
import os.log
import ShortcutField

/// How many bindings a registry permits per action. Phase 1.5 schema knob;
/// downstream UI (`KeyBindingsView`) and conflict analysis consume this.
public enum BindingsPerAction: Sendable { case one, two, unlimited }

/// The hub: owns contexts, persistence, conflicts, and routing. `@MainActor`
/// throughout (meta-spec concurrency decision). Contexts always live inside a
/// registry; single-context apps still construct one.
@MainActor
public final class ShortcutRegistry: ObservableObject, RegistryOverrideSource {
    public let bindingsPerAction: BindingsPerAction
    // Public outputs — empty here, populated by Tasks 12 (conflicts) and 15 (table).
    @Published public private(set) var conflicts: [Conflict] = []
    @Published public private(set) var keyBindingsTable: KeyBindingsTable = .init()
    public let actionFired: AnyPublisher<ActionFiredEvent, Never>

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
        bindingsPerAction: BindingsPerAction = .one
    ) {
        self.contexts = contexts
        self.mutuallyExclusiveContexts = mutuallyExclusiveContexts
        // Always prepend the Phase 1.5 wrap-single-bindings breadcrumb; the
        // shape upgrade itself happens at the decoder boundary.
        self.migrations = [WrapSingleBindingsMigration.entry] + migrations
        self.store = store
        self.systemShortcutsProvider = systemShortcutsProvider
        self.bindingsPerAction = bindingsPerAction
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
        reanalyzeConflicts()
        checkDefaultLevelConflicts()
        rebuildKeyBindingsTable()
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
        rebuildKeyBindingsTable()
    }

    private func contextScopes() -> [String: ContextScope] {
        var result: [String: ContextScope] = [:]
        for context in contexts {
            result[context.id] = context.scope
        }
        return result
    }

    func rebuildKeyBindingsTable() {
        let byAction = conflictsByActionFQN()
        var sections: [KeyBindingsTable.Section] = []
        for context in contexts {
            guard let p = context as? RegistryAttachable else { continue }
            let rows = p.__currentRows { actionID in
                byAction["\(context.id).\(actionID)"] ?? []
            }
            sections.append(.init(contextID: context.id, rows: rows))
        }
        keyBindingsTable = .init(sections: sections)
    }

    public func legend(for activeContextIDs: Set<String>) -> KeyBindingsLegend {
        var groups: [KeyBindingsLegend.Group] = []
        for context in contexts where activeContextIDs.contains(context.id) {
            guard let p = context as? RegistryAttachable else { continue }
            let rows = p.__currentRows { _ in [] }
            let entries = rows.compactMap { row -> KeyBindingsLegend.Entry? in
                guard let shortcut = row.effectiveShortcut else { return nil }
                return .init(displayName: row.displayName, shortcut: shortcut)
            }
            if !entries.isEmpty {
                groups.append(.init(contextID: context.id, entries: entries))
            }
        }
        return KeyBindingsLegend(groups: groups)
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
        case let .systemShared(_, action):
            ["\(action.contextID).\(action.actionID)"]
        case let .menuCollision(_, action, _):
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
                collisions.append(.menuCollision(
                    shortcut: occurrence.shortcut, action: occurrence, menuItemTitle: title
                ))
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
        case let .systemShared(_, action):
            return "system collision on [\(action.contextID).\(action.actionID)]"
        case let .menuCollision(_, action, _):
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
            try store.save(RawState(overrides: overrides))
        } catch {
            // Best-effort; Task 7 adds os.Logger wiring.
        }
    }

    // swiftlint:disable identifier_name
    /// Test seam — synchronously flushes the pending debounced save.
    func __flushPendingSave() {
        pendingSave?.cancel()
        pendingSave = nil
        flushSave()
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
    func __currentRows(conflictsForAction: (String) -> [Conflict]) -> [KeyBindingsTable.Row]
    func __dispatchFromMatcher(actionID: String)
}

// swiftlint:enable identifier_name
