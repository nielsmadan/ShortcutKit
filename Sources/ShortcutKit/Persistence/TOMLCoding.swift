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
        let root = makeTable(from: state, includePreferences: false)
        return serialize(root)
    }

    static func decode(_ source: String) throws -> RawState {
        let root = try TOMLTable(string: source)
        return try decodeTable(root)
    }

    // MARK: - Namespaced (sub-tree) encode/decode

    static func decode(_ source: String, atKey keyPath: [String]) throws -> RawState {
        let root = try TOMLTable(string: source)
        guard let subtable = navigate(root, path: keyPath) else {
            return RawState()
        }
        return try decodeTable(subtable)
    }

    static func encode(
        _ state: RawState,
        intoExisting existing: String?,
        atKey keyPath: [String]
    ) throws -> String {
        let root: TOMLTable = if let existing, !existing.isEmpty {
            try TOMLTable(string: existing)
        } else {
            TOMLTable()
        }
        let newSubtree = makeTable(from: state, includePreferences: true)
        setSubtable(in: root, path: keyPath, to: newSubtree)
        return serialize(root)
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

    // TOMLTable children must be assigned back into their parent after mutation.
    private static func setSubtable(in root: TOMLTable, path: [String], to value: TOMLTable) {
        precondition(!path.isEmpty, "TOMLCoding.setSubtable: path must not be empty")
        if path.count == 1 {
            root[path[0]] = value
            return
        }
        let head = path[0]
        let headTable: TOMLTable = root[head]?.table ?? TOMLTable()
        setSubtable(in: headTable, path: Array(path.dropFirst()), to: value)
        root[head] = headTable
    }

    private static let preferencesKey = "preferences"

    private static func makeTable(from state: RawState, includePreferences: Bool) -> TOMLTable {
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
        if includePreferences, !state.preferences.isDefault {
            let prefs = TOMLTable()
            if let hintsEnabled = state.preferences.hintsEnabled {
                prefs["hints-enabled"] = hintsEnabled
            }
            if let hintFrequency = state.preferences.hintFrequency {
                prefs["hint-frequency"] = hintFrequency.persistedString
            }
            root[preferencesKey] = prefs
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
            state.overrides[contextID] = perAction
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
