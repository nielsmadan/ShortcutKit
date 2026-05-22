import Foundation

/// Developer-set upper bound on how often the HUD shows the same hint.
public enum HintPolicy: Sendable, Hashable {
    /// Show every time the conditions are met.
    case always
    /// Show at most once per action per session.
    case oncePerSession
    /// Show, then suppress for this many seconds.
    case timeout(TimeInterval)
}

/// Internal policy gate — used by `ShortcutHintHUD` to decide whether to fire.
/// Not part of the adopter-facing API; the test target reaches it via
/// `@testable import ShortcutKitUI`.
struct HintPolicyGate {
    let policy: HintPolicy
    var shown: [String: Date] = [:]
    var now: @Sendable () -> Date

    init(policy: HintPolicy, now: @escaping @Sendable () -> Date = Date.init) {
        self.policy = policy
        self.now = now
    }

    func shouldShow(actionID: String) -> Bool {
        switch policy {
        case .always:
            return true
        case .oncePerSession:
            return shown[actionID] == nil
        case let .timeout(window):
            guard let last = shown[actionID] else { return true }
            return now().timeIntervalSince(last) >= window
        }
    }

    mutating func markShown(actionID: String) {
        shown[actionID] = now()
    }
}
