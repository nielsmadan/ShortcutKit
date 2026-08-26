import Foundation

/// The live activation stack, in the order the router consults it.
///
/// ``ShortcutRegistry/activeBindings()`` collapses this to a `Set` of context
/// ids, which discards exactly what decides precedence — order, and the fact
/// that one context can be activated more than once. This keeps both.
public struct ActivationSnapshot: Sendable, Equatable {
    public struct Entry: Sendable, Equatable, Identifiable {
        public let activationID: UUID
        public let contextID: String
        public let displayName: LocalizedStringResource
        public let scope: ContextScope

        public var id: UUID { activationID }

        public init(
            activationID: UUID,
            contextID: String,
            displayName: LocalizedStringResource,
            scope: ContextScope
        ) {
            self.activationID = activationID
            self.contextID = contextID
            self.displayName = displayName
            self.scope = scope
        }
    }

    /// Router order: outermost first, innermost last. Duplicates are preserved —
    /// a context activated twice appears twice.
    public let entries: [Entry]

    public init(entries: [Entry] = []) {
        self.entries = entries
    }

    /// Innermost first — dispatch order, and the order to render in.
    public var innermostFirst: [Entry] { entries.reversed() }

    public var isEmpty: Bool { entries.isEmpty }
}
