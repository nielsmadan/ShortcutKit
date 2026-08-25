import AppKit
import Foundation
import ShortcutKit
@testable import ShortcutKitUI
import SwiftUI
import Testing

@MainActor
struct ShortcutHintPresenterTests {
    @Test func presenterModifierOverloadsBuild() {
        let fixture = Fixture()

        _ = Color.clear.shortcutHintHUD(presenter: fixture.presenter)
        _ = Color.clear.shortcutHintHUD(presenter: fixture.presenter) { context in
            Text(context.actionName)
        }
    }

    @Test func test_DocExample_sharedHintPresenter() {
        let registry = makeRegistry()
        let presenter = ShortcutHintPresenter(registry: registry)
        let options = HintHUDOptions(placement: .top, presentation: .screen)

        _ = Color.clear.shortcutHintHUD(presenter: presenter, options: options)
    }

    @Test func viewHostSnapshotsCursorPositionWhenHintAppears() {
        let host = HintHUDHost(options: HintHUDOptions(placement: .cursor))
        host.isVisible = true
        host.cursorPoint = CGPoint(x: 40, y: 60)

        #expect(host.present(HintToastContext(actionName: "Rename", shortcut: "⌘r", text: "Tip"), id: UUID()))
        host.cursorPoint = CGPoint(x: 100, y: 120)

        #expect(host.current?.cursorPoint == CGPoint(x: 40, y: 60))
    }

    @Test func mountedHostInHiddenWindowIsNotEligible() {
        let fixture = Fixture()
        let window = NSWindow()
        let anchor = HintHUDAnchorView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        window.contentView = anchor
        let host = HintHUDHost(options: .default)

        host.update(
            presenter: fixture.presenter,
            options: .default,
            environment: .default,
            renderer: { _ in AnyView(EmptyView()) },
            anchorView: anchor
        )

        #expect(host.isEligible == false)
        host.detach(anchorView: anchor)
    }

    @Test func detachedMountedHostIsNotEligible() {
        let fixture = Fixture()
        let anchor = HintHUDAnchorView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        let host = HintHUDHost(options: .default)

        host.update(
            presenter: fixture.presenter,
            options: .default,
            environment: .default,
            renderer: { _ in AnyView(EmptyView()) },
            anchorView: anchor
        )

        #expect(host.isEligible == false)
        host.detach(anchorView: anchor)
    }

    @Test func compatibilityOwnerReplacesPresenterWhenRegistryChanges() {
        let firstRegistry = makeRegistry()
        let secondRegistry = makeRegistry()
        let owner = ShortcutHintPresenterOwner(registry: firstRegistry)
        let firstPresenter = owner.presenter

        owner.update(registry: secondRegistry)

        #expect(owner.presenter !== firstPresenter)
        let secondPresenter = owner.presenter
        owner.update(registry: secondRegistry)
        #expect(owner.presenter === secondPresenter)
    }

    @Test func programmaticActionPresentsResolvedHint() {
        let fixture = Fixture()

        fixture.registry.notify(contextID: "editor", actionID: "rename")

        #expect(fixture.host.presented.map(\.context) == [
            HintToastContext(
                actionName: "Rename Session",
                shortcut: "⌘r",
                text: "Tip: Rename Session is bound to ⌘r"
            ),
        ])
        #expect(fixture.announcements == ["Tip: Rename Session is bound to ⌘r"])
    }

    @Test func shortcutEventsDoNotPresentHints() {
        let fixture = Fixture()

        fixture.presenter.receive(ActionFiredEvent(
            contextID: "editor",
            actionID: "rename",
            source: .shortcut
        ))

        #expect(fixture.host.presented.isEmpty)
    }

    @Test func inactiveEventDoesNotConsumeOncePerSessionPolicy() {
        let activity = ActivityState(isActive: false)
        let fixture = Fixture(activity: activity)

        fixture.registry.notify(contextID: "editor", actionID: "rename")
        activity.isActive = true
        fixture.registry.notify(contextID: "editor", actionID: "rename")

        #expect(fixture.host.presented.count == 1)
    }

    @Test func hostlessEventDoesNotConsumeOncePerSessionPolicy() {
        let fixture = Fixture(registerHost: false)

        fixture.registry.notify(contextID: "editor", actionID: "rename")
        fixture.registerHost()
        fixture.registry.notify(contextID: "editor", actionID: "rename")

        #expect(fixture.host.presented.count == 1)
    }

    @Test func onlyTheMostRecentlyRegisteredEligibleHostPresents() {
        let fixture = Fixture()
        let newerHost = TestHintHost()
        fixture.presenter.register(newerHost)

        fixture.registry.notify(contextID: "editor", actionID: "rename")

        #expect(fixture.host.presented.isEmpty)
        #expect(newerHost.presented.count == 1)
    }

    @Test func keyWindowHostOutranksRegistrationOrder() {
        let registry = makeRegistry()
        let firstWindow = NSWindow()
        let secondWindow = NSWindow()
        let windows = WindowState(keyWindow: firstWindow, orderedWindows: [firstWindow, secondWindow])
        let announcements = AnnouncementRecorder()
        let presenter = ShortcutHintPresenter(
            registry: registry,
            isApplicationActive: { true },
            applicationWindows: { windows.snapshot },
            announce: { announcements.values.append($0) },
            sleep: { _ in }
        )
        let firstHost = TestHintHost(window: firstWindow)
        let secondHost = TestHintHost(window: secondWindow)
        presenter.register(firstHost)
        presenter.register(secondHost)

        registry.notify(contextID: "editor", actionID: "rename")

        #expect(firstHost.presented.count == 1)
        #expect(secondHost.presented.isEmpty)
    }

    @Test func largestAnchorWinsWhenAWindowHasMultipleHosts() {
        let registry = makeRegistry()
        let window = NSWindow()
        let windows = WindowState(keyWindow: window, orderedWindows: [window])
        let announcements = AnnouncementRecorder()
        let presenter = ShortcutHintPresenter(
            registry: registry,
            isApplicationActive: { true },
            applicationWindows: { windows.snapshot },
            announce: { announcements.values.append($0) },
            sleep: { _ in }
        )
        let largerHost = TestHintHost(window: window, anchorArea: 400)
        let smallerHost = TestHintHost(window: window, anchorArea: 100)
        presenter.register(largerHost)
        presenter.register(smallerHost)

        registry.notify(contextID: "editor", actionID: "rename")

        #expect(largerHost.presented.count == 1)
        #expect(smallerHost.presented.isEmpty)
    }

    @Test func rejectedPresentationDoesNotConsumeOncePerSessionPolicy() {
        let fixture = Fixture()
        fixture.host.acceptsPresentation = false

        fixture.registry.notify(contextID: "editor", actionID: "rename")
        fixture.host.acceptsPresentation = true
        fixture.registry.notify(contextID: "editor", actionID: "rename")

        #expect(fixture.host.presented.count == 1)
    }

    @Test func replacementCancelsTheOlderDismissal() async {
        let sleeper = ManualSleeper()
        let fixture = Fixture(
            frequency: .always,
            options: HintHUDOptions(duration: .seconds(10)),
            sleep: sleeper.sleep
        )

        fixture.registry.notify(contextID: "editor", actionID: "rename")
        await sleeper.waitForCallCount(1)
        fixture.registry.notify(contextID: "editor", actionID: "duplicate")
        await sleeper.waitForCallCount(2)
        let replacedID = fixture.host.presented[0].id
        let currentID = fixture.host.presented[1].id

        sleeper.resumeCall(at: 0)
        await Task.yield()
        #expect(fixture.host.dismissed == [replacedID])

        sleeper.resumeCall(at: 1)
        await Task.yield()
        #expect(fixture.host.dismissed == [replacedID, currentID])
    }
}

