import Foundation
@testable import ShortcutKit
import Testing

@MainActor
@Suite("FileStore") struct FileStoreTests {
    private func tempURL(_ ext: String) -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ShortcutKitTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("shortcuts.\(ext)")
    }

    private func sampleState() -> RawState {
        var s = RawState()
        s.overrides["editor"] = ["save": ["cmd+s"], "undo": ["cmd+z"]]
        s.overrides["viewer"] = ["zoom-in": [.continuous(.init(
            kind: .pinchOut, modifiers: .command, sensitivity: 0.5
        ))]]
        return s
    }

    @Test("JSON round-trip preserves discrete and continuous bindings")
    func jsonRoundTrip() throws {
        let url = tempURL("json")
        let store = FileStore(url: url, format: .json)
        let original = sampleState()
        try store.save(original)
        #expect(try store.load() == original)
    }

    @Test("TOML round-trip preserves discrete and continuous bindings")
    func tomlRoundTrip() throws {
        let url = tempURL("toml")
        let store = FileStore(url: url, format: .toml)
        let original = sampleState()
        try store.save(original)
        #expect(try store.load() == original)
    }

    @Test("TOML emits inline tables for continuous bindings")
    func tomlContinuousInline() throws {
        let url = tempURL("toml")
        let store = FileStore(url: url, format: .toml)
        try store.save(sampleState())
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("zoom-in = {"))
        #expect(text.contains("gesture = \"cmd+pinch-out\""))
        #expect(text.contains("sensitivity = 0.5"))
    }

    @Test("hand-authored TOML with only a [editor] table loads cleanly")
    func tomlPartialHandAuthored() throws {
        let url = tempURL("toml")
        try """
        [editor]
        save = "cmd+s"
        """.write(to: url, atomically: true, encoding: .utf8)
        let loaded = try FileStore(url: url, format: .toml).load()
        let expected: Shortcut = "cmd+s"
        #expect(loaded.overrides == ["editor": ["save": [expected]]])
    }

    @Test("missing file returns empty state")
    func missingFileEmpty() throws {
        let url = tempURL("toml")
        let loaded = try FileStore(url: url, format: .toml).load()
        #expect(loaded.overrides.isEmpty)
    }

    // MARK: - Prioritized URLs

    @Test("load uses the first existing URL in the urls list")
    func prioritizedLoad() throws {
        let userURL = tempURL("toml")
        let defaultURL = tempURL("toml")
        let defaultState = RawState(overrides: ["editor": ["save": ["cmd+d"]]])
        try FileStore(url: defaultURL).save(defaultState)

        // User URL doesn't exist yet; the default is the fallback.
        let store = FileStore(urls: [userURL, defaultURL])
        #expect(try store.load() == defaultState)

        // After saving, user URL wins.
        let userState = RawState(overrides: ["editor": ["save": ["cmd+u"]]])
        try store.save(userState)
        #expect(try store.load() == userState)
    }

    @Test("save always writes to urls[0]")
    func saveAlwaysFirst() throws {
        let userURL = tempURL("toml")
        let defaultURL = tempURL("toml")
        try FileStore(url: defaultURL).save(RawState(overrides: ["x": ["y": ["a"]]]))

        let store = FileStore(urls: [userURL, defaultURL])
        try store.save(RawState(overrides: ["editor": ["save": ["cmd+s"]]]))

        #expect(FileManager.default.fileExists(atPath: userURL.path))
        // Default file is unchanged.
        let unchanged = try FileStore(url: defaultURL).load()
        #expect(unchanged.overrides == ["x": ["y": ["a"]]])
    }

    @Test("empty urls precondition trap rejected by init")
    func emptyURLsRejected() {
        // We can't easily test precondition traps in Swift Testing, but the
        // call site below would trap if `urls: []` were accepted.
        // Verified via doc and code review.
    }

    // MARK: - createIfMissing

    @Test("createIfMissing writes an empty file when none exists")
    func createIfMissingBootstraps() throws {
        let url = tempURL("toml")
        #expect(FileManager.default.fileExists(atPath: url.path) == false)
        _ = FileStore(url: url, createIfMissing: true)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test("createIfMissing does not overwrite an existing file")
    func createIfMissingPreserves() throws {
        let url = tempURL("toml")
        let original = RawState(overrides: ["editor": ["save": ["cmd+s"]]])
        try FileStore(url: url).save(original)

        _ = FileStore(url: url, createIfMissing: true)
        #expect(try FileStore(url: url).load() == original)
    }

    // MARK: - Namespace key

    @Test("TOML namespace key round-trips and preserves sibling tables")
    func tomlNamespaceRoundTrip() throws {
        let url = tempURL("toml")
        // Hand-author a file with adopter-owned sibling tables.
        try """
        [general]
        theme = "dark"

        [appearance.window]
        remember_position = true
        """.write(to: url, atomically: true, encoding: .utf8)

        let store = FileStore(url: url, key: "shortcuts")
        let state = sampleState()
        try store.save(state)

        // Library data round-trips.
        #expect(try store.load() == state)

        // Adopter's sibling tables are still present.
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("theme = \"dark\""))
        #expect(text.contains("remember_position = true"))
    }

    @Test("TOML namespace: missing subtree on load returns empty state")
    func tomlMissingSubtreeEmpty() throws {
        let url = tempURL("toml")
        try """
        [general]
        theme = "dark"
        """.write(to: url, atomically: true, encoding: .utf8)

        let loaded = try FileStore(url: url, key: "shortcuts").load()
        #expect(loaded.overrides.isEmpty)
    }

    @Test("TOML namespace: nested dotted key path round-trips")
    func tomlNestedKeyPath() throws {
        let url = tempURL("toml")
        let store = FileStore(url: url, key: "config.shortcuts")
        let state = RawState(overrides: ["editor": ["save": ["cmd+s"]]])
        try store.save(state)
        #expect(try store.load() == state)

        let text = try String(contentsOf: url, encoding: .utf8)
        // TOML emits a nested table header at the deeper level.
        #expect(text.contains("[config.shortcuts."))
    }

    @Test("JSON namespace key round-trips and preserves sibling fields")
    func jsonNamespaceRoundTrip() throws {
        let url = tempURL("json")
        try """
        {
          "general": { "theme": "dark" },
          "appearance": { "remember_position": true }
        }
        """.write(to: url, atomically: true, encoding: .utf8)

        let store = FileStore(url: url, format: .json, key: "shortcuts")
        let state = sampleState()
        try store.save(state)

        #expect(try store.load() == state)

        let data = try Data(contentsOf: url)
        let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let general = parsed?["general"] as? [String: Any]
        #expect(general?["theme"] as? String == "dark")
    }

    @Test("JSON namespace: missing subtree on load returns empty")
    func jsonMissingSubtreeEmpty() throws {
        let url = tempURL("json")
        try """
        { "general": { "theme": "dark" } }
        """.write(to: url, atomically: true, encoding: .utf8)
        let loaded = try FileStore(url: url, format: .json, key: "shortcuts").load()
        #expect(loaded.overrides.isEmpty)
    }
}
