import AppKit
import ShortcutField

/// One matcher's verdict on an event, plus the detail the debug surface needs.
///
/// `ShortcutMatchResult` alone says `.fired` without saying *what* fired, and the
/// router has no other way to learn it. Internal, so this costs no public API.
struct ContextMatchOutcome {
    let result: ShortcutMatchResult
    /// The action the result refers to, when there is one.
    let action: ActionRef?
    /// Matched but not dispatched because the action opted out of key repeat.
    let repeatSuppressed: Bool

    static let ignored = ContextMatchOutcome(result: .ignored, action: nil, repeatSuppressed: false)
}

@MainActor protocol ContextMatching: AnyObject {
    var contextID: String { get }
    var activationID: UUID? { get }
    func handle(_ event: NSEvent) -> ContextMatchOutcome
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

    func handle(_ event: NSEvent) -> ContextMatchOutcome {
        var didAdvance = false
        var consumeFromAdvance = false
        var advancedAction: ActionRef?
        for index in perAction.indices {
            let (action, matcher) = perAction[index]
            switch matcher.handle(event) {
            case .ignored:
                continue
            case let .advanced(consume):
                didAdvance = true
                consumeFromAdvance = consumeFromAdvance || consume
                if advancedAction == nil { advancedAction = ref(action) }
            case .fired:
                resetOthers(exceptIndex: index)
                let suppressed = Self.isSuppressedRepeat(event, for: action)
                if !suppressed {
                    context?.dispatchFromMatcher(action, kind: .discrete, activationID: activationID)
                }
                return ContextMatchOutcome(
                    result: .fired, action: ref(action), repeatSuppressed: suppressed
                )
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
                return ContextMatchOutcome(
                    result: .continuousFired(magnitude: magnitude),
                    action: ref(action),
                    repeatSuppressed: false
                )
            }
        }
        guard didAdvance else { return .ignored }
        return ContextMatchOutcome(
            result: .advanced(consumeEvent: consumeFromAdvance),
            action: advancedAction,
            repeatSuppressed: false
        )
    }

    private func ref(_ action: Action) -> ActionRef {
        ActionRef(contextID: contextID, actionID: action.rawValue)
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

    /// The match still consumes the event either way — only the dispatch is
    /// dropped, so a held key doesn't leak repeats into the responder chain.
    ///
    /// `isARepeat` is only valid for keyboard events; reading it on a scroll or
    /// gesture event throws, so the `.keyDown` guard is load-bearing.
    static func isSuppressedRepeat(_ event: NSEvent, for action: Action) -> Bool {
        event.type == .keyDown
            && event.isARepeat
            && !action.definition.allowsKeyRepeat
    }
}
