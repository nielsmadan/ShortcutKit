import Foundation
import os.log
import ShortcutField

/// The stable persistence identifiers for an action.
public struct ActionRef: Sendable, Hashable {
    public let contextID: String
    public let actionID: String

    public init(contextID: String, actionID: String) {
        self.contextID = contextID
        self.actionID = actionID
    }
}

/// A persistence migration applied idempotently in declaration order.
///
/// Append new migrations; never reorder, modify, or remove a shipped entry.
public enum ShortcutMigration: Sendable {
    case renameAction(context: String, from: String, to: String)
    case moveAction(from: ActionRef, to: ActionRef)
    case resetOverride(context: String, action: String)
    case renameContext(from: String, to: String)
    case custom(@MainActor @Sendable (inout RawState) throws -> Void)
}

@MainActor
enum ShortcutMigrationApplier {
    private static let logger = Logger(
        subsystem: "com.nielsmadan.shortcutkit",
        category: "migration"
    )

    static func apply(_ migrations: [ShortcutMigration], to state: inout RawState) {
        for migration in migrations {
            do { try applyOne(migration, &state) } catch {
                logger.error(".custom migration threw: \(String(describing: error))")
            }
        }
    }

    private static func applyOne(
        _ migration: ShortcutMigration, _ state: inout RawState
    ) throws {
        switch migration {
        case let .renameAction(context, from, to):
            guard var perAction = state.overrides[context],
                  let value = perAction[from] else { return }
            if perAction[to] != nil {
                logger
                    .warning(
                        "renameAction: target \(context, privacy: .public).\(to, privacy: .public) exists; source wins"
                    )
            }
            perAction[to] = value
            perAction.removeValue(forKey: from)
            state.overrides[context] = perAction.isEmpty ? nil : perAction

        case let .moveAction(from, to):
            guard var fromPerAction = state.overrides[from.contextID],
                  let value = fromPerAction[from.actionID] else { return }
            fromPerAction.removeValue(forKey: from.actionID)
            state.overrides[from.contextID] = fromPerAction.isEmpty ? nil : fromPerAction

            var toPerAction = state.overrides[to.contextID] ?? [:]
            if toPerAction[to.actionID] != nil {
                logger
                    .warning(
                        "moveAction: target \(to.contextID, privacy: .public).\(to.actionID, privacy: .public) exists; source wins"
                    )
            }
            toPerAction[to.actionID] = value
            state.overrides[to.contextID] = toPerAction

        case let .resetOverride(context, action):
            guard var perAction = state.overrides[context] else { return }
            perAction.removeValue(forKey: action)
            state.overrides[context] = perAction.isEmpty ? nil : perAction

        case let .renameContext(from, to):
            guard let fromPerAction = state.overrides[from] else { return }
            var merged = state.overrides[to] ?? [:]
            for (action, value) in fromPerAction {
                merged[action] = value
            }
            state.overrides[to] = merged
            state.overrides.removeValue(forKey: from)

        case let .custom(closure):
            try closure(&state)
        }
    }
}
