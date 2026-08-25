# 0005 — Keep hand-maintained .strings, guarded by a coverage test

Date: 2026-08-24 · Status: Accepted

## Context

`Sources/ShortcutKitUI/Resources/en.lproj/Localizable.strings` is a legacy
hand-maintained catalogue. Four `uiString(…)` call sites in
`HintPreferencesView` had no entries — drift that arrived with a normal feature
commit and that nobody noticed.

It is invisible by construction: `String(localized:)` falls back to the key, and
the keys *are* the English text, so the UI renders correctly and every test
passes. It only surfaces once a second `.lproj` exists.

The modern answer is a String Catalog (`.xcstrings`), which Xcode populates from
source automatically.

## Decision

Keep the `.strings` file. Add `LocalizationCoverageTests`, which scans call
sites and fails on drift in both directions — missing entries and dead ones.

Migrating would not have fixed it. Key extraction is an Xcode build phase
(`SWIFT_EMIT_LOC_STRINGS`); `xcstringstool` only *compiles* an existing
catalogue. CI runs `swift build` / `swift test` / `swiftlint`, none of which
extract or validate keys **in either format**. The migration would have been
churn that left the same hole.

## Consequences

- Adding a `uiString(…)` call site requires a catalogue entry by hand; the test
  fails loudly if you forget.
- The test scans source from a test target, which is unusual — the call sites
  are literals that exist nowhere at runtime, so there is nothing else to
  compare against.
- Revisit if the package ever builds through an Xcode project, where extraction
  would actually run.
