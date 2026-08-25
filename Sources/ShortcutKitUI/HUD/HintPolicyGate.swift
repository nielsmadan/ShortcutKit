import Foundation
import ShortcutKit

struct HintPolicyGate {
    var shown: [ActionRef: Date] = [:]
    var now: @Sendable () -> Date

    init(now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
    }

    func shouldShow(action: ActionRef, policy: HintPolicy) -> Bool {
        switch policy {
        case .always:
            return true
        case .oncePerSession:
            return shown[action] == nil
        case let .timeout(window):
            guard let last = shown[action] else { return true }
            return now().timeIntervalSince(last) >= window
        }
    }

    mutating func markShown(action: ActionRef) {
        shown[action] = now()
    }
}
