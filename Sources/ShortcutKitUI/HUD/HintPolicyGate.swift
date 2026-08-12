import Foundation
import ShortcutKit

struct HintPolicyGate {
    var shown: [String: Date] = [:]
    var now: @Sendable () -> Date

    init(now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
    }

    func shouldShow(actionID: String, policy: HintPolicy) -> Bool {
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
