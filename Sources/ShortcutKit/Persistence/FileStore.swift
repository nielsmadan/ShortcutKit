import Foundation
import os.log

/// Human-editable persistence backed by a file on disk.
///
/// Loads the first existing URL and saves to `urls[0]`. A dotted `key` embeds
/// state in a subtree while preserving sibling tables. `createIfMissing` writes
/// an empty file at `urls[0]` when none of the candidate files exists.
///
/// Namespaced TOML saves re-read the latest file and apply only changes made
/// since this store's last load, then use a stale-safe atomic replacement.
/// Whole-file TOML and JSON stores remain last-writer-wins.
@MainActor
public final class FileStore: ShortcutBindingsStore {
    public enum Format: Sendable { case toml, json }
    /// Compatibility preserves historical leniency; strict rejects malformed owned values.
    public enum DecodingMode: Sendable { case compatible, strict }
    public enum Error: Swift.Error, Sendable, Equatable {
        case requiresNamespacedTOML
    }

    public let urls: [URL]
    public let format: Format
    public let key: String?
    /// The component-based TOML namespace, when this is a namespaced store.
    public let namespace: TOMLPath?
    private let keyPath: [String]?
    private let tomlFile: TOMLFile?
    private var lastKnownState: RawState?

    private static let logger = Logger(
        subsystem: "com.nielsmadan.shortcutkit",
        category: "filestore"
    )

    /// - Parameter urls: load search order (first → last); saves go to `urls[0]`.
    /// - Parameter format: `.toml` (default) or `.json`.
    /// - Parameter key: optional dotted-path subtree key. `nil` means whole-file ownership.
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
        namespace = format == .toml ? keyPath.map(TOMLPath.init) : nil
        tomlFile = format == .toml && keyPath != nil && urls.count == 1
            ? TOMLFile(url: urls[0])
            : nil
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

    /// Creates a store backed by a single file URL.
    public convenience init(
        url: URL,
        format: Format = .toml,
        key: String? = nil,
        createIfMissing: Bool = false
    ) {
        self.init(urls: [url], format: format, key: key, createIfMissing: createIfMissing)
    }

    /// Creates a namespaced shortcut store sharing an adopter-owned TOML transaction primitive.
    public init(tomlFile: TOMLFile, namespace: TOMLPath) {
        precondition(!namespace.components.isEmpty, "FileStore: `namespace` must not be empty.")
        urls = [tomlFile.url]
        format = .toml
        key = namespace.description
        self.namespace = namespace
        keyPath = namespace.components
        self.tomlFile = tomlFile
    }

