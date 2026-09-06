import Foundation
@testable import ShortcutKit
import Testing

@MainActor
@Suite("TOMLSourceDocument")
struct TOMLSourceDocumentTests {
    private let url = URL(fileURLWithPath: "/tmp/config.toml")

    @Test("unedited source round-trips byte-for-byte")
    func byteIdenticalRoundTrip() throws {
        let source =
            "\u{FEFF}# Header\r\n[settings]\r\ncolor = \"#FFA500\" # keep\r\n\r\n[unknown]\r\nvalue = 'as written'\r\n"
        let document = try makeDocument(source)

        #expect(document.data == Data(source.utf8))
    }

    @Test("invalid UTF-8 is rejected")
    func invalidUTF8() {
        do {
            _ = try TOMLSourceDocument(data: Data([0xFF]), fileURL: url)
            Issue.record("expected invalid UTF-8 to fail")
        } catch let diagnostic as TOMLDiagnostic {
            #expect(diagnostic.kind == .invalidUTF8)
            #expect(diagnostic.fileURL == url)
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test("files larger than one MiB are rejected")
    func sizeLimit() {
        let data = Data(repeating: 0x20, count: TOMLSourceDocument.maximumByteCount + 1)
        do {
            _ = try TOMLSourceDocument(data: data, fileURL: url)
            Issue.record("expected oversized input to fail")
        } catch let diagnostic as TOMLDiagnostic {
            #expect(diagnostic.kind == .tooLarge)
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test("syntax diagnostics include TOMLKit source coordinates")
    func syntaxLocation() {
        do {
            _ = try makeDocument("[settings]\ngap = 01\n")
            Issue.record("expected invalid TOML to fail")
        } catch let diagnostic as TOMLDiagnostic {
            #expect(diagnostic.kind == .syntax)
            #expect(diagnostic.location?.line == 2)
            #expect(diagnostic.location?.column != nil)
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test("setting an existing scalar preserves surrounding bytes")
    func replaceScalar() throws {
        let source = "[settings]\r\n  gap  =  8   # keep\r\nunknown = 'as written'\r\n"
        var plan = TOMLEditPlan()
        plan.set(.integer(12), at: ["settings", "gap"])

        let output = try makeDocument(source).applying(plan).source

        #expect(output == "[settings]\r\n  gap  =  12   # keep\r\nunknown = 'as written'\r\n")
    }

    @Test("replacing a value preserves a missing final newline")
    func replaceWithoutFinalNewline() throws {
        let source = "[settings]\ngap = 8"
        var plan = TOMLEditPlan()
        plan.set(.integer(12), at: ["settings", "gap"])

        let output = try makeDocument(source).applying(plan).source

        #expect(output == "[settings]\ngap = 12")
    }

    @Test("Unicode and quoted keys remain literal components")
    func unicodeQuotedKeys() throws {
        let source = "[\"réglages.app\"]\n\"fenêtre.écart\" = 8\n"
        var plan = TOMLEditPlan()
        plan.set(.integer(10), at: ["réglages.app", "fenêtre.écart"])

        let output = try makeDocument(source).applying(plan).source

        #expect(output == "[\"réglages.app\"]\n\"fenêtre.écart\" = 10\n")
    }

    @Test("TOML paths quote non-ASCII and control-character components")
    func pathDescriptionUsesValidTOMLKeys() {
        #expect(TOMLPath(["shortcuts", "naïve", "line\nfeed"]).description == "shortcuts.\"naïve\".\"line\\nfeed\"")
    }

    @Test("quoted action IDs are literal path components")
    func quotedActionID() throws {
        let source = "[shortcuts.global]\n\"window.focus.left\" = \"opt+h\" # keep\n"
        var plan = TOMLEditPlan()
        plan.set(.string("cmd+left"), at: ["shortcuts", "global", "window.focus.left"])

        let output = try makeDocument(source).applying(plan).source

        #expect(output == "[shortcuts.global]\n\"window.focus.left\" = \"cmd+left\" # keep\n")
    }

    @Test("an inserted assignment follows an existing table's CRLF style")
    func insertIntoExistingTable() throws {
        let source = "[settings]\r\ngap = 8\r\n"
        var plan = TOMLEditPlan()
        plan.set(.boolean(true), at: ["settings", "animations"])

        let output = try makeDocument(source).applying(plan).source

        #expect(output == "[settings]\r\ngap = 8\r\nanimations = true\r\n")
    }

    @Test("a new table follows the document's CRLF style")
    func createTableWithCRLF() throws {
        let source = "[unknown]\r\nvalue = true\r\n"
        var plan = TOMLEditPlan()
        plan.set(.integer(8), at: ["settings", "gap"])

        let output = try makeDocument(source).applying(plan).source

        #expect(output == "[unknown]\r\nvalue = true\r\n\r\n[settings]\r\ngap = 8\r\n")
    }

    @Test("deleting an assignment retains preceding and trailing comments")
    func deletePreservesComments() throws {
        let source = "[settings]\n# why this was customized\ngap = 8 # keep this note\ncolor = \"blue\"\n"
        var plan = TOMLEditPlan()
        plan.remove(at: ["settings", "gap"])

        let output = try makeDocument(source).applying(plan).source

        #expect(output == "[settings]\n# why this was customized\n# keep this note\ncolor = \"blue\"\n")
    }

    @Test("deleting an uncommented assignment changes no sibling bytes")
    func deleteWithoutComments() throws {
        let source = "[settings]\ngap = 8\ncolor = \"blue\"\n"
        var plan = TOMLEditPlan()
        plan.remove(at: ["settings", "gap"])

        let output = try makeDocument(source).applying(plan).source

        #expect(output == "[settings]\ncolor = \"blue\"\n")
    }

    @Test("editing a multiline value with an embedded comment is refused")
    func embeddedCommentEditRefused() throws {
        let source = "[shortcuts.global]\ncycle = [\n  \"cmd+j\", # primary\n  \"opt+j\",\n]\n"
        let document = try makeDocument(source)
        var plan = TOMLEditPlan()
        plan.set(.array([.string("cmd+j")]), at: ["shortcuts", "global", "cycle"])

        do {
            _ = try document.applying(plan)
            Issue.record("expected the unsafe edit to fail")
        } catch let diagnostic as TOMLDiagnostic {
            #expect(diagnostic.kind == .unsupportedEdit)
            #expect(diagnostic.path == TOMLPath(["shortcuts", "global", "cycle"]))
            #expect(diagnostic.location == .init(line: 2, column: 1))
        }
        #expect(document.data == Data(source.utf8))
    }

    @Test("deleting a multiline value with an embedded comment is refused")
    func embeddedCommentDeleteRefused() throws {
        let source = "[shortcuts.global]\ncycle = [\n  \"cmd+j\", # primary\n]\n"
        var plan = TOMLEditPlan()
        plan.remove(at: ["shortcuts", "global", "cycle"])

        do {
            _ = try makeDocument(source).applying(plan)
            Issue.record("expected the unsafe deletion to fail")
        } catch let diagnostic as TOMLDiagnostic {
            #expect(diagnostic.kind == .unsupportedEdit)
        }
    }

    @Test("nested inline-table fields can be inserted, replaced, and removed")
    func inlineTableEdits() throws {
        let source = "settings = { gap = 8, color = \"red\" }\n"
        var plan = TOMLEditPlan()
        plan.set(.string("blue"), at: ["settings", "color"])
        plan.set(.boolean(true), at: ["settings", "animations"])
        plan.remove(at: ["settings", "gap"])

        let output = try makeDocument(source).applying(plan)

        #expect(try output.value(at: ["settings", "color"]) == .string("blue"))
        #expect(try output.value(at: ["settings", "animations"]) == .boolean(true))
        #expect(try output.value(at: ["settings", "gap"]) == nil)
    }

    @Test("inserting below an array of tables is refused")
    func arrayOfTablesInsertionRefused() throws {
        let source = "[[plugin]]\nname = \"first\"\n"
        var plan = TOMLEditPlan()
        plan.set(.boolean(true), at: ["plugin", "enabled"])

        do {
            _ = try makeDocument(source).applying(plan)
            Issue.record("expected the ambiguous insertion to fail")
        } catch let diagnostic as TOMLDiagnostic {
            #expect(diagnostic.kind == .unsupportedEdit)
            #expect(diagnostic.path == TOMLPath(["plugin", "enabled"]))
        }
    }

    @Test("a structural conflict returns no candidate")
    func structuralConflictRefused() throws {
        let source = "settings.gap = 8\n"
        var plan = TOMLEditPlan()
        plan.set(.string("blue"), at: ["settings", "color"])

        #expect(throws: TOMLDiagnostic.self) {
            _ = try makeDocument(source).applying(plan)
        }
    }

    @Test("inserting into an empty table whose header ends at EOF adds a newline")
    func insertIntoHeaderAtEOF() throws {
        var plan = TOMLEditPlan()
        plan.set(.integer(8), at: ["settings", "gap"])

        let output = try makeDocument("[settings]").applying(plan)

        #expect(output.source == "[settings]\ngap = 8\n")
    }

    @Test("multiline strings closed by four or five quotes retain following comments and entries")
    func multilineStringClosingQuotes() throws {
        for closingQuotes in ["\"\"\"\"", "\"\"\"\"\""] {
            let source = "[settings]\ntext = \"\"\"value\(closingQuotes) # keep\nother = 1\n"
            var plan = TOMLEditPlan()
            plan.set(.string("changed"), at: ["settings", "text"])

            let output = try makeDocument(source).applying(plan)

            #expect(output.source == "[settings]\ntext = \"changed\" # keep\nother = 1\n")
        }
    }

    @Test("a present temporal value reports an unsupported-value diagnostic")
    func unsupportedTemporalValue() throws {
        let document = try makeDocument("[settings]\nbirthday = 1979-05-27\n")

        do {
            _ = try document.value(at: ["settings", "birthday"])
            Issue.record("expected the temporal value to be rejected")
        } catch let diagnostic as TOMLDiagnostic {
            #expect(diagnostic.kind == .unsupportedValue)
            #expect(diagnostic.path == TOMLPath(["settings", "birthday"]))
            #expect(diagnostic.location == .init(line: 2, column: 1))
        }
    }

    @Test("hand-edited fixture round-trips and supports a local edit")
    func handEditedFixture() throws {
        let fixture = try #require(Bundle.module.url(
            forResource: "hand-edited",
            withExtension: "toml",
            subdirectory: "Fixtures/TOML"
        ))
        let data = try Data(contentsOf: fixture)
        let document = try TOMLSourceDocument(data: data, fileURL: fixture)
        var plan = TOMLEditPlan()
        plan.set(.string("cmd+h"), at: ["shortcuts", "global", "window.focus.left"])

        let output = try document.applying(plan)

        #expect(document.data == data)
        #expect(try output.value(at: ["shortcuts", "global", "window.focus.left"]) == .string("cmd+h"))
        #expect(try output.value(at: ["settings", "theme"]) == .string("solarized"))
        #expect(output.source.contains("enabled = true # unknown to ShortcutKit"))
    }

    @Test("deterministic source variants remain valid after editing")
    func deterministicVariants() throws {
        for newline in ["\n", "\r\n"] {
            for prefix in ["", "\u{FEFF}"] {
                let source = prefix + [
                    "# configuration",
                    "[settings]",
                    "gap = 8 # retained",
                    "[unknown]",
                    "label = 'unchanged'",
                    "",
                ].joined(separator: newline)
                var plan = TOMLEditPlan()
                plan.set(.integer(12), at: ["settings", "gap"])

                let output = try makeDocument(source).applying(plan)

                #expect(try output.value(at: ["settings", "gap"]) == .integer(12))
                #expect(try output.value(at: ["unknown", "label"]) == .string("unchanged"))
                #expect(output.source.contains("gap = 12 # retained"))
                #expect(output.source.hasPrefix(prefix))
            }
        }
    }

    @Test("lookup and path enumeration use component paths")
    func lookupAndPaths() throws {
        let document = try makeDocument(
            "[shortcuts.global]\n\"window.focus.left\" = [\"cmd+left\", { gesture = \"opt+scroll\", sensitivity = 1.25 }]\n"
        )

        #expect(try document.value(at: ["shortcuts", "global", "window.focus.left"]) == .array([
            .string("cmd+left"),
            .inlineTable([
                "gesture": .string("opt+scroll"),
                "sensitivity": .float(1.25),
            ]),
        ]))
        #expect(document.assignmentPaths() == [["shortcuts", "global", "window.focus.left"]])
    }

    @Test("assignment locations count Unicode scalars and CRLF lines")
    func assignmentLocation() throws {
        let document = try makeDocument("# 🪟\r\n[settings]\r\n# note\r\n  gap = 8\r\n")

        #expect(document.location(of: ["settings", "gap"]) == .init(line: 4, column: 3))
    }

    @Test("table-header locations point at the first key component")
    func tableHeaderLocation() throws {
        let document = try makeDocument("# note\n  [settings] # retained\n")

        #expect(document.location(of: ["settings"]) == .init(line: 2, column: 4))
    }

    private func makeDocument(_ source: String) throws -> TOMLSourceDocument {
        try TOMLSourceDocument(data: Data(source.utf8), fileURL: url)
    }
}
