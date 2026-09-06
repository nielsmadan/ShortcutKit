import Foundation
import Toml
import TOMLKit

@MainActor
struct TOMLSourceDocument {
    static let maximumByteCount = 1_048_576

    let fileURL: URL
    let source: String
    let semanticRoot: TOMLTable
    var annotated: Toml.Annotated

    init(data: Data, fileURL: URL) throws {
        guard data.count <= Self.maximumByteCount else {
            throw TOMLDiagnostic(
                kind: .tooLarge,
                message: "TOML file exceeds the 1 MiB limit",
                fileURL: fileURL,
                expected: "at most \(Self.maximumByteCount) bytes"
            )
        }
        let source = String(decoding: data, as: UTF8.self)
        guard source.utf8.elementsEqual(data) else {
            throw TOMLDiagnostic(
                kind: .invalidUTF8,
                message: "TOML file is not valid UTF-8",
                fileURL: fileURL,
                expected: "UTF-8 text"
            )
        }
        let root: TOMLTable
        do {
            root = try TOMLTable(string: source)
        } catch let error as TOMLParseError {
            throw TOMLDiagnostic(
                kind: .syntax,
                message: error.description,
                fileURL: fileURL,
                location: .init(
                    line: error.source.begin.line,
                    column: error.source.begin.column
                )
            )
        } catch {
            throw TOMLDiagnostic(
                kind: .syntax,
                message: String(describing: error),
                fileURL: fileURL
            )
        }

        let annotated: Toml.Annotated
        do {
            annotated = try Toml.Annotated(parsing: source)
        } catch let error as Toml.ParseError {
            throw TOMLDiagnostic(
                kind: .syntax,
                message: error.message,
                fileURL: fileURL,
                location: .init(line: max(error.line, 1), column: 1)
            )
        }

        self.fileURL = fileURL
        self.source = source
        semanticRoot = root
        self.annotated = annotated
    }

    var data: Data { Data(annotated.render().utf8) }

    func applying(_ plan: TOMLEditPlan) throws -> Self {
        var copy = self
        for operation in plan.operations {
            switch operation {
            case let .set(path, value):
                try copy.set(value, at: path)
            case let .remove(path):
                try copy.remove(at: path)
            }
        }
        return try Self(data: copy.data, fileURL: fileURL)
    }

    func value(at path: TOMLPath) -> TOMLValue? {
        guard let leaf = path.components.last else { return nil }
        var table = semanticRoot
        for component in path.components.dropLast() {
            guard let next = table[component]?.table else { return nil }
            table = next
        }
        guard let value = table[leaf] else { return nil }
        return Self.convert(value)
    }

    func assignmentPaths() -> Set<TOMLPath> {
        var result = Set(annotated.root.entries.map { TOMLPath($0.key) })
        for block in annotated.blocks {
            for entry in block.body.entries {
                result.insert(TOMLPath(block.path + entry.key))
            }
        }
        return result
    }

    func location(of path: TOMLPath) -> TOMLSourceLocation? {
        guard let location = entryLocation(for: path) else { return nil }
        var offset = annotated.leading.unicodeScalars.count

        for (index, entry) in annotated.root.entries.enumerated() {
            offset += entry.leading.unicodeScalars.count
            if location.blockIndex == nil, location.entryIndex == index {
                return sourceLocation(at: offset + Self.keyOffset(in: entry.raw))
            }
            offset += entry.raw.unicodeScalars.count
        }
        offset += annotated.root.trailing.unicodeScalars.count

        for (blockIndex, block) in annotated.blocks.enumerated() {
            offset += block.leading.unicodeScalars.count
            if block.path == path.components {
                return sourceLocation(at: offset + Self.headerKeyOffset(in: block.headerRaw))
            }
            offset += block.headerRaw.unicodeScalars.count
            for (entryIndex, entry) in block.body.entries.enumerated() {
                offset += entry.leading.unicodeScalars.count
                if location.blockIndex == blockIndex, location.entryIndex == entryIndex {
                    return sourceLocation(at: offset + Self.keyOffset(in: entry.raw))
                }
                offset += entry.raw.unicodeScalars.count
            }
            offset += block.body.trailing.unicodeScalars.count
        }
        return nil
    }

