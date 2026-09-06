import CryptoKit
import Darwin
import Foundation

/// Lossless, stale-safe TOML transactions for one logical file URL.
@MainActor
public final class TOMLFile {
    /// Filesystem identity and symlink topology captured with a snapshot.
    public struct Revision: Sendable, Equatable, Hashable {
        public let deviceID: UInt64
        public let fileID: UInt64
        public let size: Int64
        public let modificationTimeNanoseconds: Int64
        public let topologyDigest: String

        fileprivate let referentPath: String
        fileprivate let mode: UInt16
        fileprivate let topology: [SymlinkRecord]
    }

    /// Immutable bytes and identity from one coherent file read.
    public struct Snapshot: Sendable, Equatable {
        public let fileURL: URL
        public let data: Data
        public let source: String
        public let contentDigest: String
        public let revision: Revision
    }

    /// Validated replacement bytes that have not been committed.
    public struct Candidate: Sendable, Equatable {
        public let fileURL: URL
        public let data: Data
        public let source: String
        public let contentDigest: String

        fileprivate let baseRevision: Revision?
        fileprivate let baseContentDigest: String?
    }

    public let url: URL
    var replacementVerificationHook: (() throws -> Void)?

    public init(url: URL) {
        precondition(url.isFileURL, "TOMLFile requires a file URL")
        self.url = url.standardizedFileURL
    }

    /// Reads and validates the current regular file.
    public func read() throws -> Snapshot {
        guard let snapshot = try readIfPresent() else {
            throw diagnostic(.missing, "TOML file does not exist")
        }
        return snapshot
    }

    /// Returns `nil` only when an ordinary path component is missing.
    public func readIfPresent() throws -> Snapshot? {
        for _ in 0 ..< 3 {
            switch try PathResolver.resolve(url) {
            case .absent:
                return nil
            case let .file(resolved):
                do {
                    return try read(resolved)
                } catch is RetryRead {
                    continue
                }
            }
        }
        throw diagnostic(.staleRevision, "TOML file changed repeatedly while it was being read")
    }

    /// Applies lossless edits to supplied snapshot bytes without writing.
    public func candidate(from snapshot: Snapshot, applying plan: TOMLEditPlan) throws -> Candidate {
        try requireMatchingURL(snapshot.fileURL)
        let document = try TOMLSourceDocument(data: snapshot.data, fileURL: url)
        let edited = try document.applying(plan)
        return makeCandidate(
            data: edited.data,
            baseRevision: snapshot.revision,
            baseContentDigest: snapshot.contentDigest
        )
    }

    /// Validates new source and optional edits for a later no-replace create.
    public func candidate(source: String, applying plan: TOMLEditPlan = .init()) throws -> Candidate {
        let document = try TOMLSourceDocument(data: Data(source.utf8), fileURL: url)
        let edited = try document.applying(plan)
        return makeCandidate(data: edited.data, baseRevision: nil, baseContentDigest: nil)
    }

    /// Atomically replaces the candidate's unchanged base generation.
    public func commit(_ candidate: Candidate) throws -> Snapshot {
        try requireMatchingURL(candidate.fileURL)
        guard let expected = candidate.baseRevision else {
            throw diagnostic(.staleRevision, "Candidate was not created from an existing snapshot")
        }
        let current = try read()
        guard current.revision == expected,
              current.contentDigest == candidate.baseContentDigest
        else {
            throw diagnostic(.staleRevision, "TOML file changed since the candidate was prepared")
        }
        try replace(candidate.data, current: current)
        let written = try read()
        guard written.contentDigest == candidate.contentDigest else {
            throw diagnostic(.io, "Committed TOML bytes do not match the candidate")
        }
        return written
    }

    /// Atomically creates the file only if its logical path remains absent.
    public func create(_ candidate: Candidate) throws -> Snapshot {
        try requireMatchingURL(candidate.fileURL)
        guard candidate.baseRevision == nil else {
            throw diagnostic(.staleRevision, "Candidate was created from an existing snapshot")
        }
        try createParentDirectory()
        let absence: ResolvedAbsence
        switch try PathResolver.resolve(url) {
        case let .absent(resolved):
            absence = resolved
        case .file:
            throw diagnostic(.staleRevision, "TOML file appeared before it could be created")
        }
        try create(candidate.data, at: absence)
        let written = try read()
        guard written.contentDigest == candidate.contentDigest else {
            throw diagnostic(.io, "Created TOML bytes do not match the candidate")
        }
        return written
    }

