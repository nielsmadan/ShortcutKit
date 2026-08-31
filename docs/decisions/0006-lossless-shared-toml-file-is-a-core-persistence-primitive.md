# 0006 — Lossless shared TOML file is a Core persistence primitive

Date: 2026-08-30 · Status: Accepted

## Context

`FileStore` can place ShortcutKit state below a dotted TOML key and preserves
sibling values semantically. Its current TOMLKit round-trip serializes the whole
document, however, so it discards comments and formatting. Two independently
constructed stores can also read and replace the same file without coordinating
their writes.

Juggler needs ordinary settings and ShortcutKit overrides in one user-edited
file. UI edits must retain comments and unknown content, and a settings write
must not race a shortcut write. These requirements are not specific to
Juggler: they follow from `FileStore` advertising namespaced, human-editable
persistence in a shared file.

## Decision

Add one additive public Core type, `TOMLFile`, representing a coordinated TOML
file. It provides immutable, `Sendable` snapshots containing source text and a
content revision, lossless assignment-level edits, serialized in-process
writes, atomic replacement, and structured source diagnostics. `FileStore`
gains an initializer that accepts a shared instance and a way to decode
`RawState` from a supplied snapshot. Existing URL initializers continue to work
and create their own instance internally.

The lossless layer preserves untouched source bytes, including comments,
whitespace, table ordering, and unknown content. A changed assignment may use
canonical formatting. Deleting an assignment does not intentionally delete
adjacent comments.

ShortcutKit continues to own shortcut encoding, decoding, preferences, and
migrations. The shared file primitive does not model application settings.
File watching, source selection, whole-application validation, UI, and runtime
effects remain adopter responsibilities. JSON behavior is unchanged.

## Consequences

- Adopters can safely compose `FileStore` with another store in one TOML file
  without using ShortcutKit as their general settings framework.
- Applications that need an all-or-nothing reload can decode settings and
  shortcuts from one coherent snapshot before applying either.
- Structured diagnostics become public API because adopters must render useful
  errors for hand-edited files.
- Existing `FileStore` source compatibility is preserved.
- All in-process writers must share the same file instance to receive the
  serialization guarantee.
- Atomic writes prevent torn files but cannot eliminate a last-writer-wins race
  with an uncooperative external editor. Writers patch the latest readable
  source immediately before replacement to minimize that window.
- The lossless editing contract requires source-aware parsing in addition to
  TOMLKit's semantic AST.
