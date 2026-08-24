import Foundation
import Testing

/// Every `uiString(_:)` call site must have an entry in `Localizable.strings`.
///
/// A missing key is invisible in English: `String(localized:)` falls back to the
/// key, and the keys here *are* the English text, so the UI looks correct and
/// every other test passes. The gap only surfaces once a second `.lproj` exists,
/// at which point those strings silently stay English. This scans the sources so
/// the drift fails CI instead.
///
/// Scanning source from a test is unusual, but the call sites are literals that
/// exist nowhere at runtime — there is nothing else to compare the catalog to.
@MainActor
struct LocalizationCoverageTests {
    /// Walks up from this file to the package root, then down to the target.
    private static func packageRelative(_ path: String, from file: StaticString = #filePath) -> URL? {
        var dir = URL(fileURLWithPath: "\(file)").deletingLastPathComponent()
        while dir.path != "/" {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("Package.swift").path) {
                return dir.appendingPathComponent(path)
            }
            dir = dir.deletingLastPathComponent()
        }
        return nil
    }

    /// `uiString("Blocker: \(x)")` resolves to the key `"Blocker: %@"`, so
    /// interpolation segments collapse the same way before comparison.
    private static func normalizeInterpolation(_ literal: String) -> String {
        var out = ""
        var rest = Substring(literal)
        while let open = rest.range(of: "\\(") {
            out += rest[rest.startIndex ..< open.lowerBound]
            var depth = 1
            var index = open.upperBound
            while index < rest.endIndex, depth > 0 {
                if rest[index] == "(" { depth += 1 }
                if rest[index] == ")" { depth -= 1 }
                index = rest.index(after: index)
            }
            out += "%@"
            rest = rest[index...]
        }
        return out + rest
    }

    private static func callSiteKeys(in sourceDir: URL) throws -> Set<String> {
        guard let files = FileManager.default.enumerator(at: sourceDir, includingPropertiesForKeys: nil)
        else { return [] }
        var keys: Set<String> = []
        // Matches uiString("…") where … has no unescaped quote.
        let pattern = try NSRegularExpression(pattern: #"uiString\(\s*"((?:[^"\\]|\\.)*)"\s*\)"#)
        for case let url as URL in files where url.pathExtension == "swift" {
            guard let source = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let range = NSRange(source.startIndex ..< source.endIndex, in: source)
            for match in pattern.matches(in: source, range: range) {
                guard let literalRange = Range(match.range(at: 1), in: source) else { continue }
                keys.insert(normalizeInterpolation(String(source[literalRange])))
            }
        }
        return keys
    }

    private static func catalogKeys(at file: URL) throws -> Set<String> {
        guard let contents = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        var keys: Set<String> = []
        let pattern = try NSRegularExpression(pattern: #"^"((?:[^"\\]|\\.)*)"\s*="#, options: [.anchorsMatchLines])
        let range = NSRange(contents.startIndex ..< contents.endIndex, in: contents)
        for match in pattern.matches(in: contents, range: range) {
            guard let keyRange = Range(match.range(at: 1), in: contents) else { continue }
            keys.insert(String(contents[keyRange]))
        }
        return keys
    }

    @Test("every uiString call site has a Localizable.strings entry")
    func everyCallSiteIsBacked() throws {
        let sources = try #require(Self.packageRelative("Sources/ShortcutKitUI"))
        let catalog = try #require(
            Self.packageRelative("Sources/ShortcutKitUI/Resources/en.lproj/Localizable.strings")
        )

        let called = try Self.callSiteKeys(in: sources)
        // A regression in the scanner itself would silently pass an empty set.
        #expect(called.count > 20)

        let missing = try called.subtracting(Self.catalogKeys(at: catalog)).sorted()
        #expect(missing.isEmpty, "uiString keys with no Localizable.strings entry: \(missing)")
    }

    @Test("Localizable.strings has no entries that nothing calls")
    func noDeadEntries() throws {
        let sources = try #require(Self.packageRelative("Sources/ShortcutKitUI"))
        let catalog = try #require(
            Self.packageRelative("Sources/ShortcutKitUI/Resources/en.lproj/Localizable.strings")
        )

        let dead = try Self.catalogKeys(at: catalog).subtracting(Self.callSiteKeys(in: sources)).sorted()
        #expect(dead.isEmpty, "Localizable.strings entries no uiString call site uses: \(dead)")
    }
}
