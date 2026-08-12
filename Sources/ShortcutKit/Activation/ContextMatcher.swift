import AppKit
import ShortcutField

@MainActor protocol ContextMatching: AnyObject {
    var contextID: String { get }
    var activationID: UUID? { get }
    func handle(_ event: NSEvent) -> ShortcutMatchResult
    func reset()
    func rebuild()
}

@MainActor
final class ContextMatcher<Action: ShortcutAction>: ContextMatching {
    let contextID: String
    let activationID: UUID?
    private weak var context: ShortcutContext<Action>?
    private weak var coalescer: ContinuousCoalescer?
    private var perAction: [(action: Action, matcher: ShortcutMatcher)] = []

    init(
        context: ShortcutContext<Action>,
        coalescer: ContinuousCoalescer? = nil,
        activationID: UUID? = nil
    ) {
        contextID = context.id
        self.activationID = activationID
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
                context?.dispatchFromMatcher(action, kind: .discrete, activationID: activationID)
                return .fired
            case let .continuousFired(magnitude):
                if let coalescer, let context {
                    let id = context.id
                    coalescer.accumulate(
                        contextID: id,
                        actionID: action.rawValue,
                        magnitude: magnitude
                    ) { [weak context, activationID] summedMagnitude in
                        context?.dispatchFromMatcher(
                            action,
                            kind: .continuous(magnitude: summedMagnitude),
                            activationID: activationID
                        )
                    }
                } else {
                    context?.dispatchFromMatcher(
                        action,
                        kind: .continuous(magnitude: magnitude),
                        activationID: activationID
                    )
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
