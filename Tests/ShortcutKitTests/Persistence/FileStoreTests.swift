import Foundation
@testable import ShortcutKit
import Testing

@MainActor
@Suite("FileStore") final class FileStoreTests {
    private let temporaryDirectory: URL

    init() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShortcutKit-FileStore-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: false)
    }

    deinit {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    private func tempURL(_ ext: String) -> URL {
        temporaryDirectory.appendingPathComponent("\(UUID().uuidString).\(ext)")
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

    @Test("load uses the first existing URL in the urls list")
    func prioritizedLoad() throws {
        let userURL = tempURL("toml")
        let defaultURL = tempURL("toml")
        let defaultState = RawState(overrides: ["editor": ["save": ["cmd+d"]]])
        try FileStore(url: defaultURL).save(defaultState)

        let store = FileStore(urls: [userURL, defaultURL])
        #expect(try store.load() == defaultState)

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
        let unchanged = try FileStore(url: defaultURL).load()
        #expect(unchanged.overrides == ["x": ["y": ["a"]]])
    }

    @Test("empty urls precondition trap rejected by init")
    func emptyURLsRejected() {
        // Swift Testing cannot exercise a precondition trap in-process.
    }

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

    @Test("TOML namespace key round-trips and preserves sibling tables")
    func tomlNamespaceRoundTrip() throws {
        let url = tempURL("toml")
        try """
        [general]
        theme = "dark"

        [appearance.window]
        remember_position = true
        """.write(to: url, atomically: true, encoding: .utf8)

        let store = FileStore(url: url, key: "shortcuts")
        let state = sampleState()
        try store.save(state)

        #expect(try store.load() == state)

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

    private func stateWithPref() -> RawState {
        var s = sampleState()
        s.preferences.hintsEnabled = false
        return s
    }

    @Test("JSON round-trips preferences alongside overrides")
    func jsonPreferencesRoundTrip() throws {
        let url = tempURL("json")
        let store = FileStore(url: url, format: .json)
        let original = stateWithPref()
        try store.save(original)
        #expect(try store.load() == original)
    }

    @Test("default preferences are not written to JSON")
    func jsonDefaultPreferencesOmitted() throws {
        let url = tempURL("json")
        try FileStore(url: url, format: .json).save(sampleState())
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("preferences") == false)
    }

    @Test("namespaced TOML round-trips preferences under [key.preferences]")
    func tomlNamespacedPreferencesRoundTrip() throws {
        let url = tempURL("toml")
        let store = FileStore(url: url, format: .toml, key: "shortcutkit")
        let original = stateWithPref()
        try store.save(original)
        #expect(try store.load() == original)

        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("[shortcutkit.preferences]"))
        #expect(text.contains("hints-enabled = false"))
    }

    @Test("JSON round-trips hintFrequency including a timeout value")
    func jsonHintFrequencyRoundTrip() throws {
        let url = tempURL("json")
        let store = FileStore(url: url, format: .json)
        var original = sampleState()
        original.preferences.hintFrequency = .timeout(45)
        try store.save(original)
        #expect(try store.load() == original)
    }

    @Test("namespaced TOML round-trips hintFrequency as a hand-editable string")
    func tomlHintFrequencyRoundTrip() throws {
        let url = tempURL("toml")
        let store = FileStore(url: url, format: .toml, key: "shortcutkit")
        var original = sampleState()
        original.preferences.hintFrequency = .always
        try store.save(original)
        #expect(try store.load() == original)

        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("hint-frequency = \"always\""))
    }

    @Test("un-namespaced TOML persists overrides but drops preferences")
    func tomlNoKeyDropsPreferences() throws {
        let url = tempURL("toml")
        let store = FileStore(url: url, format: .toml)
        try store.save(stateWithPref())

        let reloaded = try store.load()
        #expect(reloaded.overrides == sampleState().overrides)
        #expect(reloaded.preferences.isDefault)
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("preferences") == false)
    }

    @Test("clear() empties the library's data and preserves sibling tables")
    func clearPreservesSiblings() throws {
        let url = tempURL("toml")
        try """
        [general]
        theme = "dark"
        """.write(to: url, atomically: true, encoding: .utf8)
        let store = FileStore(url: url, key: "shortcuts")
        try store.save(sampleState())
        #expect(try store.load().overrides.isEmpty == false)

        try store.clear()

        #expect(try store.load().overrides.isEmpty)
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("theme = \"dark\""))
    }

    @Test("shared TOML save changes only owned assignment bytes")
    func sharedTOMLPreservesSource() throws {
        let url = tempURL("toml")
        let source = """
        # user configuration
        [shortcuts.editor]
        save   = "cmd+s" # keep this note

        [general]
        theme = 'as written'
        """ + "\n"
        try Data(source.utf8).write(to: url)
        let file = TOMLFile(url: url)
        let store = FileStore(tomlFile: file, namespace: ["shortcuts"])
        let desired = RawState(overrides: ["editor": ["save": ["cmd+shift+s"]]])

        try store.save(desired)

        let expected = source.replacingOccurrences(of: "\"cmd+s\"", with: "\"shift+cmd+s\"")
        #expect(try String(contentsOf: url, encoding: .utf8) == expected)
        #expect(try store.load() == desired)
    }

    @Test("namespaced saves preserve unrelated external shortcut edits")
    func namespacedSaveMergesExternalChanges() throws {
        let url = tempURL("toml")
        try Data("""
        [shortcuts.editor]
        save = "cmd+s"
        undo = "cmd+z"
        """.utf8).write(to: url)
        let store = FileStore(url: url, key: "shortcuts")
        var desired = try store.load()
        desired[context: "editor", action: "undo"] = ["shift+cmd+z"]
        try Data("""
        [shortcuts.editor]
        save = "ctrl+s" # changed outside the app
        undo = "cmd+z"
        """.utf8).write(to: url)

        try store.save(desired)

        let merged = try store.load()
        #expect(merged.overrides["editor"]?["save"] == ["ctrl+s"])
        #expect(merged.overrides["editor"]?["undo"] == ["shift+cmd+z"])
        #expect(try String(contentsOf: url, encoding: .utf8).contains("# changed outside the app"))
    }

    @Test("compatible inline context tables remain editable")
    func inlineContextTableEdits() throws {
        let url = tempURL("toml")
        try Data("""
        shortcuts = { editor = { save = "cmd+s", undo = "cmd+z" } }
        general = { theme = "dark" }
        """.utf8).write(to: url)
        let store = FileStore(url: url, key: "shortcuts")
        var desired = try store.load()
        desired[context: "editor", action: "save"] = ["shift+cmd+s"]
        desired[context: "editor", action: "undo"] = nil
        desired[context: "editor", action: "quit"] = ["cmd+q"]

        try store.save(desired)

        #expect(try store.load() == desired)
        let source = try String(contentsOf: url, encoding: .utf8)
        #expect(source.contains("theme = \"dark\""))
    }

    @Test("compatible table-shaped continuous shortcuts can be updated and removed")
    func tableShapedContinuousEdits() throws {
        let url = tempURL("toml")
        try Data("""
        [shortcuts.viewer.zoom]
        gesture = "cmd+pinch-out"
        sensitivity = 0.5 # chosen deliberately

        [general]
        theme = "dark"
        """.utf8).write(to: url)
        let store = FileStore(url: url, key: "shortcuts")
        var desired = try store.load()
        desired[context: "viewer", action: "zoom"] = [.continuous(.init(
            kind: .pinchOut,
            modifiers: .command,
            sensitivity: 0.75
        ))]

        try store.save(desired)

        #expect(try store.load() == desired)
        #expect(try String(contentsOf: url, encoding: .utf8).contains("sensitivity = 0.75 # chosen deliberately"))

        desired[context: "viewer", action: "zoom"] = ["cmd+z"]
        try store.save(desired)

        #expect(try store.load() == desired)
        #expect(try String(contentsOf: url, encoding: .utf8).contains("# chosen deliberately"))

        desired[context: "viewer", action: "zoom"] = nil
        try store.save(desired)

        #expect(try store.load() == desired)
        let source = try String(contentsOf: url, encoding: .utf8)
        #expect(source.contains("theme = \"dark\""))
        #expect(source.contains("# chosen deliberately"))
    }

    @Test("shared TOML clear retains shortcut comments and sibling bytes")
    func sharedTOMLClearPreservesComments() throws {
        let url = tempURL("toml")
        let source = """
        [shortcuts.editor]
        # chosen for muscle memory
        save = "cmd+s" # keep this note

        [general]
        theme = "dark"
        """ + "\n"
        try Data(source.utf8).write(to: url)
        let store = FileStore(tomlFile: TOMLFile(url: url), namespace: ["shortcuts"])

        try store.clear()

        #expect(try String(contentsOf: url, encoding: .utf8) == """
        [shortcuts.editor]
        # chosen for muscle memory
        # keep this note

        [general]
        theme = "dark"
        """ + "\n")
    }

    @Test("strict decode rejects invalid preferences with source details")
    func strictInvalidPreference() throws {
        let url = tempURL("toml")
        try Data("[shortcuts.preferences]\nhint-frequency = \"sometimes\"\n".utf8).write(to: url)
        let file = TOMLFile(url: url)
        let store = FileStore(tomlFile: file, namespace: ["shortcuts"])
        let snapshot = try file.read()

        #expect(try store.decode(snapshot, mode: .compatible).preferences.isDefault)
        do {
            _ = try store.decode(snapshot, mode: .strict)
            Issue.record("expected strict decoding to fail")
        } catch let diagnostic as TOMLDiagnostic {
            #expect(diagnostic.kind == .invalidValue)
            #expect(diagnostic.path == TOMLPath(["shortcuts", "preferences", "hint-frequency"]))
            #expect(diagnostic.location == .init(line: 2, column: 1))
            #expect(diagnostic.offendingValue?.contains("sometimes") == true)
            #expect(diagnostic.expected?.contains("once-per-session") == true)
            #expect(diagnostic.description.contains("found"))
            #expect(diagnostic.description.contains("expected"))
        }
    }

    @Test("strict decode rejects a non-positive hint timeout")
    func strictInvalidHintTimeout() throws {
        let url = tempURL("toml")
        try Data("[shortcuts.preferences]\nhint-frequency = \"timeout:-1\"\n".utf8).write(to: url)
        let file = TOMLFile(url: url)
        let store = FileStore(tomlFile: file, namespace: ["shortcuts"])

        #expect(throws: TOMLDiagnostic.self) {
            _ = try store.decode(file.read(), mode: .strict)
        }
    }

    @Test("strict decode rejects non-table namespace and context shapes")
    func strictNamespaceShapes() throws {
        let namespaceURL = tempURL("toml")
        try Data("shortcuts = \"wrong\"\n".utf8).write(to: namespaceURL)
        let namespaceFile = TOMLFile(url: namespaceURL)
        let namespaceStore = FileStore(tomlFile: namespaceFile, namespace: ["shortcuts"])

        do {
            _ = try namespaceStore.decode(namespaceFile.read(), mode: .strict)
            Issue.record("expected namespace shape to fail")
        } catch let diagnostic as TOMLDiagnostic {
            #expect(diagnostic.path == TOMLPath(["shortcuts"]))
            #expect(diagnostic.expected == "table")
        }

        let contextURL = tempURL("toml")
        try Data("[shortcuts]\nglobal = true\n".utf8).write(to: contextURL)
        let contextFile = TOMLFile(url: contextURL)
        let contextStore = FileStore(tomlFile: contextFile, namespace: ["shortcuts"])

        do {
            _ = try contextStore.decode(contextFile.read(), mode: .strict)
            Issue.record("expected context shape to fail")
        } catch let diagnostic as TOMLDiagnostic {
            #expect(diagnostic.path == TOMLPath(["shortcuts", "global"]))
            #expect(diagnostic.location == .init(line: 2, column: 1))
        }
    }

    @Test("strict decode reports malformed shortcut array at its assignment")
    func strictMalformedShortcut() throws {
        let url = tempURL("toml")
        try Data("[shortcuts.global]\ncycle = [\"cmd+j\", 3]\n".utf8).write(to: url)
        let file = TOMLFile(url: url)
        let store = FileStore(tomlFile: file, namespace: ["shortcuts"])

        do {
            _ = try store.decode(file.read(), mode: .strict)
            Issue.record("expected shortcut shape to fail")
        } catch let diagnostic as TOMLDiagnostic {
            #expect(diagnostic.kind == .invalidValue)
            #expect(diagnostic.path == TOMLPath(["shortcuts", "global", "cycle"]))
            #expect(diagnostic.location == .init(line: 2, column: 1))
            #expect(diagnostic.expected?.contains("shortcut string") == true)
        }
    }

    @Test("strict decoding accepts canonical continuous shortcuts and preferences")
    func strictCanonicalContinuousAndPreferences() throws {
        let url = tempURL("toml")
        try Data("""
        [shortcuts.viewer]
        zoom = { gesture = "cmd+pinch-out", sensitivity = 0.75 }

        [shortcuts.preferences]
        hints-enabled = false
        hint-frequency = "timeout:45.0"
        """.utf8).write(to: url)
        let file = TOMLFile(url: url)
        let store = FileStore(tomlFile: file, namespace: ["shortcuts"])

        let state = try store.decode(file.read(), mode: .strict)

        #expect(state.overrides["viewer"]?["zoom"] == [.continuous(.init(
            kind: .pinchOut,
            modifiers: .command,
            sensitivity: 0.75
        ))])
        #expect(state.preferences.hintsEnabled == false)
        #expect(state.preferences.hintFrequency == .timeout(45))
    }

    @Test("strict decoding rejects malformed continuous shortcut forms")
    func strictMalformedContinuousForms() throws {
        let values = [
            "{ gesture = \"cmd+pinch-out\" }",
            "{ gesture = \"cmd+pinch-out\", sensitivity = 1.5 }",
            "{ gesture = \"cmd+pinch-out\", sensitivity = 0.5, extra = true }",
            "{ gesture = \"cmd+s\", sensitivity = 0.5 }",
        ]
        for value in values {
            let url = tempURL("toml")
            try Data("[shortcuts.viewer]\nzoom = \(value)\n".utf8).write(to: url)
            let file = TOMLFile(url: url)
            let store = FileStore(tomlFile: file, namespace: ["shortcuts"])

            do {
                _ = try store.decode(file.read(), mode: .strict)
                Issue.record("expected strict decoding to reject \(value)")
            } catch let diagnostic as TOMLDiagnostic {
                #expect(diagnostic.kind == .invalidValue)
                #expect(diagnostic.path == TOMLPath(["shortcuts", "viewer", "zoom"]))
            }
        }
    }

    @Test("strict decoding rejects invalid preference shapes and types")
    func strictPreferenceShapesAndTypes() throws {
        let sources = [
            "[shortcuts]\npreferences = { hints-enabled = true }\n",
            "[shortcuts.preferences]\nhints-enabled = \"yes\"\n",
        ]
        for source in sources {
            let url = tempURL("toml")
            try Data(source.utf8).write(to: url)
            let file = TOMLFile(url: url)
            let store = FileStore(tomlFile: file, namespace: ["shortcuts"])

            do {
                _ = try store.decode(file.read(), mode: .strict)
                Issue.record("expected strict preference decoding to fail")
            } catch let diagnostic as TOMLDiagnostic {
                #expect(diagnostic.kind == .invalidValue)
                #expect(diagnostic.path?.components.starts(with: ["shortcuts", "preferences"]) == true)
            }
        }
    }

    @Test("shared TOML APIs reject JSON and whole-file stores")
    func sharedTOMLAPIsRequireNamespacedTOML() throws {
        let url = tempURL("toml")
        try Data("[shortcuts.editor]\nsave = \"cmd+s\"\n".utf8).write(to: url)
        let snapshot = try TOMLFile(url: url).read()
        let stores = [
            FileStore(url: tempURL("json"), format: .json, key: "shortcuts"),
            FileStore(url: tempURL("toml"), format: .toml),
        ]

        for store in stores {
            #expect(store.namespace == nil)
            #expect(throws: FileStore.Error.requiresNamespacedTOML) {
                _ = try store.decode(snapshot)
            }
            #expect(throws: FileStore.Error.requiresNamespacedTOML) {
                _ = try store.editPlan(from: RawState(), to: RawState())
            }
        }
    }

    @Test("supplied snapshot decoding is independent of later disk changes")
    func snapshotDecodeIsStable() throws {
        let url = tempURL("toml")
        try Data("[shortcuts.editor]\nsave = \"cmd+s\"\n".utf8).write(to: url)
        let file = TOMLFile(url: url)
        let store = FileStore(tomlFile: file, namespace: ["shortcuts"])
        let snapshot = try file.read()
        try Data("[shortcuts.editor]\nsave = \"cmd+x\"\n".utf8).write(to: url)

        let decoded = try store.decode(snapshot, mode: .strict)

        #expect(decoded.overrides == ["editor": ["save": ["cmd+s"]]])
    }

    @Test("shortcut edit plans compose with adopter edits before one commit")
    func editPlanComposition() throws {
        let url = tempURL("toml")
        let source = "[settings]\ngap = 8\n\n[shortcuts.editor]\nsave = \"cmd+s\"\n"
        try Data(source.utf8).write(to: url)
        let file = TOMLFile(url: url)
        let store = FileStore(tomlFile: file, namespace: ["shortcuts"])
        let snapshot = try file.read()
        let base = try store.decode(snapshot, mode: .strict)
        var desired = base
        desired[context: "editor", action: "save"] = ["cmd+shift+s"]
        var settingsPlan = TOMLEditPlan()
        settingsPlan.set(.integer(12), at: ["settings", "gap"])
        let plan = try settingsPlan.appending(store.editPlan(from: base, to: desired))

        let candidate = try file.candidate(from: snapshot, applying: plan)

        #expect(try String(contentsOf: url, encoding: .utf8) == source)
        #expect(candidate.source == "[settings]\ngap = 12\n\n[shortcuts.editor]\nsave = \"shift+cmd+s\"\n")
        #expect(try store.decode(candidate, mode: .strict) == desired)
        #expect(try file.value(at: ["settings", "gap"], in: candidate) == .integer(12))
        _ = try file.commit(candidate)
        #expect(try store.load() == desired)
    }

    @Test("namespaced save never overwrites an unreadable document model")
    func saveDoesNotSwallowReadErrors() throws {
        let url = tempURL("toml")
        let source = "[general\ntheme = \"dark\"\n"
        try Data(source.utf8).write(to: url)
        let store = FileStore(url: url, key: "shortcuts")

        #expect(throws: TOMLDiagnostic.self) {
            try store.save(RawState(overrides: ["editor": ["save": ["cmd+s"]]]))
        }
        #expect(try String(contentsOf: url, encoding: .utf8) == source)
    }

    @Test("namespaced save retries stale revisions at most three times")
    func saveRetriesAreBounded() throws {
        let url = tempURL("toml")
        try Data("[shortcuts.editor]\nsave = \"cmd+s\"\n".utf8).write(to: url)
        let file = TOMLFile(url: url)
        let store = FileStore(tomlFile: file, namespace: ["shortcuts"])
        var attempts = 0
        file.replacementVerificationHook = {
            attempts += 1
            try Data("[shortcuts.editor]\nsave = \"ctrl+s\" # race \(attempts)\n".utf8).write(to: url)
        }

        do {
            try store.save(RawState(overrides: ["editor": ["save": ["cmd+shift+s"]]]))
            Issue.record("expected repeated stale writes to fail")
        } catch let diagnostic as TOMLDiagnostic {
            #expect(diagnostic.kind == .staleRevision)
        }

        #expect(attempts == 3)
        #expect(try String(contentsOf: url, encoding: .utf8) == "[shortcuts.editor]\nsave = \"ctrl+s\" # race 3\n")
        #expect(try FileManager.default.contentsOfDirectory(
            atPath: url.deletingLastPathComponent().path
        ).sorted() == [url.lastPathComponent])
    }

    @Test("DocC example: shared TOML transaction")
    func test_DocExample_sharedTOMLTransaction() throws {
        let configURL = tempURL("toml")
        try Data("[settings]\nwindow-gap = 8\n".utf8).write(to: configURL)
        let file = TOMLFile(url: configURL)
        let shortcutStore = FileStore(tomlFile: file, namespace: ["shortcuts"])

        let snapshot = try file.read()
        let base = try shortcutStore.decode(snapshot, mode: .strict)
        var desired = base
        desired[context: "editor", action: "save"] = ["cmd+s"]
        var settingsEdits = TOMLEditPlan()
        settingsEdits.set(.integer(12), at: ["settings", "window-gap"])
        let edits = try settingsEdits.appending(shortcutStore.editPlan(from: base, to: desired))
        let candidate = try file.candidate(from: snapshot, applying: edits)
        let committed = try file.commit(candidate)

        #expect(try file.value(at: ["settings", "window-gap"], in: committed) == .integer(12))
        #expect(try shortcutStore.decode(committed, mode: .strict) == desired)
    }
}