    public func value(at path: TOMLPath, in snapshot: Snapshot) throws -> TOMLValue? {
        try requireMatchingURL(snapshot.fileURL)
        return try TOMLSourceDocument(data: snapshot.data, fileURL: url).value(at: path)
    }

    public func value(at path: TOMLPath, in candidate: Candidate) throws -> TOMLValue? {
        try requireMatchingURL(candidate.fileURL)
        return try TOMLSourceDocument(data: candidate.data, fileURL: url).value(at: path)
    }

    public func assignmentPaths(in snapshot: Snapshot) throws -> Set<TOMLPath> {
        try requireMatchingURL(snapshot.fileURL)
        return try TOMLSourceDocument(data: snapshot.data, fileURL: url).assignmentPaths()
    }

    public func assignmentPaths(in candidate: Candidate) throws -> Set<TOMLPath> {
        try requireMatchingURL(candidate.fileURL)
        return try TOMLSourceDocument(data: candidate.data, fileURL: url).assignmentPaths()
    }

    public func location(of path: TOMLPath, in snapshot: Snapshot) throws -> TOMLSourceLocation? {
        try requireMatchingURL(snapshot.fileURL)
        return try TOMLSourceDocument(data: snapshot.data, fileURL: url).location(of: path)
    }

    public func location(of path: TOMLPath, in candidate: Candidate) throws -> TOMLSourceLocation? {
        try requireMatchingURL(candidate.fileURL)
        return try TOMLSourceDocument(data: candidate.data, fileURL: url).location(of: path)
    }

    private func read(_ resolved: ResolvedFile) throws -> Snapshot {
        let descriptor = resolved.descriptor.rawValue

        var before = stat()
        guard fstat(descriptor, &before) == 0 else {
            throw ioDiagnostic("Could not inspect TOML file", code: errno)
        }
        guard Self.isRegular(before.st_mode) else {
            throw diagnostic(.nonRegularFile, "TOML path does not resolve to a regular file")
        }
        guard before.st_size <= TOMLSourceDocument.maximumByteCount else {
            throw diagnostic(.tooLarge, "TOML file exceeds the 1 MiB limit")
        }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let result = Darwin.read(descriptor, &buffer, buffer.count)
            if result == 0 { break }
            if result < 0 {
                if errno == EINTR { continue }
                throw ioDiagnostic("Could not read TOML file", code: errno)
            }
            data.append(buffer, count: result)
            guard data.count <= TOMLSourceDocument.maximumByteCount else {
                throw diagnostic(.tooLarge, "TOML file exceeds the 1 MiB limit")
            }
        }

        var after = stat()
        guard fstat(descriptor, &after) == 0 else {
            throw ioDiagnostic("Could not inspect TOML file after reading", code: errno)
        }
        guard Self.sameFileState(before, after) else { throw RetryRead() }

        guard case let .file(verified) = try PathResolver.resolve(url),
              verified.referentPath == resolved.referentPath,
              verified.topology == resolved.topology,
              UInt64(after.st_dev) == verified.deviceID,
              UInt64(after.st_ino) == verified.fileID
        else {
            throw RetryRead()
        }

