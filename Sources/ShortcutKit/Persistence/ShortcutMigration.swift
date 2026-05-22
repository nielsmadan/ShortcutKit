/// Append-only migration step applied to `RawState`. Cases ship in Task 7.
public enum ShortcutMigration: Sendable {
    // Intentionally empty at this stage; Task 7 adds .renameAction, .moveAction,
    // .resetOverride, .renameContext, .custom.
}
