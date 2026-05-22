import Foundation
import ShortcutField
import TOMLKit

enum TOMLCoding {
    enum Error: Swift.Error, Equatable {
        case malformedContinuous(actionID: String)
        case continuousKindRequired(gesture: String)
        case invalidShortcutString(actionID: String, value: String)
    }

    static func encode(_ state: RawState) throws -> String {
        let root = TOMLTable()
        for (contextID, perAction) in state.overrides {
            let table = TOMLTable()
            for (actionID, shortcut) in perAction {
                switch shortcut {
                case let .discrete(discrete):
                    table[actionID] = discrete.ascii
                case let .continuous(continuous):
                    // Represent the gesture as a single-step DiscreteShortcut ascii string
                    // (e.g. "cmd+pinch-out") without the "@sensitivity" suffix.
                    let gestureAscii = DiscreteShortcut(
                        kind: continuous.kind.asDiscreteKind,
                        modifiers: continuous.modifiers
                    ).ascii
                    let inline = TOMLTable(inline: true)
                    inline["gesture"] = gestureAscii
                    inline["sensitivity"] = continuous.sensitivity
                    table[actionID] = inline
                }
            }
            root[contextID] = table
        }
        // Omit .allowLiteralStrings so strings are emitted with double quotes,
        // not single-quoted TOML literal strings. This keeps output hand-editable
        // with standard double-quote conventions and lets test assertions match.
        return root.convert(to: .toml, options: [
            .allowMultilineStrings,
            .allowUnicodeStrings,
            .allowBinaryIntegers,
            .allowOctalIntegers,
            .allowHexadecimalIntegers,
            .indentations,
        ])
    }

    static func decode(_ source: String) throws -> RawState {
        let root = try TOMLTable(string: source)
        var state = RawState()
        for contextID in root.keys {
            guard let contextTable = root[contextID]?.table else { continue }
            var perAction: [String: Shortcut] = [:]
            for actionID in contextTable.keys {
                let value = contextTable[actionID]
                if let str = value?.string {
                    do {
                        perAction[actionID] = try Shortcut(ascii: str)
                    } catch {
                        throw Error.invalidShortcutString(actionID: actionID, value: str)
                    }
                } else if let inline = value?.table {
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

                    perAction[actionID] = .continuous(.init(
                        kind: kind,
                        modifiers: discrete.steps[0].modifiers,
                        sensitivity: sensitivity
                    ))
                }
            }
            state.overrides[contextID] = perAction
        }
        return state
    }
}