        let document = try TOMLSourceDocument(data: data, fileURL: url)
        let revision = Self.revision(stat: after, resolved: verified)
        return .init(
            fileURL: url,
            data: document.data,
            source: String(decoding: document.data, as: UTF8.self),
            contentDigest: Self.digest(document.data),
            revision: revision
        )
    }

    private func replace(_ data: Data, current: Snapshot) throws {
        let target = current.revision.referentPath
        let temporary = try stage(data, beside: target, mode: mode_t(current.revision.mode), copyMetadataFrom: target)
        var removeTemporary = true
        defer {
            if removeTemporary { unlink(temporary) }
        }

        try replacementVerificationHook?()
        let verified = try read()
        guard verified.revision == current.revision,
              verified.contentDigest == current.contentDigest
        else {
            throw diagnostic(.staleRevision, "TOML file changed immediately before commit")
        }
        guard Darwin.rename(temporary, target) == 0 else {
            throw ioDiagnostic("Could not atomically replace TOML file", code: errno)
        }
        removeTemporary = false
        try syncParent(of: target)
    }

    private func create(_ data: Data, at absence: ResolvedAbsence) throws {
        let target = absence.targetPath
        let temporary = try stage(data, beside: target, mode: 0o600, copyMetadataFrom: nil)
        var removeTemporary = true
        defer {
            if removeTemporary { unlink(temporary) }
        }

        guard case let .absent(verified) = try PathResolver.resolve(url),
              verified.targetPath == target,
              verified.topology == absence.topology
        else {
            throw diagnostic(.topologyChanged, "TOML path changed immediately before creation")
        }
        if Darwin.renamex_np(temporary, target, UInt32(RENAME_EXCL)) == 0 {
            removeTemporary = false
            try syncParent(of: target)
            return
        }
        let renameError = errno
        if renameError == EEXIST {
            throw diagnostic(.staleRevision, "TOML file appeared before it could be created")
        }
        guard renameError == ENOTSUP || renameError == EINVAL || renameError == ENOSYS else {
            throw ioDiagnostic("Could not atomically create TOML file", code: renameError)
        }
        guard Darwin.link(temporary, target) == 0 else {
            let linkError = errno
            if linkError == EEXIST {
                throw diagnostic(.staleRevision, "TOML file appeared before it could be created")
            }
            throw ioDiagnostic("Could not atomically create TOML file", code: linkError)
        }
        guard unlink(temporary) == 0 else {
            throw ioDiagnostic("Could not remove TOML staging link", code: errno)
        }
        removeTemporary = false
        try syncParent(of: target)
    }

    private func stage(
        _ data: Data,
        beside target: String,
        mode: mode_t,
        copyMetadataFrom source: String?
    ) throws -> String {
        let parent = URL(fileURLWithPath: target).deletingLastPathComponent().path
        let name = URL(fileURLWithPath: target).lastPathComponent
        var template = Array("\(parent)/.\(name).shortcutkit.XXXXXX".utf8CString)
        let descriptor = template.withUnsafeMutableBufferPointer { mkstemp($0.baseAddress) }
        guard descriptor >= 0 else {
            throw ioDiagnostic("Could not create TOML staging file", code: errno)
        }
        let path = String(decoding: template.dropLast().map { UInt8(bitPattern: $0) }, as: UTF8.self)
        var keep = false
        defer {
            Darwin.close(descriptor)
            if !keep { unlink(path) }
        }

        guard fchmod(descriptor, mode) == 0 else {
            throw ioDiagnostic("Could not set TOML staging permissions", code: errno)
        }
        if let source {
            let flags = copyfile_flags_t(COPYFILE_ACL | COPYFILE_XATTR)
            guard copyfile(source, path, nil, flags) == 0 else {
                throw ioDiagnostic("Could not preserve TOML file metadata", code: errno)
            }
        }

        try data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            var written = 0
            while written < bytes.count {
                let result = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: written),
                    bytes.count - written
                )
                if result < 0 {
                    if errno == EINTR { continue }
                    throw ioDiagnostic("Could not write TOML staging file", code: errno)
                }
                written += result
            }
        }
        guard fsync(descriptor) == 0 else {
            throw ioDiagnostic("Could not synchronize TOML staging file", code: errno)
        }
        keep = true
        return path
    }

    private func syncParent(of path: String) throws {
        let parent = URL(fileURLWithPath: path).deletingLastPathComponent().path
        let descriptor = Darwin.open(parent, O_RDONLY | O_CLOEXEC)
        guard descriptor >= 0 else {
            throw ioDiagnostic("Could not open TOML parent directory", code: errno)
        }
        defer { Darwin.close(descriptor) }
        guard fsync(descriptor) == 0 else {
            throw ioDiagnostic("Could not synchronize TOML parent directory", code: errno)
        }
    }

    private func createParentDirectory() throws {
        let parent = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: parent,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            throw diagnostic(.io, "Could not create TOML parent directory: \(error)")
        }
    }

    private func makeCandidate(
        data: Data,
        baseRevision: Revision?,
        baseContentDigest: String?
    ) -> Candidate {
        .init(
            fileURL: url,
            data: data,
            source: String(decoding: data, as: UTF8.self),
            contentDigest: Self.digest(data),
            baseRevision: baseRevision,
            baseContentDigest: baseContentDigest
        )
    }

    private func requireMatchingURL(_ other: URL) throws {
        guard other.standardizedFileURL == url else {
            throw diagnostic(.topologyChanged, "Snapshot or candidate belongs to a different TOML file")
        }
    }

    private static func revision(stat value: stat, resolved: ResolvedFile) -> Revision {
        .init(
            deviceID: UInt64(value.st_dev),
            fileID: UInt64(value.st_ino),
            size: value.st_size,
            modificationTimeNanoseconds: Int64(value.st_mtimespec.tv_sec) * 1_000_000_000
                + Int64(value.st_mtimespec.tv_nsec),
            topologyDigest: digest(Data(resolved.topology.description.utf8)),
            referentPath: resolved.referentPath,
            mode: UInt16(value.st_mode & 0o7777),
            topology: resolved.topology
        )
    }

    private static func sameFileState(_ lhs: stat, _ rhs: stat) -> Bool {
        lhs.st_dev == rhs.st_dev
            && lhs.st_ino == rhs.st_ino
            && lhs.st_size == rhs.st_size
            && lhs.st_mtimespec.tv_sec == rhs.st_mtimespec.tv_sec
            && lhs.st_mtimespec.tv_nsec == rhs.st_mtimespec.tv_nsec
            && lhs.st_ctimespec.tv_sec == rhs.st_ctimespec.tv_sec
            && lhs.st_ctimespec.tv_nsec == rhs.st_ctimespec.tv_nsec
    }

    private static func isRegular(_ mode: mode_t) -> Bool {
        mode & S_IFMT == S_IFREG
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func ioDiagnostic(_ message: String, code: Int32) -> TOMLDiagnostic {
        let kind: TOMLDiagnostic.Kind = code == EACCES || code == EPERM ? .unreadable : .io
        return diagnostic(kind, "\(message): \(String(cString: strerror(code)))")
    }

    private func diagnostic(_ kind: TOMLDiagnostic.Kind, _ message: String) -> TOMLDiagnostic {
        .init(kind: kind, message: message, fileURL: url)
    }
}

