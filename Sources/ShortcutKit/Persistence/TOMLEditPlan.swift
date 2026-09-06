import Foundation

/// Ordered, composable assignment edits for a ``TOMLFile`` candidate.
public struct TOMLEditPlan: Sendable, Equatable {
    enum Operation: Sendable, Equatable {
        case set(path: TOMLPath, value: TOMLValue)
        case remove(path: TOMLPath)
    }

    var operations: [Operation]

    public init() {
        operations = []
    }

    public var isEmpty: Bool { operations.isEmpty }

    public mutating func set(_ value: TOMLValue, at path: TOMLPath) {
        operations.append(.set(path: path, value: value))
    }

    public mutating func remove(at path: TOMLPath) {
        operations.append(.remove(path: path))
    }

    public func appending(_ other: Self) -> Self {
        var copy = self
        copy.operations.append(contentsOf: other.operations)
        return copy
    }
}
