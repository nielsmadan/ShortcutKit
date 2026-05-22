import AppKit
import ShortcutField

/// Type-erased per-context matcher the registry's aggregator (`RegistryEventRouter`,
/// Task 9) iterates. Holds the matching state for one context.
@MainActor protocol ContextMatching: AnyObject {
    var contextID: String { get }
    /// Feed one event. Dispatches the action internally on `.fired` and
    /// (in Task 11) routes `.continuousFired` through the coalescer.
    func handle(_ event: NSEvent) -> ShortcutMatchResult
    /// Drop in-progress sequence state across all actions in the context.
    func reset()
    /// Rebuild per-action matchers from the context's current effective shortcuts.
    func rebuild()
}

/// One concrete `ContextMatching`, generic over the action enum.
@MainActor
final class ContextMatcher<Action: ShortcutAction>: ContextMatching {
    let contextID: String
    private weak var context: ShortcutContext<Action>?
    private weak var coalescer: ContinuousCoalescer?
    private var perAction: [(action: Action, matcher: ShortcutMatcher)] = []

    init(context: ShortcutContext<Action>, coalescer: ContinuousCoalescer? = nil) {
        contextID = context.id
        self.context = context
        self.coalescer = coalescer
        rebuild()
    }

    func handle(_ event: NSEvent) -> ShortcutMatchResult {
        var didAdvance = false
        var consumeFromAdvance = false
        for index in perAction.indices {
            let (action, matcher) = perAction[index]
            switch matcher.handle(event) {
            case .ignored:
                continue
            case let .advanced(consume):
                didAdvance = true
                consumeFromAdvance = consumeFromAdvance || consume
            case .fired:
                resetOthers(exceptIndex: index)
                context?.dispatchFromMatcher(action, kind: .discrete)
                return .fired
            case let .continuousFired(magnitude):
                if let coalescer, let context {
                    let id = context.id
                    coalescer.accumulate(
                        contextID: id,
                        actionID: action.rawValue,
                        magnitude: magnitude
                    ) { [weak context] summedMagnitude in
                        context?.dispatchFromMatcher(action, kind: .continuous(magnitude: summedMagnitude))
                    }
                } else {
                    // No coalescer attached (standalone tests): dispatch immediately.
                    context?.dispatchFromMatcher(action, kind: .continuous(magnitude: magnitude))
                }
                return .continuousFired(magnitude: magnitude)
            }
        }
        return didAdvance ? .advanced(consumeEvent: consumeFromAdvance) : .ignored
    }

    func reset() {
        for (_, matcher) in perAction {
            matcher.reset()
        }
    }

    func rebuild() {
        guard let context else { perAction = []; return }
        var built: [(action: Action, matcher: ShortcutMatcher)] = []
        for action in Action.allCases {
            for shortcut in context.shortcuts(for: action) {
                built.append((action, ShortcutMatcher(shortcut)))
            }
        }
        perAction = built
    }

    private func resetOthers(exceptIndex keepIndex: Int) {
        for index in perAction.indices where index != keepIndex {
            perAction[index].matcher.reset()
        }
    }
}