    private mutating func set(_ value: TOMLValue, at path: TOMLPath) throws {
        guard !path.components.isEmpty else {
            throw diagnostic("Cannot assign the TOML document root", path: path)
        }
        if let location = entryLocation(for: path) {
            var entry = entry(at: location)
            guard let layout = AssignmentLayout(raw: entry.raw) else {
                throw diagnostic("Could not locate the assignment value", path: path)
            }
            guard !layout.hasCommentInsideValue else {
                throw diagnostic(
                    "Editing this value would remove an embedded comment; edit it in the file instead",
                    path: path,
                    location: self.location(of: path)
                )
            }
            entry.raw = layout.replacingValue(in: entry.raw, with: value.encoded)
            entry.valueText = value.encoded
            replaceEntry(at: location, with: entry)
            return
        }
        try insert(value, at: path)
    }

    private mutating func remove(at path: TOMLPath) throws {
        guard let location = entryLocation(for: path) else { return }
        let removed = entry(at: location)
        guard let layout = AssignmentLayout(raw: removed.raw) else {
            throw diagnostic("Could not locate the assignment value", path: path)
        }
        guard !layout.hasCommentInsideValue else {
            throw diagnostic(
                "Removing this value would remove an embedded comment; edit it in the file instead",
                path: path,
                location: self.location(of: path)
            )
        }
        let preserved = removed.leading + layout.standaloneTrailingComments(from: removed.raw)
        removeEntry(at: location, preserving: preserved)
    }

    private mutating func insert(_ value: TOMLValue, at path: TOMLPath) throws {
        let parent = Array(path.components.dropLast())
        let leaf = path.components[path.components.count - 1]
        if parent.isEmpty {
            annotated.root = Self.appending(
                entryForKey: leaf,
                value: value,
                to: annotated.root,
                fallbackNewline: newlineStyle
            )
            return
        }

        if let blockIndex = annotated.blocks.firstIndex(where: {
            $0.kind == .table && $0.path == parent
        }) {
            annotated.blocks[blockIndex].body = Self.appending(
                entryForKey: leaf,
                value: value,
                to: annotated.blocks[blockIndex].body,
                fallbackNewline: Self.newline(in: annotated.blocks[blockIndex].headerRaw) ?? newlineStyle
            )
            return
        }

        guard entryLocation(for: TOMLPath(parent)) == nil else {
            throw diagnostic("Cannot insert below a value or inline table", path: path)
        }
        guard !annotated.blocks.contains(where: {
            $0.kind == .arrayElement && parent.starts(with: $0.path)
        }) else {
            throw diagnostic("Cannot insert an assignment below an array of tables", path: path)
        }

        let newline = newlineStyle
        let rendered = annotated.render()
        if !rendered.isEmpty, !rendered.hasSuffix("\n") {
            if annotated.blocks.isEmpty {
                annotated.root.trailing += newline
            } else {
                annotated.blocks[annotated.blocks.count - 1].body.trailing += newline
            }
        }
        let refreshed = annotated.render()
        let separator = refreshed.isEmpty || refreshed.hasSuffix(newline + newline) ? "" : newline
        annotated.blocks.append(.init(
            leading: separator,
            kind: .table,
            headerRaw: "[\(parent.map(Self.encodeKey).joined(separator: "."))]\(newline)",
            path: parent,
            body: .init(entries: [Self.makeEntry(key: leaf, value: value, indent: "", newline: newline)])
        ))
    }

    private func entryLocation(for path: TOMLPath) -> EntryLocation? {
        var matches: [EntryLocation] = []
        for (entryIndex, entry) in annotated.root.entries.enumerated()
            where entry.key == path.components
        {
            matches.append(.init(blockIndex: nil, entryIndex: entryIndex))
        }
        for (blockIndex, block) in annotated.blocks.enumerated() where block.kind == .table {
            guard path.components.starts(with: block.path) else { continue }
            let remainder = Array(path.components.dropFirst(block.path.count))
            for (entryIndex, entry) in block.body.entries.enumerated() where entry.key == remainder {
                matches.append(.init(blockIndex: blockIndex, entryIndex: entryIndex))
            }
        }
        return matches.count == 1 ? matches[0] : nil
    }

    private func entry(at location: EntryLocation) -> Toml.Annotated.Entry {
        if let blockIndex = location.blockIndex {
            return annotated.blocks[blockIndex].body.entries[location.entryIndex]
        }
        return annotated.root.entries[location.entryIndex]
    }

