import Foundation
import Toml

/// A TOML value supported by assignment-level edits and lookups.
public indirect enum TOMLValue: Sendable, Equatable {
    case string(String)
    case integer(Int64)
    case float(Double)
    case boolean(Bool)
    case array([TOMLValue])
    case inlineTable([String: TOMLValue])
}

extension TOMLValue {
    var encoded: String {
        Toml.encode(tomlValue)
    }

    var tomlValue: Toml.Value {
        switch self {
        case let .string(value):
            .string(value)
        case let .integer(value):
            .int(value)
        case let .float(value):
            .double(value)
        case let .boolean(value):
            .bool(value)
        case let .array(values):
            .array(values.map(\.tomlValue))
        case let .inlineTable(values):
            .table(values.mapValues(\.tomlValue))
        }
    }
}
