import AppKit
import Carbon.HIToolbox
import Foundation
import ShortcutField
@testable import ShortcutKit
import Testing

@MainActor
@Suite("Layout-exclusive keys") struct LayoutExclusiveKeyTests {
    private func occ(_ ctx: String, _ act: String, _ shortcut: Shortcut) -> Occurrence {
        .init(contextID: ctx, actionID: act, shortcut: shortcut)
    }

    private func key(_ keyCode: Int, _ modifiers: NSEvent.ModifierFlags = .command) -> Shortcut {
        .discrete(DiscreteShortcut(kind: .key(keyCode: UInt16(keyCode)), modifiers: modifiers))
    }

    @Test("the ISO section key is flagged as ISO-only")
    func isoSectionKeyFlagged() {
        let conflicts = ConflictAnalyzer.analyze(
            bindings: [occ("editor", "toggle", key(kVK_ISO_Section))],
            mutuallyExclusiveContexts: []
        )

        #expect(conflicts.count == 1)
        if case let .layoutExclusiveKey(occurrence, layout) = conflicts[0] {
            #expect(occurrence.actionID == "toggle")
            #expect(layout == .iso)
        } else {
            Issue.record("expected .layoutExclusiveKey, got \(conflicts[0])")
        }
    }

    @Test("JIS-only keys are flagged as JIS")
    func jisKeysFlagged() {
        for keyCode in [kVK_JIS_Yen, kVK_JIS_Underscore, kVK_JIS_Kana] {
            let conflicts = ConflictAnalyzer.analyze(
                bindings: [occ("editor", "act", key(keyCode))],
                mutuallyExclusiveContexts: []
            )
            if case let .layoutExclusiveKey(_, layout) = conflicts.first {
                #expect(layout == .jis)
            } else {
                Issue.record("expected .layoutExclusiveKey for keyCode \(keyCode)")
            }
        }
    }

    @Test("a layout-exclusive key is a warning, not an error")
    func flaggedAsWarning() {
        let conflicts = ConflictAnalyzer.analyze(
            bindings: [occ("editor", "toggle", key(kVK_ISO_Section))],
            mutuallyExclusiveContexts: []
        )

        #expect(conflicts[0].severity == .warning)
    }

    @Test("an ordinary ANSI key produces no layout conflict")
    func ansiKeyNotFlagged() {
        let conflicts = ConflictAnalyzer.analyze(
            bindings: [occ("editor", "save", "cmd+s")],
            mutuallyExclusiveContexts: []
        )

        #expect(conflicts.isEmpty)
    }

    @Test("a layout-exclusive key anywhere in a chord is flagged")
    func flaggedMidChord() {
        let chord = Shortcut.discrete(DiscreteShortcut(steps: [
            .init(kind: .key(keyCode: UInt16(kVK_ANSI_K)), modifiers: .command),
            .init(kind: .key(keyCode: UInt16(kVK_ISO_Section)), modifiers: []),
        ]))

        let conflicts = ConflictAnalyzer.analyze(
            bindings: [occ("editor", "chord", chord)],
            mutuallyExclusiveContexts: []
        )

        #expect(conflicts.count == 1)
        #expect(conflicts[0].severity == .warning)
    }

    @Test("the conflict reports the occurrence it came from")
    func reportsOccurrence() {
        let conflicts = ConflictAnalyzer.analyze(
            bindings: [occ("editor", "toggle", key(kVK_ISO_Section))],
            mutuallyExclusiveContexts: []
        )

        #expect(conflicts[0].occurrences.map(\.actionID) == ["toggle"])
    }
}
