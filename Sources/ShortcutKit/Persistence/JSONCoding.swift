import Foundation

enum JSONCoding {
    enum Error: Swift.Error, Equatable {
        case rootNotAnObject
    }

    // MARK: - Whole-file

    static func encode(_ state: RawState) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(state)
    }

    static func decode(_ data: Data) throws -> RawState {
        try JSONDecoder().decode(RawState.self, from: data)
    }

    // MARK: - Namespaced (sub-tree)

    /// Decode the subtree at `keyPath`. Empty `RawState` if any segment is
    /// missing — adopters without customizations see empty state.
    static func decode(_ data: Data, atKey keyPath: [String]) throws -> RawState {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Error.rootNotAnObject
        }
        guard let subtree = navigate(root, path: keyPath) else {
            return RawState()
        }
        let subtreeData = try JSONSerialization.data(withJSONObject: subtree, options: [.sortedKeys])
        return try JSONDecoder().decode(RawState.self, from: subtreeData)
    }

    /// Read-modify-write: parse `existing` (or start fresh), replace the
    /// subtree at `keyPath` with `state`'s encoding, return the full file Data.
    static func encode(
        _ state: RawState,
        intoExisting existing: Data?,
        atKey keyPath: [String]
    ) throws -> Data {
        var root: [String: Any] = [:]
        if let existing, !existing.isEmpty,
           let parsed = try JSONSerialization.jsonObject(with: existing) as? [String: Any]
        {
            root = parsed
        }
        let stateData = try encode(state)
        guard let subtree = try JSONSerialization.jsonObject(with: stateData) as? [String: Any] else {
            throw Error.rootNotAnObject
        }
        insertSubtree(into: &root, path: keyPath, value: subtree)
        return try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        )
    }

    // MARK: - Helpers

    private static func navigate(_ root: [String: Any], path: [String]) -> [String: Any]? {
        var current = root
        for component in path {
            guard let next = current[component] as? [String: Any] else { return nil }
            current = next
        }
        return current
    }

    private static func insertSubtree(
        into root: inout [String: Any],
        path: [String],
        value: [String: Any]
    ) {
        precondition(!path.isEmpty, "JSONCoding.insertSubtree: path must not be empty")
        if path.count == 1 {
            root[path[0]] = value
            return
        }
        let head = path[0]
        var child = (root[head] as? [String: Any]) ?? [:]
        var rest = path
        rest.removeFirst()
        insertSubtree(into: &child, path: rest, value: value)
        root[head] = child
    }
}
