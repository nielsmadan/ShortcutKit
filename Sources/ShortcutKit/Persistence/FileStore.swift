import Foundation
import os.log

/// Human-editable persistence backed by a file on disk.
///
/// Three independent capabilities:
///
/// 1. **Prioritized search**: pass `urls` instead of `url` to look at several
///    locations in order on load (e.g. user config, then a shipped default).
///    Saves always go to `urls[0]`.
///
/// 2. **Namespace key**: pass `key` to embed ShortcutKit's data under a
///    top-level subtree of the file, leaving sibling tables for the adopter's
///    own settings. Supports dotted paths (`"config.shortcuts"` → nested
///    `[config.shortcuts]`). Saves preserve sibling tables via read-modify-write.
///
/// 3. **`createIfMissing`**: write an empty file at `urls[0]` at init if no
///    file in `urls` exists. Makes the file discoverable from day one.
///
/// Concurrent writers: the library issues atomic single-process writes. If
/// the adopter also writes to the same file from outside the library, they
/// are responsible for serializing those writes; cross-process write races
/// can drop one side's changes.
public final class FileStore: ShortcutBindingsStore {
    public enum Format: Sendable { case toml, json }

    public let urls: [URL]
    public let format: Format
    public let key: String?
    private let keyPath: [String]?

    private static let logger = Logger(
        subsystem: "com.nielsmadan.shortcutkit",
        category: "filestore"
    )

    /// Designated init.
    /// - Parameter urls: load search order (first → last); saves go to `urls[0]`.
    /// - Parameter format: `.toml` (default) or `.json`.
    /// - Parameter key: optional dotted-path subtree key. `nil` means whole-file
    ///   ownership (today's default).
    /// - Parameter createIfMissing: if `true`, writes an empty file at `urls[0]`
    ///   at init time when no file in `urls` exists.
    public init(
        urls: [URL],
        format: Format = .toml,
        key: String? = nil,
        createIfMissing: Bool = false
    ) {
        precondition(!urls.isEmpty, "FileStore: `urls` must not be empty.")
        self.urls = urls
        self.format = format
        self.key = key
        keyPath = key.map { $0.split(separator: ".").map(String.init) }
        precondition(
            keyPath.map { !$0.isEmpty } ?? true,
            "FileStore: `key` must contain at least one path component."
        )
        if createIfMissing, existingFileURL == nil {
            do { try save(RawState()) } catch {
                Self.logger.error(
                    "createIfMissing failed: \(String(describing: error), privacy: .public)"
                )
            }
        }
    }

    /// Convenience for a single URL.
    public convenience init(
        url: URL,
        format: Format = .toml,
        key: String? = nil,
        createIfMissing: Bool = false
    ) {
        self.init(urls: [url], format: format, key: key, createIfMissing: createIfMissing)
    }

    public func load() throws -> RawState {
        guard let url = existingFileURL else { return RawState() }
        switch format {
        case .json:
            let data = try Data(contentsOf: url)
            if let keyPath {
                return try JSONCoding.decode(data, atKey: keyPath)
            }
            return try JSONCoding.decode(data)
        case .toml:
            let text = try String(contentsOf: url, encoding: .utf8)
            if let keyPath {
                return try TOMLCoding.decode(text, atKey: keyPath)
            }
            return try TOMLCoding.decode(text)
        }
    }

    public func save(_ state: RawState) throws {
        let writeURL = urls[0]
        let dir = writeURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        switch format {
        case .json:
            if let keyPath {
                let existing = try? Data(contentsOf: writeURL)
                let data = try JSONCoding.encode(state, intoExisting: existing, atKey: keyPath)
                try data.write(to: writeURL, options: .atomic)
            } else {
                let data = try JSONCoding.encode(state)
                try data.write(to: writeURL, options: .atomic)
            }
        case .toml:
            if let keyPath {
                let existing = try? String(contentsOf: writeURL, encoding: .utf8)
                let text = try TOMLCoding.encode(state, intoExisting: existing, atKey: keyPath)
                try text.write(to: writeURL, atomically: true, encoding: .utf8)
            } else {
                if !state.preferences.isDefault {
                    Self.logger.warning(
                        "preferences not persisted to un-namespaced TOML; set a `key:` to enable a [key.preferences] section"
                    )
                }
                let text = try TOMLCoding.encode(state)
                try text.write(to: writeURL, atomically: true, encoding: .utf8)
            }
        }
    }

    /// First URL in `urls` whose file actually exists on disk.
    private var existingFileURL: URL? {
        urls.first(where: { FileManager.default.fileExists(atPath: $0.path) })
    }
}
