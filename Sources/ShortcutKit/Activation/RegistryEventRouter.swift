import AppKit
import ShortcutField

/// The single aggregator handler ShortcutKit registers with
/// `ShortcutEventDispatcher.shared`. Owns an ordered stack of active
/// `ContextMatching` instances and iterates them newest-first with
/// early-termination on first `.fired` / `.continuousFired`. Outer matchers
/// are `.reset()` on a win so their mid-sequence state cannot interfere with
/// subsequent events.
///
/// This is the §4 resolution: ShortcutField's dispatcher calls every handler
/// (preserving prefix-sharing for `.onShortcut`); ShortcutKit gets
/// "innermost wins" by doing its own early-termination *inside* one handler.
@MainActor
final class RegistryEventRouter {
    private var stack: [any ContextMatching] = []
    private let dispatcher: ShortcutEventDispatcher
    private let listenerID = UUID()
    private var isRegistered = false

    init(dispatcher: ShortcutEventDispatcher = .shared) {
        self.dispatcher = dispatcher
    }

    /// Push a context matcher onto the stack. Last push = innermost = highest
    /// priority. Lazily registers with the dispatcher on the first push.
    func push(_ matcher: any ContextMatching) {
        stack.append(matcher)
        if !isRegistered {
            dispatcher.register(id: listenerID) { [weak self] event in
                self?.handle(event) ?? .ignored
            }
            isRegistered = true
        }
    }

    /// Remove the matcher for `contextID`. Unregisters from the dispatcher
    /// when the stack becomes empty.
    func remove(contextID: String) {
        stack.removeAll { $0.contextID == contextID }
        if stack.isEmpty, isRegistered {
            dispatcher.unregister(id: listenerID)
            isRegistered = false
        }
    }

    /// Iterate the stack newest-first; the first `.fired` / `.continuousFired`
    /// wins and outer matchers are reset.
    func handle(_ event: NSEvent) -> ShortcutMatchResult {
        var consumeFromAdvance = false
        var didAdvance = false
        for matcher in stack.reversed() {
            switch matcher.handle(event) {
            case .ignored:
                continue
            case let .advanced(consume):
                didAdvance = true
                consumeFromAdvance = consumeFromAdvance || consume
            case .fired:
                resetOthers(winner: matcher)
                return .fired
            case let .continuousFired(magnitude):
                resetOthers(winner: matcher)
                return .continuousFired(magnitude: magnitude)
            }
        }
        return didAdvance ? .advanced(consumeEvent: consumeFromAdvance) : .ignored
    }

    private func resetOthers(winner: any ContextMatching) {
        for matcher in stack where matcher !== winner {
            matcher.reset()
        }
    }

    // MARK: - Test seam

    // swiftlint:disable identifier_name
    /// Test hook: replace the stack directly without going through `push`,
    /// so unit tests don't have to register with `ShortcutEventDispatcher.shared`.
    func __setStackForTesting(_ matchers: [any ContextMatching]) {
        stack = matchers
    }

    /// Test hook: stack as context IDs in outer→innermost order.
    var __currentStackIDs: [String] { stack.map(\.contextID) }
    // swiftlint:enable identifier_name
}
