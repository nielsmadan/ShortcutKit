import Foundation
import os.log
import ShortcutField

/// One migration step. Append to the registry's `migrations:` list; never
/// reorder, modify, or delete a shipped entry (spec §5.3).
public enum ShortcutMigration: Sendable {
    case renameAction(context: String, from: String, to: String)
    case moveAction(from: (context: String, action: String),
                    to: (context: String, action: String))
    case resetOverride(context: String, action: String)
    case renameContext(from: String, to: String)
    case custom(@MainActor @Sendable (inout RawState) throws -> Void)
}

/// Internal applier. Runs every migration in order, idempotently. `.custom`
/// errors are caught and logged; state advances as far as it can.
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
            guard var fromPerAction = state.overrides[from.context],
                  let value = fromPerAction[from.action] else { return }
            fromPerAction.removeValue(forKey: from.action)
            state.overrides[from.context] = fromPerAction.isEmpty ? nil : fromPerAction

            var toPerAction = state.overrides[to.context] ?? [:]
            if toPerAction[to.action] != nil {
                logger
                    .warning(
                        "moveAction: target \(to.context, privacy: .public).\(to.action, privacy: .public) exists; source wins"
                    )
            }
            toPerAction[to.action] = value
            state.overrides[to.context] = toPerAction

        case let .resetOverride(context, action):
            guard var perAction = state.overrides[context] else { return }
            perAction.removeValue(forKey: action)
            state.overrides[context] = perAction.isEmpty ? nil : perAction

        case let .renameContext(from, to):
            guard let fromPerAction = state.overrides[from] else { return }
            var merged = state.overrides[to] ?? [:]
            for (action, value) in fromPerAction {
                // Source wins on collision.
                merged[action] = value
            }
            state.overrides[to] = merged
            state.overrides.removeValue(forKey: from)

        case let .custom(closure):
            try closure(&state)
        }
    }
}