    private mutating func replaceEntry(at location: EntryLocation, with entry: Toml.Annotated.Entry) {
        if let blockIndex = location.blockIndex {
            annotated.blocks[blockIndex].body.entries[location.entryIndex] = entry
        } else {
            annotated.root.entries[location.entryIndex] = entry
        }
    }

    private mutating func removeEntry(at location: EntryLocation, preserving text: String) {
        if let blockIndex = location.blockIndex {
            var body = annotated.blocks[blockIndex].body
            body.entries.remove(at: location.entryIndex)
            Self.prepend(text, afterRemovedIndex: location.entryIndex, in: &body)
            annotated.blocks[blockIndex].body = body
        } else {
            annotated.root.entries.remove(at: location.entryIndex)
            Self.prepend(text, afterRemovedIndex: location.entryIndex, in: &annotated.root)
        }
    }

    private static func prepend(_ text: String, afterRemovedIndex index: Int, in body: inout Toml.Annotated.Body) {
        if body.entries.indices.contains(index) {
            body.entries[index].leading = text + body.entries[index].leading
        } else {
            body.trailing = text + body.trailing
        }
    }

    private static func appending(
        entryForKey key: String,
        value: TOMLValue,
        to body: Toml.Annotated.Body,
        fallbackNewline: String
    ) -> Toml.Annotated.Body {
        var copy = body
        let indent: String
        let newline: String
        if let sibling = copy.entries.last {
            indent = String(sibling.raw.prefix { $0 == " " || $0 == "\t" })
            newline = Self.newline(in: sibling.raw) ?? fallbackNewline
            if sibling.raw.unicodeScalars.last != "\n" {
                copy.entries[copy.entries.count - 1].raw += newline
            }
        } else {
            indent = ""
            newline = fallbackNewline
        }
        copy.entries.append(makeEntry(key: key, value: value, indent: indent, newline: newline))
        return copy
    }

    private static func makeEntry(
        key: String,
        value: TOMLValue,
        indent: String,
        newline: String
    ) -> Toml.Annotated.Entry {
        .init(
            leading: "",
            raw: "\(indent)\(encodeKey(key)) = \(value.encoded)\(newline)",
            key: [key],
            valueText: value.encoded
        )
    }

    private static func encodeKey(_ key: String) -> String {
        if !key.isEmpty, key.unicodeScalars.allSatisfy({
            ($0 >= "A" && $0 <= "Z") || ($0 >= "a" && $0 <= "z")
                || ($0 >= "0" && $0 <= "9") || $0 == "_" || $0 == "-"
        }) {
            return key
        }
        return Toml.encode(.string(key))
    }

    private var newlineStyle: String {
        source.contains("\r\n") ? "\r\n" : "\n"
    }

    private static func newline(in text: String) -> String? {
        if text.contains("\r\n") { return "\r\n" }
        if text.contains("\n") { return "\n" }
        return nil
    }

    private func sourceLocation(at scalarOffset: Int) -> TOMLSourceLocation {
        let scalars = Array(source.unicodeScalars)
        var line = 1
        var column = 1
        var index = 0
        while index < min(scalarOffset, scalars.count) {
            if scalars[index] == "\r", index + 1 < scalars.count, scalars[index + 1] == "\n" {
                line += 1
                column = 1
                index += 2
                continue
            } else if scalars[index] == "\n" {
                line += 1
                column = 1
                index += 1
                continue
            }
            column += 1
            index += 1
        }
        return .init(line: line, column: column)
    }

    private static func keyOffset(in raw: String) -> Int {
        raw.unicodeScalars.prefix { $0 == " " || $0 == "\t" }.count
    }

    private static func headerKeyOffset(in raw: String) -> Int {
        raw.unicodeScalars.prefix { $0 == " " || $0 == "\t" || $0 == "[" }.count
    }

    private func diagnostic(
        _ message: String,
        path: TOMLPath,
        location: TOMLSourceLocation? = nil
    ) -> TOMLDiagnostic {
        .init(
            kind: .unsupportedEdit,
            message: message,
            fileURL: fileURL,
            path: path,
            location: location
        )
    }

