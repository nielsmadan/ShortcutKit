@testable import ShortcutKitGlobal
import Testing

@Suite("GlobalActivatorError") struct GlobalActivatorErrorTests {
    @Test("alreadyStarted has a description")
    func alreadyStartedDescription() {
        let error = GlobalActivatorError.alreadyStarted
        #expect(!error.localizedDescription.isEmpty)
    }
}
