import ShortcutField

/// Phase 1 → Phase 1.5 shape upgrade for `RawState.overrides`. The upgrade
/// itself happens transparently at the decoder boundary (see
/// `RawState.init(from:)` in `ShortcutBindingsStore.swift`), so the migration
/// closure here is a deliberate no-op. The named entry exists to keep the
/// upgrade visible in the registered migrations list.
public enum WrapSingleBindingsMigration {
    /// The migration value to append to a `ShortcutRegistry`'s migration list.
    public static let entry: ShortcutMigration = .custom { _ in
        // No-op: shape upgrade happens at the decoder boundary.
    }
}
