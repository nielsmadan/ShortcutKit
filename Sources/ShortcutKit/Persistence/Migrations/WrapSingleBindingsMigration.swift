import ShortcutField

/// Records the legacy single-binding shape upgrade in the migration sequence.
/// Decoding performs the compatibility conversion before migrations run.
enum WrapSingleBindingsMigration {
    static let entry: ShortcutMigration = .custom { _ in
    }
}
