import Foundation

enum JSONCoding {
    static func encode(_ state: RawState) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(state)
    }

    static func decode(_ data: Data) throws -> RawState {
        try JSONDecoder().decode(RawState.self, from: data)
    }
}
