import Foundation

/// A one-based position in TOML source text.
public struct TOMLSourceLocation: Sendable, Equatable, Hashable {
    public let line: Int
    public let column: Int

    public init(line: Int, column: Int) {
        self.line = line
        self.column = column
    }
}

/// A structured file, parse, schema, or edit failure suitable for user-facing diagnostics.
public struct TOMLDiagnostic: Error, Sendable, Equatable, CustomStringConvertible {
    public enum Kind: String, Sendable, Equatable {
        case syntax
        case invalidUTF8
        case invalidValue
        case unsupportedValue
        case tooLarge
        case missing
        case unreadable
        case unwritable
        case nonRegularFile
        case unsupportedEdit
        case staleRevision
        case topologyChanged
        case io
    }

    public let kind: Kind
    public let message: String
    public let fileURL: URL
    public let path: TOMLPath?
    public let location: TOMLSourceLocation?
    public let offendingValue: String?
    public let expected: String?

    public init(
        kind: Kind,
        message: String,
        fileURL: URL,
        path: TOMLPath? = nil,
        location: TOMLSourceLocation? = nil,
        offendingValue: String? = nil,
        expected: String? = nil
    ) {
        self.kind = kind
        self.message = message
        self.fileURL = fileURL
        self.path = path
        self.location = location
        self.offendingValue = offendingValue
        self.expected = expected
    }

    public var description: String {
        var result = fileURL.path
        if let location {
            result += ":\(location.line):\(location.column)"
        }
        if let path {
            result += " [\(path)]"
        }
        result += ": " + message
        if let offendingValue {
            result += "; found \(offendingValue)"
        }
        if let expected {
            result += "; expected \(expected)"
        }
        return result
    }
}