private struct RetryRead: Error {}

private struct SymlinkRecord: Sendable, Equatable, Hashable, CustomStringConvertible {
    let path: String
    let target: String
    let deviceID: UInt64
    let fileID: UInt64

    var description: String { "\(path)\u{0}\(target)\u{0}\(deviceID)\u{0}\(fileID)" }
}

private struct ResolvedFile {
    let referentPath: String
    let topology: [SymlinkRecord]
    let deviceID: UInt64
    let fileID: UInt64
    let descriptor: OwnedDescriptor
}

private struct ResolvedAbsence {
    let targetPath: String
    let topology: [SymlinkRecord]
}

private enum ResolvedPath {
    case absent(ResolvedAbsence)
    case file(ResolvedFile)
}

private enum PathResolver {
    private struct Directory {
        let name: String?
        let descriptor: OwnedDescriptor
    }

    private struct PendingComponent {
        let name: String
        let fromSymlinkTarget: Bool
    }

    private struct ResolutionState {
        let root: Directory
        var directories: [Directory]
        var pending: [PendingComponent]
        var topology: [SymlinkRecord] = []
        var seenSymlinks: Set<FileIdentity> = []
        var traversals = 0

        var currentDirectory: Directory { directories[directories.count - 1] }
    }

    static func resolve(_ url: URL) throws -> ResolvedPath {
        for _ in 0 ..< 3 {
            do {
                return try resolveOnce(url)
            } catch is RetryPathResolution {
                continue
            }
        }
        throw TOMLDiagnostic(
            kind: .topologyChanged,
            message: "TOML path changed repeatedly while it was being resolved",
            fileURL: url
        )
    }

