import Darwin
import Foundation
@testable import ShortcutKit
import Testing

@MainActor
@Suite("TOMLFile")
struct TOMLFileTests {
    @Test("missing ordinary path returns no snapshot")
    func missingPath() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = TOMLFile(url: directory.appendingPathComponent("config.toml"))

        #expect(try file.readIfPresent() == nil)
    }

    @Test("an empty file is a valid snapshot")
    func emptyFile() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("config.toml")
        try Data().write(to: url)

        let snapshot = try TOMLFile(url: url).read()

        #expect(snapshot.data.isEmpty)
        #expect(snapshot.source.isEmpty)
    }

    @Test("snapshot contains exact bytes, digest, revision, and source")
    func snapshotContents() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("config.toml")
        let source = "\u{FEFF}# config\r\n[settings]\r\ngap = 8\r\n"
        try Data(source.utf8).write(to: url)
        let file = TOMLFile(url: url)

        let snapshot = try file.read()

        #expect(snapshot.data == Data(source.utf8))
        #expect(snapshot.source == source)
        #expect(snapshot.contentDigest.count == 64)
        #expect(snapshot.revision.size == source.utf8.count)
        #expect(try file.value(at: ["settings", "gap"], in: snapshot) == .integer(8))
        #expect(try file.location(of: ["settings", "gap"], in: snapshot) == .init(line: 3, column: 1))
    }

    @Test("invalid UTF-8 and TOML syntax are reported")
    func invalidContents() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("config.toml")
        let file = TOMLFile(url: url)

        try Data([0xFF]).write(to: url)
        #expect(throws: TOMLDiagnostic.self) {
            _ = try file.read()
        }

        try Data("[settings]\ngap = 01\n".utf8).write(to: url)
        do {
            _ = try file.read()
            Issue.record("expected invalid TOML to fail")
        } catch let diagnostic as TOMLDiagnostic {
            #expect(diagnostic.kind == .syntax)
            #expect(diagnostic.location?.line == 2)
        }
    }

    @Test("oversized, directory, FIFO, and broken symlink paths are invalid")
    func invalidPathShapes() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let oversized = directory.appendingPathComponent("oversized.toml")
        try Data(repeating: 0x20, count: TOMLSourceDocument.maximumByteCount + 1).write(to: oversized)
        try expectDiagnostic(.tooLarge, from: TOMLFile(url: oversized))

        let childDirectory = directory.appendingPathComponent("directory.toml")
        try FileManager.default.createDirectory(at: childDirectory, withIntermediateDirectories: false)
        try expectDiagnostic(.nonRegularFile, from: TOMLFile(url: childDirectory))

        let fifo = directory.appendingPathComponent("fifo.toml")
        #expect(mkfifo(fifo.path, 0o600) == 0)
        try expectDiagnostic(.nonRegularFile, from: TOMLFile(url: fifo))

        let broken = directory.appendingPathComponent("broken.toml")
        #expect(Darwin.symlink("missing-target.toml", broken.path) == 0)
        try expectDiagnostic(.nonRegularFile, from: TOMLFile(url: broken))
    }

    @Test("an unreadable file reports an unreadable diagnostic")
    func unreadableFile() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("config.toml")
        try Data("value = true\n".utf8).write(to: url)
        #expect(chmod(url.path, 0o000) == 0)

        try expectDiagnostic(.unreadable, from: TOMLFile(url: url))
    }

    @Test("candidate commit preserves unrelated bytes and returns disk generation")
    func commitCandidate() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("config.toml")
        let source = "# config\n[settings]\ngap = 8 # keep\n\n[unknown]\nvalue = 'as written'\n"
        try Data(source.utf8).write(to: url)
        let file = TOMLFile(url: url)
        let snapshot = try file.read()
        var plan = TOMLEditPlan()
        plan.set(.integer(12), at: ["settings", "gap"])

        let candidate = try file.candidate(from: snapshot, applying: plan)
        let committed = try file.commit(candidate)
        let diskData = try Data(contentsOf: url)

        let expected = "# config\n[settings]\ngap = 12 # keep\n\n[unknown]\nvalue = 'as written'\n"
        #expect(committed.source == expected)
        #expect(committed.data == diskData)
        #expect(committed.contentDigest == candidate.contentDigest)
        #expect(committed.revision.fileID != snapshot.revision.fileID)
        #expect(try directoryContents(at: directory) == ["config.toml"])
    }

    @Test("stale candidate never overwrites a newer file")
    func staleCandidate() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("config.toml")
        try Data("[settings]\ngap = 8\n".utf8).write(to: url)
        let file = TOMLFile(url: url)
        let snapshot = try file.read()
        var plan = TOMLEditPlan()
        plan.set(.integer(12), at: ["settings", "gap"])
        let candidate = try file.candidate(from: snapshot, applying: plan)
        let external = "[settings]\ngap = 9\nexternal = true\n"
        try Data(external.utf8).write(to: url)

        do {
            _ = try file.commit(candidate)
            Issue.record("expected stale commit to fail")
        } catch let diagnostic as TOMLDiagnostic {
            #expect(diagnostic.kind == .staleRevision)
        }
        #expect(try String(contentsOf: url, encoding: .utf8) == external)
    }

    @Test("content changes invalidate a candidate even when size and mtime are restored")
    func digestDetectsDisguisedChange() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("config.toml")
        try Data("value = 1\n".utf8).write(to: url)
        let file = TOMLFile(url: url)
        let snapshot = try file.read()
        var plan = TOMLEditPlan()
        plan.set(.integer(3), at: ["value"])
        let candidate = try file.candidate(from: snapshot, applying: plan)
        try Data("value = 2\n".utf8).write(to: url)
        let seconds = snapshot.revision.modificationTimeNanoseconds / 1_000_000_000
        let nanoseconds = snapshot.revision.modificationTimeNanoseconds % 1_000_000_000
        var times = [
            timespec(tv_sec: 0, tv_nsec: Int(UTIME_OMIT)),
            timespec(tv_sec: Int(seconds), tv_nsec: Int(nanoseconds)),
        ]
        #expect(utimensat(AT_FDCWD, url.path, &times, 0) == 0)

        #expect(throws: TOMLDiagnostic.self) {
            _ = try file.commit(candidate)
        }
        #expect(try String(contentsOf: url, encoding: .utf8) == "value = 2\n")
    }

    @Test("create is atomic, no-replace, and uses private permissions")
    func createCandidate() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("nested/juggler/config.toml")
        let file = TOMLFile(url: url)
        let candidate = try file.candidate(source: "[settings]\ngap = 8\n")

        let snapshot = try file.create(candidate)

        #expect(snapshot.source == "[settings]\ngap = 8\n")
        #expect(fileMode(at: url) == 0o600)
        #expect(fileMode(at: url.deletingLastPathComponent()) == 0o700)
        #expect(try directoryContents(at: url.deletingLastPathComponent()) == ["config.toml"])

        do {
            _ = try file.create(candidate)
            Issue.record("expected no-replace creation to fail")
        } catch let diagnostic as TOMLDiagnostic {
            #expect(diagnostic.kind == .staleRevision)
        }
    }

    @Test("replacement preserves permissions")
    func preservesPermissions() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("config.toml")
        try Data("[settings]\ngap = 8\n".utf8).write(to: url)
        #expect(chmod(url.path, 0o640) == 0)
        let file = TOMLFile(url: url)
        let snapshot = try file.read()
        var plan = TOMLEditPlan()
        plan.set(.integer(9), at: ["settings", "gap"])

        _ = try file.commit(file.candidate(from: snapshot, applying: plan))

        #expect(fileMode(at: url) == 0o640)
    }

    @Test("replacement preserves extended attributes")
    func preservesExtendedAttributes() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("config.toml")
        try Data("value = 1\n".utf8).write(to: url)
        let name = "com.nielsmadan.shortcutkit.test"
        let attribute = Data("retained".utf8)
        let setResult = attribute.withUnsafeBytes {
            setxattr(url.path, name, $0.baseAddress, $0.count, 0, 0)
        }
        #expect(setResult == 0)
        let file = TOMLFile(url: url)
        let snapshot = try file.read()
        var plan = TOMLEditPlan()
        plan.set(.integer(2), at: ["value"])

        _ = try file.commit(file.candidate(from: snapshot, applying: plan))

        let size = getxattr(url.path, name, nil, 0, 0, 0)
        #expect(size == attribute.count)
        var bytes = [UInt8](repeating: 0, count: max(size, 0))
        let read = getxattr(url.path, name, &bytes, bytes.count, 0, 0)
        #expect(read == attribute.count)
        #expect(Data(bytes) == attribute)
    }

    @Test("final-component symlink remains while its referent is replaced")
    func finalSymlink() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("target.toml")
        let logical = directory.appendingPathComponent("config.toml")
        try Data("[settings]\ngap = 8\n".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(atPath: logical.path, withDestinationPath: "target.toml")
        let file = TOMLFile(url: logical)
        let snapshot = try file.read()
        var plan = TOMLEditPlan()
        plan.set(.integer(9), at: ["settings", "gap"])

        _ = try file.commit(file.candidate(from: snapshot, applying: plan))

        var info = stat()
        #expect(lstat(logical.path, &info) == 0)
        #expect(info.st_mode & S_IFMT == S_IFLNK)
        #expect(try String(contentsOf: target, encoding: .utf8) == "[settings]\ngap = 9\n")
    }

    @Test("missing file below a symlinked parent can be created")
    func symlinkedParentCreate() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let targetDirectory = directory.appendingPathComponent("real")
        try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: false)
        let logicalDirectory = directory.appendingPathComponent("linked")
        try FileManager.default.createSymbolicLink(atPath: logicalDirectory.path, withDestinationPath: "real")
        let logical = logicalDirectory.appendingPathComponent("config.toml")
        let file = TOMLFile(url: logical)

        _ = try file.create(file.candidate(source: "enabled = true\n"))

        #expect(try String(
            contentsOf: targetDirectory.appendingPathComponent("config.toml"),
            encoding: .utf8
        ) == "enabled = true\n")
    }

    @Test("symlink retargeting invalidates a prepared candidate")
    func symlinkRetarget() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("first.toml")
        let second = directory.appendingPathComponent("second.toml")
        let logical = directory.appendingPathComponent("config.toml")
        try Data("value = 1\n".utf8).write(to: first)
        try Data("value = 2\n".utf8).write(to: second)
        try FileManager.default.createSymbolicLink(atPath: logical.path, withDestinationPath: "first.toml")
        let file = TOMLFile(url: logical)
        let snapshot = try file.read()
        var plan = TOMLEditPlan()
        plan.set(.integer(3), at: ["value"])
        let candidate = try file.candidate(from: snapshot, applying: plan)
        try FileManager.default.removeItem(at: logical)
        try FileManager.default.createSymbolicLink(atPath: logical.path, withDestinationPath: "second.toml")

        #expect(throws: TOMLDiagnostic.self) {
            _ = try file.commit(candidate)
        }
        #expect(try String(contentsOf: first, encoding: .utf8) == "value = 1\n")
        #expect(try String(contentsOf: second, encoding: .utf8) == "value = 2\n")
    }

    @Test("symbolic-link cycles are rejected")
    func symlinkCycle() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("first")
        let second = directory.appendingPathComponent("second")
        try FileManager.default.createSymbolicLink(atPath: first.path, withDestinationPath: "second")
        try FileManager.default.createSymbolicLink(atPath: second.path, withDestinationPath: "first")

        do {
            _ = try TOMLFile(url: first).read()
            Issue.record("expected symlink cycle to fail")
        } catch let diagnostic as TOMLDiagnostic {
            #expect(diagnostic.kind == .topologyChanged)
        }
    }

    @Test("snapshot and candidate are Sendable")
    func sendability() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("config.toml")
        try Data("value = true\n".utf8).write(to: url)
        let file = TOMLFile(url: url)
        let snapshot = try file.read()
        let candidate = try file.candidate(from: snapshot, applying: .init())

        requireSendable(snapshot)
        requireSendable(candidate)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShortcutKit-TOMLFile-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    private func expectDiagnostic(_ kind: TOMLDiagnostic.Kind, from file: TOMLFile) throws {
        do {
            _ = try file.read()
            Issue.record("expected \(kind) diagnostic")
        } catch let diagnostic as TOMLDiagnostic {
            #expect(diagnostic.kind == kind, "Received: \(diagnostic)")
        }
    }

    private func fileMode(at url: URL) -> mode_t? {
        var info = stat()
        guard stat(url.path, &info) == 0 else { return nil }
        return info.st_mode & 0o7777
    }

    private func directoryContents(at url: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: url.path).sorted()
    }

    private func requireSendable(_: some Sendable) {}
}
