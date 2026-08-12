import Foundation

/// How often the discoverability HUD repeats a hint for an action.
public enum HintPolicy: Sendable, Hashable {
    /// Show every time the conditions are met.
    case always
    /// Show at most once per action per session.
    case oncePerSession
    /// Show, then suppress for this many seconds.
    case timeout(TimeInterval)
}

extension HintPolicy {
    /// Stable, hand-editable persistence form: `"always"`, `"once-per-session"`,
    /// or `"timeout:30.0"`. Used by both the JSON (`Codable`) and TOML stores.
    var persistedString: String {
        switch self {
        case .always: "always"
        case .oncePerSession: "once-per-session"
        case let .timeout(seconds): "timeout:\(seconds)"
        }
    }

    init?(persistedString string: String) {
        switch string {
        case "always": self = .always
        case "once-per-session": self = .oncePerSession
        default:
            let parts = string.split(separator: ":", maxSplits: 1)
            guard parts.count == 2, parts[0] == "timeout",
                  let seconds = TimeInterval(parts[1])
            else { return nil }
            self = .timeout(seconds)
        }
    }
}

extension HintPolicy: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let value = HintPolicy(persistedString: string) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Invalid HintPolicy string: \(string)"
            )
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(persistedString)
    }
}