    private static func resolveOnce(_ url: URL) throws -> ResolvedPath {
        var state = try initialState(for: url)

        while !state.pending.isEmpty {
            let component = state.pending.removeFirst()
            if component.name == "." { continue }
            if component.name == ".." {
                if state.directories.count > 1 { state.directories.removeLast() }
                continue
            }
            let directory = state.currentDirectory
            var info = stat()
            if Darwin.fstatat(
                directory.descriptor.rawValue,
                component.name,
                &info,
                AT_SYMLINK_NOFOLLOW
            ) != 0 {
                return try inspectionFailure(
                    code: errno,
                    component: component,
                    pending: state.pending,
                    directories: state.directories,
                    topology: state.topology,
                    fileURL: url
                )
            }

            let type = info.st_mode & S_IFMT
            if type == S_IFLNK {
                try followSymlink(component, info: info, state: &state, fileURL: url)
                continue
            }

            if state.pending.isEmpty {
                guard type == S_IFREG else {
                    throw TOMLDiagnostic(
                        kind: .nonRegularFile,
                        message: "TOML path does not resolve to a regular file",
                        fileURL: url
                    )
                }
                let (descriptor, openedInfo) = try openFile(component, expected: info, in: directory, fileURL: url)
                return .file(.init(
                    referentPath: path(in: state.directories, appending: component.name),
                    topology: state.topology,
                    deviceID: UInt64(openedInfo.st_dev),
                    fileID: UInt64(openedInfo.st_ino),
                    descriptor: descriptor
                ))
            }
            guard type == S_IFDIR else {
                throw TOMLDiagnostic(
                    kind: .nonRegularFile,
                    message: "A TOML path component is not a directory",
                    fileURL: url
                )
            }
            let descriptor = try openDirectory(component, expected: info, in: directory, fileURL: url)
            state.directories.append(.init(name: component.name, descriptor: descriptor))
        }

        return .absent(.init(targetPath: url.path, topology: state.topology))
    }

    private static func initialState(for url: URL) throws -> ResolutionState {
        let rootValue = Darwin.open("/", O_RDONLY | O_CLOEXEC | O_DIRECTORY)
        guard rootValue >= 0 else {
            throw pathDiagnostic("Could not open filesystem root", code: errno, fileURL: url)
        }
        let root = Directory(name: nil, descriptor: .init(rootValue))
        let pending = url.standardizedFileURL.pathComponents.dropFirst().map {
            PendingComponent(name: $0, fromSymlinkTarget: false)
        }
        return .init(root: root, directories: [root], pending: pending)
    }

    private static func followSymlink(
        _ component: PendingComponent,
        info: stat,
        state: inout ResolutionState,
        fileURL: URL
    ) throws {
        state.traversals += 1
        let identity = FileIdentity(deviceID: UInt64(info.st_dev), fileID: UInt64(info.st_ino))
        guard state.traversals <= 64, state.seenSymlinks.insert(identity).inserted else {
            throw TOMLDiagnostic(
                kind: .topologyChanged,
                message: "TOML path contains a symbolic-link cycle",
                fileURL: fileURL
            )
        }
        let target = try readLink(
            component.name,
            relativeTo: state.currentDirectory.descriptor.rawValue,
            fileURL: fileURL
        )
        state.topology.append(.init(
            path: path(in: state.directories, appending: component.name),
            target: target,
            deviceID: identity.deviceID,
            fileID: identity.fileID
        ))
        let targetComponents = (target as NSString).pathComponents
        let expanded = targetComponents
            .dropFirst(target.hasPrefix("/") ? 1 : 0)
            .map { PendingComponent(name: $0, fromSymlinkTarget: true) }
        if target.hasPrefix("/") { state.directories = [state.root] }
        state.pending.insert(contentsOf: expanded, at: 0)
    }

    private static func openFile(
        _ component: PendingComponent,
        expected: stat,
        in directory: Directory,
        fileURL: URL
    ) throws -> (OwnedDescriptor, stat) {
        let descriptorValue = Darwin.openat(
            directory.descriptor.rawValue,
            component.name,
            O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK
        )
        guard descriptorValue >= 0 else {
            throw try openFailure(code: errno, fileURL: fileURL)
        }
        let descriptor = OwnedDescriptor(descriptorValue)
        var openedInfo = stat()
        guard fstat(descriptor.rawValue, &openedInfo) == 0 else {
            throw pathDiagnostic("Could not inspect opened TOML file", code: errno, fileURL: fileURL)
        }
        guard sameIdentity(expected, openedInfo), openedInfo.st_mode & S_IFMT == S_IFREG else {
            throw RetryPathResolution()
        }
        return (descriptor, openedInfo)
    }

