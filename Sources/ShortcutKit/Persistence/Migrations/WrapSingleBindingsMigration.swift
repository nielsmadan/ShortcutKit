import ShortcutField

/// Phase 1 → Phase 1.5 shape upgrade for `RawState.overrides`. The upgrade
/// itself happens transparently at the decoder boundary (see
/// `RawState.init(from:)` in `ShortcutBindingsStore.swift`), so the migration
/// closure here is a deliberate no-op. The named entry exists to keep the
/// upgrade visible in the registered migrations list.
enum WrapSingleBindingsMigration {
    /// The migration value the registry prepends to every adopter's migration list.
    static let entry: ShortcutMigration = .custom { _ in
        // No-op: shape upgrade happens at the decoder boundary.
    }
}