    public func load() throws -> RawState {
        if case .toml = format, keyPath != nil {
            for candidateURL in urls {
                let file = tomlFile(for: candidateURL)
                if let snapshot = try file.readIfPresent() {
                    let state = try decode(snapshot, mode: .compatible)
                    lastKnownState = candidateURL == urls[0] ? state : nil
                    return state
                }
            }
            lastKnownState = RawState()
            return RawState()
        }

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
            return try TOMLCoding.decode(text)
        }
    }

    /// Decodes this store's namespace from immutable TOML bytes.
    public func decode(
        _ snapshot: TOMLFile.Snapshot,
        mode: DecodingMode = .compatible
    ) throws -> RawState {
        guard format == .toml, keyPath != nil else {
            throw Error.requiresNamespacedTOML
        }
        return try decode(tomlFile(for: snapshot.fileURL).sourceDocument(for: snapshot), mode: mode)
    }

    /// Decodes this store's namespace from a validated, uncommitted candidate.
    public func decode(
        _ candidate: TOMLFile.Candidate,
        mode: DecodingMode = .compatible
    ) throws -> RawState {
        guard format == .toml, keyPath != nil else {
            throw Error.requiresNamespacedTOML
        }
        return try decode(tomlFile(for: candidate.fileURL).sourceDocument(for: candidate), mode: mode)
    }

    private func decode(_ document: TOMLSourceDocument, mode: DecodingMode) throws -> RawState {
        guard format == .toml, let keyPath else {
            throw Error.requiresNamespacedTOML
        }
        switch mode {
        case .compatible:
            return try TOMLCoding.decode(document, atKey: keyPath)
        case .strict:
            return try TOMLCoding.decodeStrict(document, atKey: keyPath)
        }
    }

    /// Produces assignment-level changes without reading or writing the file.
    public func editPlan(from base: RawState, to desired: RawState) throws -> TOMLEditPlan {
        guard format == .toml, let keyPath else {
            throw Error.requiresNamespacedTOML
        }
        return TOMLCoding.editPlan(from: base, to: desired, atKey: keyPath)
    }

    public func save(_ state: RawState) throws {
        let writeURL = urls[0]

        switch format {
        case .json:
            try createLegacyParentDirectory(for: writeURL)
            if let keyPath {
                let existing = FileManager.default.fileExists(atPath: writeURL.path)
                    ? try Data(contentsOf: writeURL)
                    : nil
                let data = try JSONCoding.encode(state, intoExisting: existing, atKey: keyPath)
                try data.write(to: writeURL, options: .atomic)
            } else {
                let data = try JSONCoding.encode(state)
                try data.write(to: writeURL, options: .atomic)
            }
        case .toml:
            if keyPath != nil {
                try saveNamespaced(state, to: tomlFile(for: writeURL))
            } else {
                try createLegacyParentDirectory(for: writeURL)
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

    private func createLegacyParentDirectory(for url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    private func saveNamespaced(_ state: RawState, to file: TOMLFile) throws {
        for attempt in 0 ..< 3 {
            do {
                if let snapshot = try file.readIfPresent() {
                    let latest = try decode(snapshot, mode: .compatible)
                    let base = lastKnownState ?? latest
                    let merged = Self.mergingChanges(from: base, to: state, into: latest)
                    let plan = try editPlan(from: latest, to: merged)
                    guard !plan.isEmpty else {
                        lastKnownState = latest
                        return
                    }
                    let candidate = try file.candidate(from: snapshot, applying: plan)
                    guard try decode(candidate, mode: .compatible) == merged else {
                        throw TOMLDiagnostic(
                            kind: .unsupportedEdit,
                            message: "The existing TOML representation cannot express the requested shortcut changes safely",
                            fileURL: file.url
                        )
                    }
                    let committed = try file.commit(candidate)
                    lastKnownState = try decode(committed, mode: .compatible)
                } else {
                    let plan = try editPlan(from: RawState(), to: state)
                    let candidate = try file.candidate(source: "", applying: plan)
                    guard try decode(candidate, mode: .compatible) == state else {
                        throw TOMLDiagnostic(
                            kind: .unsupportedEdit,
                            message: "Could not encode the requested shortcut state",
                            fileURL: file.url
                        )
                    }
                    let created = try file.create(candidate)
                    lastKnownState = try decode(created, mode: .compatible)
                }
                return
            } catch let diagnostic as TOMLDiagnostic
                where attempt < 2 && (diagnostic.kind == .staleRevision || diagnostic.kind == .topologyChanged)
            {
                continue
            }
        }
    }

    private func tomlFile(for url: URL) -> TOMLFile {
        if let tomlFile, tomlFile.url == url {
            return tomlFile
        }
        return TOMLFile(url: url)
    }

    private static func mergingChanges(from base: RawState, to desired: RawState, into latest: RawState) -> RawState {
        var merged = latest
        let contextIDs = Set(base.overrides.keys).union(desired.overrides.keys)
        for contextID in contextIDs {
            let baseActions = base.overrides[contextID] ?? [:]
            let desiredActions = desired.overrides[contextID] ?? [:]
            for actionID in Set(baseActions.keys).union(desiredActions.keys)
                where baseActions[actionID] != desiredActions[actionID]
            {
                merged[context: contextID, action: actionID] = desiredActions[actionID]
            }
        }
        if base.preferences.hintsEnabled != desired.preferences.hintsEnabled {
            merged.preferences.hintsEnabled = desired.preferences.hintsEnabled
        }
        if base.preferences.hintFrequency != desired.preferences.hintFrequency {
            merged.preferences.hintFrequency = desired.preferences.hintFrequency
        }
        return merged
    }

    private var existingFileURL: URL? {
        urls.first(where: { FileManager.default.fileExists(atPath: $0.path) })
    }
}