    private static func openDirectory(
        _ component: PendingComponent,
        expected: stat,
        in directory: Directory,
        fileURL: URL
    ) throws -> OwnedDescriptor {
        let descriptorValue = Darwin.openat(
            directory.descriptor.rawValue,
            component.name,
            O_RDONLY | O_CLOEXEC | O_DIRECTORY | O_NOFOLLOW
        )
        guard descriptorValue >= 0 else {
            throw try openFailure(code: errno, fileURL: fileURL)
        }
        let descriptor = OwnedDescriptor(descriptorValue)
        var openedInfo = stat()
        guard fstat(descriptor.rawValue, &openedInfo) == 0 else {
            throw pathDiagnostic("Could not inspect TOML directory", code: errno, fileURL: fileURL)
        }
        guard sameIdentity(expected, openedInfo), openedInfo.st_mode & S_IFMT == S_IFDIR else {
            throw RetryPathResolution()
        }
        return descriptor
    }

    private static func inspectionFailure(
        code: Int32,
        component: PendingComponent,
        pending: [PendingComponent],
        directories: [Directory],
        topology: [SymlinkRecord],
        fileURL: URL
    ) throws -> ResolvedPath {
        if code == ENOENT {
            guard !component.fromSymlinkTarget else {
                throw TOMLDiagnostic(
                    kind: .nonRegularFile,
                    message: "TOML path contains a broken symbolic link",
                    fileURL: fileURL
                )
            }
            let suffix = [component.name] + pending.map(\.name)
            let target = path(in: directories, appending: suffix)
            return .absent(.init(targetPath: target, topology: topology))
        }
        throw pathDiagnostic("Could not inspect TOML path", code: code, fileURL: fileURL)
    }

    private static func readLink(_ name: String, relativeTo directory: Int32, fileURL: URL) throws -> String {
        var capacity = 256
        while capacity <= 64 * 1024 {
            var buffer = [CChar](repeating: 0, count: capacity)
            let result = Darwin.readlinkat(directory, name, &buffer, buffer.count)
            guard result >= 0 else {
                if errno == ENOENT || errno == EINVAL { throw RetryPathResolution() }
                throw pathDiagnostic("Could not read symbolic link", code: errno, fileURL: fileURL)
            }
            if result < buffer.count {
                return String(
                    decoding: buffer.prefix(Int(result)).map { UInt8(bitPattern: $0) },
                    as: UTF8.self
                )
            }
            capacity *= 2
        }
        throw TOMLDiagnostic(
            kind: .io,
            message: "Symbolic-link target exceeds the supported length",
            fileURL: fileURL
        )
    }

    private static func openFailure(code: Int32, fileURL: URL) throws -> TOMLDiagnostic {
        if code == ENOENT || code == ELOOP { throw RetryPathResolution() }
        return pathDiagnostic("Could not open TOML path component", code: code, fileURL: fileURL)
    }

    private static func path(in directories: [Directory], appending name: String) -> String {
        path(in: directories, appending: [name])
    }

    private static func path(in directories: [Directory], appending suffix: [String]) -> String {
        "/" + (directories.compactMap(\.name) + suffix).joined(separator: "/")
    }

    private static func sameIdentity(_ lhs: stat, _ rhs: stat) -> Bool {
        lhs.st_dev == rhs.st_dev && lhs.st_ino == rhs.st_ino
    }

    private static func pathDiagnostic(_ message: String, code: Int32, fileURL: URL) -> TOMLDiagnostic {
        let kind: TOMLDiagnostic.Kind = code == EACCES || code == EPERM ? .unreadable : .io
        return .init(
            kind: kind,
            message: "\(message): \(String(cString: strerror(code)))",
            fileURL: fileURL
        )
    }
}

private final class OwnedDescriptor {
    let rawValue: Int32

    init(_ rawValue: Int32) {
        self.rawValue = rawValue
    }

    deinit {
        Darwin.close(rawValue)
    }
}

private struct RetryPathResolution: Error {}

private struct FileIdentity: Hashable {
    let deviceID: UInt64
    let fileID: UInt64
}
