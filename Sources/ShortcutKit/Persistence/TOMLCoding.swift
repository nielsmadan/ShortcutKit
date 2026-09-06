import Foundation
import ShortcutField
import TOMLKit

enum TOMLCoding {
    enum Error: Swift.Error, Equatable {
        case malformedContinuous(actionID: String)
        case continuousKindRequired(gesture: String)
        case invalidShortcutString(actionID: String, value: String)
        case rootNotATable
    }

    // MARK: - Whole-file encode/decode

    static func encode(_ state: RawState) throws -> String {
        // Preferences require a namespace to avoid colliding with context tables.
        let root = makeTable(from: state)
        return serialize(root)
    }

    static func decode(_ source: String) throws -> RawState {
        let root = try TOMLTable(string: source)
        return try decodeTable(root)
    }

    // MARK: - Namespaced (sub-tree) encode/decode

    static func decode(_ source: String, atKey keyPath: [String]) throws -> RawState {
        let root = try TOMLTable(string: source)
        return try decode(root, atKey: keyPath)
    }

    @MainActor
    static func decode(_ document: TOMLSourceDocument, atKey keyPath: [String]) throws -> RawState {
        try decode(document.semanticRoot, atKey: keyPath)
    }

    private static func decode(_ root: TOMLTable, atKey keyPath: [String]) throws -> RawState {
        guard let subtable = navigate(root, path: keyPath) else {
            return RawState()
        }
        return try decodeTable(subtable)
    }

    @MainActor
    static func decodeStrict(_ document: TOMLSourceDocument, atKey keyPath: [String]) throws -> RawState {
        var namespace = document.semanticRoot
        var namespacePath: [String] = []
        for component in keyPath {
            namespacePath.append(component)
            guard let value = namespace[component] else { return RawState() }
            guard let table = value.table, !table.inline else {
                throw strictDiagnostic(
                    document,
                    path: TOMLPath(namespacePath),
                    value: value,
                    expected: "table",
                    message: "Shortcut namespace must be a table"
                )
            }
            namespace = table
        }

        var state = RawState()
        for contextID in namespace.keys.sorted() {
            let contextPath = TOMLPath(keyPath + [contextID])
            guard let value = namespace[contextID] else { continue }
            if contextID == preferencesKey {
                try decodeStrictPreferences(value, at: contextPath, document: document, into: &state)
                continue
            }
            guard let context = value.table, !context.inline else {
                throw strictDiagnostic(
                    document,
                    path: contextPath,
                    value: value,
                    expected: "table",
                    message: "Shortcut context must be a table"
                )
            }

            var perAction: [String: [Shortcut]] = [:]
            for actionID in context.keys.sorted() {
                guard let actionValue = context[actionID] else { continue }
                let actionPath = contextPath.appending(actionID)
                if let array = actionValue.array {
                    var shortcuts: [Shortcut] = []
                    for element in array {
                        try shortcuts.append(decodeStrictShortcut(
                            element,
                            at: actionPath,
                            document: document
                        ))
                    }
                    perAction[actionID] = shortcuts
                } else {
                    perAction[actionID] = try [decodeStrictShortcut(
                        actionValue,
                        at: actionPath,
                        document: document
                    )]
                }
            }
            if !perAction.isEmpty {
                state.overrides[contextID] = perAction
            }
        }
        return state
    }

    static func editPlan(from base: RawState, to desired: RawState, atKey keyPath: [String]) -> TOMLEditPlan {
        var plan = TOMLEditPlan()
        let contextIDs = Set(base.overrides.keys).union(desired.overrides.keys).sorted()
        for contextID in contextIDs {
            let baseActions = base.overrides[contextID] ?? [:]
            let desiredActions = desired.overrides[contextID] ?? [:]
            let actionIDs = Set(baseActions.keys).union(desiredActions.keys).sorted()
            for actionID in actionIDs where baseActions[actionID] != desiredActions[actionID] {
                let path = TOMLPath(keyPath + [contextID, actionID])
                if let shortcuts = desiredActions[actionID] {
                    plan.set(encodeSourceShortcuts(shortcuts), at: path)
                } else {
                    plan.remove(at: path)
                }
            }
        }

        let preferencesPath = TOMLPath(keyPath + [preferencesKey])
        if base.preferences.hintsEnabled != desired.preferences.hintsEnabled {
            let path = preferencesPath.appending("hints-enabled")
            if let value = desired.preferences.hintsEnabled {
                plan.set(.boolean(value), at: path)
            } else {
                plan.remove(at: path)
            }
        }
        if base.preferences.hintFrequency != desired.preferences.hintFrequency {
            let path = preferencesPath.appending("hint-frequency")
            if let value = desired.preferences.hintFrequency {
                plan.set(.string(value.persistedString), at: path)
            } else {
                plan.remove(at: path)
            }
        }
        return plan
    }

