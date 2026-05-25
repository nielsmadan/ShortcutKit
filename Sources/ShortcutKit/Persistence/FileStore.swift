import Foundation

/// Human-editable persistence backed by a file on disk. Choose `.toml` for
/// dotfile-style readable storage; `.json` is also supported.
public final class FileStore: ShortcutBindingsStore {
    public enum Format: Sendable { case toml, json }

    public let url: URL
    public let format: Format

    public init(url: URL, format: Format = .toml) {
        self.url = url
        self.format = format
    }

    public func load() throws -> RawState {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return RawState() }
        switch format {
        case .json:
            let data = try Data(contentsOf: url)
            return try JSONCoding.decode(data)
        case .toml:
            let text = try String(contentsOf: url, encoding: .utf8)
            return try TOMLCoding.decode(text)
        }
    }

    public func save(_ state: RawState) throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        switch format {
        case .json:
            let data = try JSONCoding.encode(state)
            try data.write(to: url, options: .atomic)
        case .toml:
            let text = try TOMLCoding.encode(state)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