    private static func convert(_ value: any TOMLValueConvertible) -> TOMLValue? {
        switch value.type {
        case .string:
            value.string.map(TOMLValue.string)
        case .int:
            value.int.map { .integer(Int64($0)) }
        case .double:
            value.double.map(TOMLValue.float)
        case .bool:
            value.bool.map(TOMLValue.boolean)
        case .array:
            value.array.flatMap { array in
                var result: [TOMLValue] = []
                for element in array {
                    guard let converted = convert(element) else { return nil }
                    result.append(converted)
                }
                return .array(result)
            }
        case .table:
            value.table.flatMap { table in
                var result: [String: TOMLValue] = [:]
                for key in table.keys {
                    guard let child = table[key], let converted = convert(child) else { return nil }
                    result[key] = converted
                }
                return .inlineTable(result)
            }
        case .date, .time, .dateTime:
            nil
        }
    }
}

private struct EntryLocation {
    let blockIndex: Int?
    let entryIndex: Int
}

private struct AssignmentLayout {
    let valueRange: Range<Int>
    let commentRanges: [Range<Int>]

    init?(raw: String) {
        let scalars = Array(raw.unicodeScalars)
        guard let equal = Self.firstEquals(in: scalars) else { return nil }
        var start = equal + 1
        while start < scalars.count, scalars[start] == " " || scalars[start] == "\t" {
            start += 1
        }

        var index = start
        var end = start
        var comments: [Range<Int>] = []
        while index < scalars.count {
            let scalar = scalars[index]
            if scalar == "#" {
                let commentStart = index
                while index < scalars.count, scalars[index] != "\n" {
                    index += 1
                }
                comments.append(commentStart ..< index)
            } else if scalar == "\"" || scalar == "'" {
                index = Self.endOfQuotedToken(in: scalars, from: index)
                end = index
            } else if scalar == " " || scalar == "\t" || scalar == "\r" || scalar == "\n" {
                index += 1
            } else {
                index += 1
                end = index
            }
        }
        valueRange = start ..< end
        commentRanges = comments
    }

    var hasCommentInsideValue: Bool {
        commentRanges.contains { $0.lowerBound < valueRange.upperBound }
    }

    func replacingValue(in raw: String, with replacement: String) -> String {
        let scalars = Array(raw.unicodeScalars)
        return Self.string(scalars[..<valueRange.lowerBound])
            + replacement
            + Self.string(scalars[valueRange.upperBound...])
    }

    func standaloneTrailingComments(from raw: String) -> String {
        let scalars = Array(raw.unicodeScalars)
        var result = ""
        for range in commentRanges where range.lowerBound >= valueRange.upperBound {
            var lineStart = range.lowerBound
            while lineStart > 0, scalars[lineStart - 1] != "\n" {
                lineStart -= 1
            }
            let indent = scalars[lineStart ..< range.lowerBound].prefix { $0 == " " || $0 == "\t" }
            var comment = Array(scalars[range])
            if comment.last == "\r" { comment.removeLast() }
            result += Self.string(indent)
            result += Self.string(comment[...])
            if range.upperBound < scalars.count, scalars[range.upperBound] == "\n" {
                result += range.upperBound > 0 && scalars[range.upperBound - 1] == "\r" ? "\r\n" : "\n"
            }
        }
        return result
    }

    private static func firstEquals(in scalars: [Unicode.Scalar]) -> Int? {
        var index = 0
        while index < scalars.count {
            if scalars[index] == "\"" || scalars[index] == "'" {
                index = endOfQuotedToken(in: scalars, from: index)
            } else if scalars[index] == "=" {
                return index
            } else {
                index += 1
            }
        }
        return nil
    }

    private static func endOfQuotedToken(in scalars: [Unicode.Scalar], from start: Int) -> Int {
        let quote = scalars[start]
        let multiline = start + 2 < scalars.count
            && scalars[start + 1] == quote
            && scalars[start + 2] == quote
        let delimiterCount = multiline ? 3 : 1
        var index = start + delimiterCount
        while index < scalars.count {
            if quote == "\"", scalars[index] == "\\" {
                index = min(index + 2, scalars.count)
                continue
            }
            if multiline {
                if index + 2 < scalars.count,
                   scalars[index] == quote,
                   scalars[index + 1] == quote,
                   scalars[index + 2] == quote
                {
                    return index + 3
                }
            } else if scalars[index] == quote {
                return index + 1
            }
            index += 1
        }
        return scalars.count
    }

    private static func string(_ scalars: some Collection<Unicode.Scalar>) -> String {
        String(String.UnicodeScalarView(scalars))
    }
}