@MainActor
private func makeRegistry() -> ShortcutRegistry {
    ShortcutRegistry(contexts: [ShortcutContext<TestAction>("editor")])
}

@MainActor
private final class Fixture {
    let registry: ShortcutRegistry
    let presenter: ShortcutHintPresenter
    let host: TestHintHost
    private let announcementRecorder: AnnouncementRecorder
    var announcements: [String] { announcementRecorder.values }
    private var registration: UUID?

    init(
        activity: ActivityState = ActivityState(isActive: true),
        frequency: HintPolicy = .oncePerSession,
        options: HintHUDOptions = HintHUDOptions(duration: .seconds(60)),
        sleep: @escaping @MainActor @Sendable (Duration) async -> Void = { duration in
            try? await Task.sleep(for: duration)
        },
        registerHost: Bool = true
    ) {
        let context = ShortcutContext<TestAction>("editor")
        let announcementRecorder = AnnouncementRecorder()
        registry = ShortcutRegistry(contexts: [context], defaultHintFrequency: frequency)
        host = TestHintHost(options: options)
        self.announcementRecorder = announcementRecorder
        presenter = ShortcutHintPresenter(
            registry: registry,
            isApplicationActive: { activity.isActive },
            announce: { announcementRecorder.values.append($0) },
            sleep: sleep
        )
        if registerHost {
            registration = presenter.register(host)
        }
    }

    func registerHost() {
        registration = presenter.register(host)
    }
}

private enum TestAction: String, ShortcutAction {
    case rename, duplicate

    var definition: ShortcutActionDefinition {
        switch self {
        case .rename: .init("Rename Session", "cmd+r")
        case .duplicate: .init("Duplicate Session", "cmd+d")
        }
    }
}

@MainActor
private final class AnnouncementRecorder {
    var values: [String] = []
}

@MainActor
private final class TestHintHost: ShortcutHintHost {
    struct Presentation {
        let id: UUID
        let context: HintToastContext
    }

    var options: HintHUDOptions
    var isEligible = true
    var window: NSWindow?
    var anchorArea: CGFloat
    var acceptsPresentation = true
    var presented: [Presentation] = []
    var dismissed: [UUID] = []

    init(
        options: HintHUDOptions = .default,
        window: NSWindow? = nil,
        anchorArea: CGFloat = 0
    ) {
        self.options = options
        self.window = window
        self.anchorArea = anchorArea
    }

    func present(_ context: HintToastContext, id: UUID) -> Bool {
        guard acceptsPresentation else { return false }
        presented.append(Presentation(id: id, context: context))
        return true
    }

    func dismiss(id: UUID) {
        dismissed.append(id)
    }
}

@MainActor
private final class WindowState {
    var keyWindow: NSWindow?
    var orderedWindows: [NSWindow]

    init(keyWindow: NSWindow?, orderedWindows: [NSWindow]) {
        self.keyWindow = keyWindow
        self.orderedWindows = orderedWindows
    }

    var snapshot: HintHUDApplicationWindows {
        HintHUDApplicationWindows(
            keyWindow: keyWindow,
            orderedWindows: orderedWindows,
            mainWindow: nil
        )
    }
}

@MainActor
private final class ActivityState {
    var isActive: Bool

    init(isActive: Bool) {
        self.isActive = isActive
    }
}

@MainActor
private final class ManualSleeper {
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func sleep(for _: Duration) async {
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func waitForCallCount(_ count: Int) async {
        while continuations.count < count {
            await Task.yield()
        }
    }

    func resumeCall(at index: Int) {
        continuations[index].resume()
    }
}