    // MARK: - Helpers

    private static func navigate(_ root: TOMLTable, path: [String]) -> TOMLTable? {
        var current: TOMLTable = root
        for component in path {
            guard let next = current[component]?.table else { return nil }
            current = next
        }
        return current
    }

    private static let preferencesKey = "preferences"

    private static func makeTable(from state: RawState) -> TOMLTable {
        let root = TOMLTable()
        for (contextID, perAction) in state.overrides {
            let table = TOMLTable()
            for (actionID, shortcuts) in perAction {
                if shortcuts.count == 1 {
                    table[actionID] = encodeShortcut(shortcuts[0])
                } else {
                    let array = TOMLArray()
                    for shortcut in shortcuts {
                        array.append(encodeShortcut(shortcut))
                    }
                    table[actionID] = array
                }
            }
            root[contextID] = table
        }
        return root
    }

    private static func decodeTable(_ root: TOMLTable) throws -> RawState {
        var state = RawState()
        for contextID in root.keys {
            if contextID == preferencesKey {
                if let prefs = root[preferencesKey]?.table {
                    state.preferences.hintsEnabled = prefs["hints-enabled"]?.bool
                    state.preferences.hintFrequency = prefs["hint-frequency"]?.string
                        .flatMap(HintPolicy.init(persistedString:))
                }
                continue
            }
            guard let contextTable = root[contextID]?.table else { continue }
            var perAction: [String: [Shortcut]] = [:]
            for actionID in contextTable.keys {
                let value = contextTable[actionID]
                if let array = value?.array {
                    var shortcuts: [Shortcut] = []
                    for element in array {
                        try shortcuts.append(decodeShortcut(element, actionID: actionID))
                    }
                    perAction[actionID] = shortcuts
                } else if let value {
                    perAction[actionID] = try [decodeShortcut(value, actionID: actionID)]
                }
            }
            if !perAction.isEmpty {
                state.overrides[contextID] = perAction
            }
        }
        return state
    }

    private static func encodeShortcut(_ shortcut: Shortcut) -> TOMLValueConvertible {
        switch shortcut {
        case let .discrete(discrete):
            return discrete.ascii
        case let .continuous(continuous):
            let gestureAscii = DiscreteShortcut(
                kind: continuous.kind.asDiscreteKind,
                modifiers: continuous.modifiers
            ).ascii
            let inline = TOMLTable(inline: true)
            inline["gesture"] = gestureAscii
            inline["sensitivity"] = continuous.sensitivity
            return inline
        }
    }

    private static func decodeShortcut(
        _ value: TOMLValueConvertible,
        actionID: String
    ) throws -> Shortcut {
        if let str = value.string {
            do {
                return try Shortcut(ascii: str)
            } catch {
                throw Error.invalidShortcutString(actionID: actionID, value: str)
            }
        } else if let inline = value.table {
            guard let gesture = inline["gesture"]?.string,
                  let sensitivity = (inline["sensitivity"]?.double)
                  ?? (inline["sensitivity"]?.int).map(Double.init)
            else { throw Error.malformedContinuous(actionID: actionID) }

            let discrete: DiscreteShortcut
            do {
                discrete = try DiscreteShortcut(ascii: gesture)
            } catch {
                throw Error.invalidShortcutString(actionID: actionID, value: gesture)
            }
            guard discrete.steps.count == 1,
                  let kind = ContinuousShortcut.Kind(discrete.steps[0].kind)
            else { throw Error.continuousKindRequired(gesture: gesture) }

            return .continuous(.init(
                kind: kind,
                modifiers: discrete.steps[0].modifiers,
                sensitivity: sensitivity
            ))
        } else {
            throw Error.malformedContinuous(actionID: actionID)
        }
    }

    @MainActor
    private static func decodeStrictPreferences(
        _ value: TOMLValueConvertible,
        at path: TOMLPath,
        document: TOMLSourceDocument,
        into state: inout RawState
    ) throws {
        guard let preferences = value.table, !preferences.inline else {
            throw strictDiagnostic(
                document,
                path: path,
                value: value,
                expected: "table",
                message: "Shortcut preferences must be a table"
            )
        }

        if let hints = preferences["hints-enabled"] {
            let valuePath = path.appending("hints-enabled")
            guard let enabled = hints.bool else {
                throw strictDiagnostic(
                    document,
                    path: valuePath,
                    value: hints,
                    expected: "boolean",
                    message: "hints-enabled must be a boolean"
                )
            }
            state.preferences.hintsEnabled = enabled
        }

        if let frequency = preferences["hint-frequency"] {
            let valuePath = path.appending("hint-frequency")
            guard let string = frequency.string,
                  let policy = HintPolicy(persistedString: string),
                  Self.isValid(policy)
            else {
                throw strictDiagnostic(
                    document,
                    path: valuePath,
                    value: frequency,
                    expected: "\"always\", \"once-per-session\", or \"timeout:<seconds>\"",
                    message: "hint-frequency is invalid"
                )
            }
            state.preferences.hintFrequency = policy
        }
    }

