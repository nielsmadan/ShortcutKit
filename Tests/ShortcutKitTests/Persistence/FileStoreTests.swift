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
        s.overrides["editor"] = ["save": "cmd+s", "undo": "cmd+z"]
        s.overrides["viewer"] = ["zoom-in": .continuous(.init(
            kind: .pinchOut, modifiers: .command, sensitivity: 0.5
        ))]
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
        #expect(loaded.overrides == ["editor": ["save": expected]])
    }

    @Test("missing file returns empty state")
    func missingFileEmpty() throws {
        let url = tempURL("toml")
        let loaded = try FileStore(url: url, format: .toml).load()
        #expect(loaded.overrides.isEmpty)
    }
}
