import Foundation
import ShortcutField
@testable import ShortcutKit
import Testing

enum EditorAct: String, ShortcutAction {
    case save, undo
    var definition: ShortcutActionDefinition {
        switch self {
        case .save: .init("Save", "cmd+s")
        case .undo: .init("Undo", "cmd+z")
        }
    }
}

enum ViewerAct: String, ShortcutAction {
    case secondSave
    var definition: ShortcutActionDefinition { .init("Save (Viewer)", "cmd+s") }
}

@MainActor
@Suite("ConflictAnalyzer") struct ConflictAnalyzerTests {
    private func occ(_ ctx: String, _ act: String, _ shortcut: Shortcut) -> Occurrence {
        .init(contextID: ctx, actionID: act, shortcut: shortcut)
    }

    @Test("same-trigger 1-step duplicates within one context = .error")
    func withinContextDuplicateError() {
        let conflicts = ConflictAnalyzer.analyze(
            bindings: [
                occ("editor", "save", "cmd+s"),
                occ("editor", "alsoSave", "cmd+s"),
            ],
            mutuallyExclusiveContexts: []
        )
        #expect(conflicts.count == 1)
        if case let .duplicate(occurrences) = conflicts[0] {
            #expect(occurrences.count == 2)
            #expect(conflicts[0].severity == .error)
        } else { Issue.record("expected .duplicate") }
    }

    @Test("same-trigger duplicates across contexts = .warning")
    func crossContextDuplicateWarning() {
        let conflicts = ConflictAnalyzer.analyze(
            bindings: [
                occ("editor", "save", "cmd+s"),
                occ("viewer", "secondSave", "cmd+s"),
            ],
            mutuallyExclusiveContexts: []
        )
        #expect(conflicts.count == 1)
        #expect(conflicts[0].severity == .warning)
    }

    @Test("mutex-grouped contexts suppress cross-context duplicates")
    func mutexSuppressesCrossContext() {
        let conflicts = ConflictAnalyzer.analyze(
            bindings: [
                occ("editor", "save", "cmd+s"),
                occ("viewer", "secondSave", "cmd+s"),
            ],
            mutuallyExclusiveContexts: [["editor", "viewer"]]
        )
        #expect(conflicts.isEmpty)
    }

    @Test("multi-step shortcuts are not duplicates of single-step shortcuts")
    func multiStepNotDuplicate() {
        let multi: Shortcut = "cmd+k cmd+s"
        let conflicts = ConflictAnalyzer.analyze(
            bindings: [
                occ("editor", "save", "cmd+s"),
                occ("editor", "saveAndKill", multi),
            ],
            mutuallyExclusiveContexts: []
        )
        #expect(conflicts.filter { if case .duplicate = $0 { true } else { false } }.isEmpty)
    }

    @Test("cross-kind duplicate: discrete scroll-up vs continuous scroll-up")
    func crossKindDuplicate() {
        let discreteScroll: Shortcut = .discrete(.init(kind: .scroll(direction: .up), modifiers: .command))
        let continuousScroll: Shortcut = .continuous(.init(
            kind: .scroll(direction: .up),
            modifiers: .command,
            sensitivity: 0.5
        ))
        let conflicts = ConflictAnalyzer.analyze(
            bindings: [
                occ("editor", "scrollDiscrete", discreteScroll),
                occ("editor", "scrollContinuous", continuousScroll),
            ],
            mutuallyExclusiveContexts: []
        )
        #expect(conflicts.count == 1)
        if case .duplicate = conflicts[0] {} else { Issue.record("expected .duplicate") }
    }

    @Test("unreachable prefix within a single context = .error")
    func unreachablePrefixSameContextError() {
        let conflicts = ConflictAnalyzer.analyze(
            bindings: [
                occ("editor", "saveChord", "cmd+k"),
                occ("editor", "saveLong", "cmd+k cmd+s"),
            ],
            mutuallyExclusiveContexts: []
        )
        let prefixes = conflicts.compactMap { (c: Conflict) -> Conflict? in
            if case .unreachablePrefix = c { return c } else { return nil }
        }
        #expect(prefixes.count == 1)
        #expect(prefixes[0].severity == .error)
    }

    @Test("unreachable prefix across contexts = .warning")
    func unreachablePrefixCrossContextWarning() {
        let conflicts = ConflictAnalyzer.analyze(
            bindings: [
                occ("editor", "saveChord", "cmd+k"),
                occ("viewer", "saveLong", "cmd+k cmd+s"),
            ],
            mutuallyExclusiveContexts: []
        )
        let prefixes = conflicts.compactMap { (c: Conflict) -> Conflict? in
            if case .unreachablePrefix = c { return c } else { return nil }
        }
        #expect(prefixes.count == 1)
        #expect(prefixes[0].severity == .warning)
    }
}
