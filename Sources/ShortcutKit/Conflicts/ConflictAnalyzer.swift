import ShortcutField

@MainActor
enum ConflictAnalyzer {
    static func analyze(
        bindings: [Occurrence],
        mutuallyExclusiveContexts: [Set<String>],
        systemShortcuts: Set<SystemHotKey> = []
    ) -> [Conflict] {
        var conflicts: [Conflict] = []
        conflicts.append(contentsOf: detectDuplicates(bindings, mutex: mutuallyExclusiveContexts))
        conflicts.append(contentsOf: detectUnreachablePrefixes(bindings, mutex: mutuallyExclusiveContexts))
        conflicts.append(contentsOf: detectSystemShared(bindings: bindings, systemShortcuts: systemShortcuts))
        return conflicts
    }

    // MARK: Duplicates

    private static func detectDuplicates(
        _ bindings: [Occurrence], mutex: [Set<String>]
    ) -> [Conflict] {
        let completeAtTrigger = bindings.filter { isCompleteAtTrigger($0.shortcut) }
        var bySignature: [TriggerSignature: [Occurrence]] = [:]
        for occurrence in completeAtTrigger {
            bySignature[TriggerSignature(occurrence.shortcut), default: []].append(occurrence)
        }
        var conflicts: [Conflict] = []
        for occurrences in bySignature.values where occurrences.count > 1 {
            if anyPairCanCoactivate(occurrences, mutex: mutex) {
                conflicts.append(.duplicate(occurrences: occurrences))
            }
        }
        return conflicts
    }

    private static func isCompleteAtTrigger(_ shortcut: Shortcut) -> Bool {
        switch shortcut {
        case let .discrete(discrete): discrete.steps.count == 1
        case .continuous: true
        }
    }

    // MARK: Unreachable prefixes

    private static func detectUnreachablePrefixes(
        _ bindings: [Occurrence], mutex: [Set<String>]
    ) -> [Conflict] {
        let discreteOccurrences = bindings.compactMap { occ -> (Occurrence, [DiscreteShortcut.Step])? in
            guard case let .discrete(discrete) = occ.shortcut else { return nil }
            return (occ, discrete.steps)
        }
        var conflicts: [Conflict] = []
        for i in discreteOccurrences.indices {
            for j in discreteOccurrences.indices where i != j {
                let (blocker, blockerSteps) = discreteOccurrences[i]
                let (blocked, blockedSteps) = discreteOccurrences[j]
                guard isStrictPrefix(blockerSteps, of: blockedSteps) else { continue }
                if canCoactivate(blocker.contextID, blocked.contextID, mutex: mutex) {
                    conflicts.append(.unreachablePrefix(blocker: blocker, blocked: blocked))
                }
            }
        }
        return conflicts
    }

    private static func isStrictPrefix(
        _ prefix: [DiscreteShortcut.Step], of full: [DiscreteShortcut.Step]
    ) -> Bool {
        guard prefix.count < full.count else { return false }
        return Array(full.prefix(prefix.count)) == prefix
    }

    // MARK: System shared

    private static func detectSystemShared(
        bindings: [Occurrence],
        systemShortcuts: Set<SystemHotKey>
    ) -> [Conflict] {
        var conflicts: [Conflict] = []
        for occurrence in bindings {
            guard case let .discrete(discrete) = occurrence.shortcut,
                  discrete.steps.count == 1,
                  case let .key(keyCode) = discrete.steps[0].kind else { continue }
            let key = SystemHotKey(keyCode: keyCode, modifiers: discrete.steps[0].modifiers)
            if systemShortcuts.contains(key) {
                conflicts.append(.systemShared(
                    shortcut: occurrence.shortcut, action: occurrence
                ))
            }
        }
        return conflicts
    }

    // MARK: Mutex helpers

    private static func canCoactivate(_ a: String, _ b: String, mutex: [Set<String>]) -> Bool {
        if a == b { return true }
        return !mutex.contains { $0.contains(a) && $0.contains(b) }
    }

    private static func anyPairCanCoactivate(
        _ occurrences: [Occurrence], mutex: [Set<String>]
    ) -> Bool {
        let ids = Array(Set(occurrences.map(\.contextID)))
        if ids.count == 1 { return true }
        for i in ids.indices {
            for j in (i + 1) ..< ids.count where canCoactivate(ids[i], ids[j], mutex: mutex) {
                return true
            }
        }
        return false
    }
}