    private static func isValid(_ policy: HintPolicy) -> Bool {
        guard case let .timeout(seconds) = policy else { return true }
        return seconds.isFinite && seconds > 0
    }

    @MainActor
    private static func decodeStrictShortcut(
        _ value: TOMLValueConvertible,
        at path: TOMLPath,
        document: TOMLSourceDocument
    ) throws -> Shortcut {
        if let string = value.string {
            do {
                return try Shortcut(ascii: string)
            } catch {
                throw strictDiagnostic(
                    document,
                    path: path,
                    value: value,
                    expected: "valid Shortcut ASCII",
                    message: "Shortcut string is invalid"
                )
            }
        }

        guard let table = value.table, table.inline else {
            throw strictDiagnostic(
                document,
                path: path,
                value: value,
                expected: "shortcut string, inline continuous-shortcut table, or array of those values",
                message: "Shortcut value has the wrong shape"
            )
        }
        guard Set(table.keys) == ["gesture", "sensitivity"],
              let gestureValue = table["gesture"],
              let gesture = gestureValue.string,
              let sensitivityValue = table["sensitivity"],
              let sensitivity = sensitivityValue.double ?? sensitivityValue.int.map(Double.init),
              sensitivity.isFinite,
              (0 ... 1).contains(sensitivity)
        else {
            throw strictDiagnostic(
                document,
                path: path,
                value: value,
                expected: "{ gesture = <continuous Shortcut ASCII>, sensitivity = <0...1> }",
                message: "Continuous shortcut is malformed"
            )
        }

        let discrete: DiscreteShortcut
        do {
            discrete = try DiscreteShortcut(ascii: gesture)
        } catch {
            throw strictDiagnostic(
                document,
                path: path,
                value: gestureValue,
                expected: "single continuous gesture Shortcut ASCII",
                message: "Continuous shortcut gesture is invalid"
            )
        }
        guard discrete.steps.count == 1,
              let kind = ContinuousShortcut.Kind(discrete.steps[0].kind)
        else {
            throw strictDiagnostic(
                document,
                path: path,
                value: gestureValue,
                expected: "single scroll, pinch, or rotate gesture",
                message: "Continuous shortcut requires a continuous gesture"
            )
        }
        return .continuous(.init(
            kind: kind,
            modifiers: discrete.steps[0].modifiers,
            sensitivity: sensitivity
        ))
    }

    private static func encodeSourceShortcuts(_ shortcuts: [Shortcut]) -> ShortcutKit.TOMLValue {
        if shortcuts.count == 1 {
            return encodeSourceShortcut(shortcuts[0])
        }
        return .array(shortcuts.map(encodeSourceShortcut))
    }

    private static func encodeSourceShortcut(_ shortcut: Shortcut) -> ShortcutKit.TOMLValue {
        switch shortcut {
        case let .discrete(discrete):
            .string(discrete.ascii)
        case let .continuous(continuous):
            .inlineTable([
                "gesture": .string(DiscreteShortcut(
                    kind: continuous.kind.asDiscreteKind,
                    modifiers: continuous.modifiers
                ).ascii),
                "sensitivity": .float(continuous.sensitivity),
            ])
        }
    }

    @MainActor
    private static func strictDiagnostic(
        _ document: TOMLSourceDocument,
        path: TOMLPath,
        value: TOMLValueConvertible,
        expected: String,
        message: String
    ) -> TOMLDiagnostic {
        .init(
            kind: .invalidValue,
            message: message,
            fileURL: document.fileURL,
            path: path,
            location: document.location(of: path),
            offendingValue: value.debugDescription,
            expected: expected
        )
    }

    private static func serialize(_ root: TOMLTable) -> String {
        // Double-quoted strings keep generated TOML familiar and hand-editable.
        root.convert(to: .toml, options: [
            .allowMultilineStrings,
            .allowUnicodeStrings,
            .allowBinaryIntegers,
            .allowOctalIntegers,
            .allowHexadecimalIntegers,
            .indentations,
        ])
    }
}
