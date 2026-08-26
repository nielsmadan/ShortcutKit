import AppKit
import ShortcutField

/// Routes events through active contexts from innermost to outermost.
///
/// The first fired match wins. Other matchers are reset so partial sequences
/// cannot affect later events.
@MainActor
final class RegistryEventRouter {
    private var stack: [any ContextMatching] = []
    private let dispatcher: ShortcutEventDispatcher
    private let listenerID = UUID()
    private var isRegistered = false

    /// Debug sink. `nil` — the default — is the recording gate: with nothing
    /// attached the hot path pays one optional test and builds no event.
    var onDebugEvent: ((ShortcutDebugEvent) -> Void)?

    init(dispatcher: ShortcutEventDispatcher = .shared) {
        self.dispatcher = dispatcher
    }

    func push(_ matcher: any ContextMatching) {
        stack.append(matcher)
        if !isRegistered {
            dispatcher.register(id: listenerID) { [weak self] event in
                self?.handle(event) ?? .ignored
            }
            isRegistered = true
        }
    }

    func remove(activationID: UUID) {
        stack.removeAll { $0.activationID == activationID }
        if stack.isEmpty, isRegistered {
            dispatcher.unregister(id: listenerID)
            isRegistered = false
        }
    }

    func handle(_ event: NSEvent) -> ShortcutMatchResult {
        var consumeFromAdvance = false
        var didAdvance = false
        var advanced: ActionRef?
        // Innermost first, so the index is the depth reported to the debug sink.
        for (depth, matcher) in stack.reversed().enumerated() {
            let outcome = matcher.handle(event)
            switch outcome.result {
            case .ignored:
                continue
            case let .advanced(consume):
                didAdvance = true
                consumeFromAdvance = consumeFromAdvance || consume
                if advanced == nil { advanced = outcome.action }
            case .fired:
                resetOthers(winner: matcher)
                emitDebug(event) {
                    guard let action = outcome.action else { return .noMatch }
                    return outcome.repeatSuppressed
                        ? .suppressedKeyRepeat(action)
                        : .dispatched(action, stackDepth: depth)
                }
                return .fired
            case let .continuousFired(magnitude):
                resetOthers(winner: matcher)
                return .continuousFired(magnitude: magnitude)
            }
        }
        guard didAdvance else {
            emitDebug(event) { .noMatch }
            return .ignored
        }
        emitDebug(event) { advanced.map { .advanced($0) } ?? .noMatch }
        return .advanced(consumeEvent: consumeFromAdvance)
    }

    /// The outcome closure runs only when a sink is attached, so nothing is built
    /// while recording is off.
    private func emitDebug(
        _ event: NSEvent,
        _ outcome: () -> ShortcutDebugEvent.Outcome
    ) {
        guard let onDebugEvent,
              let pressed = ShortcutDebugEvent.pressedShortcut(from: event)
        else { return }
        onDebugEvent(ShortcutDebugEvent(pressed: pressed, outcome: outcome()))
    }

    private func resetOthers(winner: any ContextMatching) {
        for matcher in stack where matcher !== winner {
            matcher.reset()
        }
    }

    // swiftlint:disable identifier_name
    func __setStackForTesting(_ matchers: [any ContextMatching]) {
        stack = matchers
    }

    var __currentStackIDs: [String] { stack.map(\.contextID) }
    // swiftlint:enable identifier_name

    /// Router order — outermost first. `nil` activation ids are skipped: only
    /// activated matchers sit on this stack.
    var activationOrder: [(contextID: String, activationID: UUID)] {
        stack.compactMap { matcher in
            matcher.activationID.map { (matcher.contextID, $0) }
        }
    }
}
