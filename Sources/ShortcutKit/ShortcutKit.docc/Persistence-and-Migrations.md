# Persistence and Migrations

Where customization is stored, how to make it portable, and how to rename actions
without losing user data.

## Overview

A ``ShortcutRegistry`` persists user customization through a pluggable
``ShortcutBindingsStore``. Only the bindings a user actually changes are written —
everything else falls back to the declared defaults — so the stored state stays
small and readable. The persisted shape is a ``RawState``: a map of context id →
action id → bindings, plus a ``Preferences`` section.

## Choosing a store

- ``UserDefaultsStore`` (the default) writes a compact JSON blob to
  `UserDefaults`. Best for "it just works" customization that rides along with the
  app's other defaults.
- ``FileStore`` writes a human-editable TOML or JSON file. Best when users (or you)
  want to read, hand-edit, sync, or check in the shortcut config.

```swift
let store = FileStore(url: configURL, format: .toml, key: "shortcuts")
let registry = ShortcutRegistry(contexts: contexts, store: store)
```

### Sharing a file with your own settings

`FileStore`'s `key:` namespaces ShortcutKit's data under a subtree, so the
library's section can live in the same file as your app's settings. Namespaced
TOML saves change individual assignments: comments, formatting, unknown keys,
line endings, and sibling tables stay as written. If changing an assignment
would remove a comment embedded in its value, the save fails with a
``TOMLDiagnostic`` instead.

For one application-wide transaction, construct a shared ``TOMLFile`` and use a
component-based namespace. This also supports quoted identifiers containing a
dot without treating them as multiple path components.

```swift
let file = TOMLFile(url: configURL)
let shortcutStore = FileStore(tomlFile: file, namespace: ["shortcuts"])
```

Read one immutable snapshot, strictly decode ShortcutKit's section, compose its
edit plan with your settings edits, validate the combined candidate, and commit
once:

```swift
let snapshot = try file.read()
let base = try shortcutStore.decode(snapshot, mode: .strict)
var desired = base
desired[context: "editor", action: "save"] = ["cmd+s"]
var settingsEdits = TOMLEditPlan()
settingsEdits.set(.integer(12), at: ["settings", "window-gap"])
let edits = settingsEdits.appending(try shortcutStore.editPlan(from: base, to: desired))
let candidate = try file.candidate(from: snapshot, applying: edits)
let committed = try file.commit(candidate)
```

Strict decoding accepts both snapshots and uncommitted candidates, and rejects
malformed shortcut values, preference values, and reserved table shapes with a
component path and source position. The default `.compatible` mode retains the
historical leniency of `FileStore.load()`.
Candidate creation is pure; ``TOMLFile/commit(_:)`` rejects a stale source
rather than overwriting it. ``TOMLFile/create(_:)`` atomically creates a missing
file without replacing one that appeared in the meantime.

`TOMLFile` follows symlinks component by component while retaining the logical
URL. Replacing a symlinked file updates its referent and leaves the symlink in
place. File watching and whole-application schema validation remain the
adopter's responsibility.

### Re-reading after out-of-band changes

If the file changes underneath you — a hand edit, a sync, a restore — call
``ShortcutRegistry/reload()`` to re-read the store and refresh bindings,
conflicts, and the published `keyBindings`. It flushes a pending local edit
first. Namespaced TOML stores merge those local changes into the latest file,
so an unrelated outside edit is retained. The Boolean method returns `true`
only when the complete reload and any migration write-back succeed.

Use ``ShortcutRegistry/reloadResult()`` when the caller needs to distinguish a
pending-save failure, load failure, migration failure, or a live reload whose
migrated representation could not be written back. The last case updates the
runtime state and leaves it pending for a later save.

An adopter that stages multiple schemas can use
``ShortcutRegistry/prepare(_:)`` without changing live state, then apply the
opaque result with `try` ``ShortcutRegistry/commit(_:)`` after its aggregate
file transaction succeeds. Prepared state belongs to the registry and
generation that created it and can be applied only once. The static
``ShortcutRegistry/prepare(_:migrations:)`` validates and migrates data without
creating registry-applicable state. Observe ``ShortcutRegistry/saveResults``
for a receipt after each registry-initiated store attempt. A file-invalid
rollback must be explicit through `try`
``ShortcutRegistry/discardPendingSave(applying:)``.

### Wiping customization

``ShortcutBindingsStore/clear()`` removes all persisted state; the next load falls
back to declared defaults. It's available on every store.

## Preferences

Beyond bindings, the registry persists a small ``Preferences`` section through the
same store — currently the user's hint-visibility choice
(``ShortcutRegistry/hintsEnabled``), stored only when it diverges from the app's
default.

## Migrations

Action raw values and context ids are **stable persistence ids**. To rename one
without orphaning a user's saved override, append a ``ShortcutMigration`` to the
registry. Migrations are append-only and idempotent (content-detecting), so the
list only grows and re-running it is safe — no version counter needed.

```swift
ShortcutRegistry(
    contexts: contexts,
    migrations: [
        .renameAction(context: "editor", from: "save", to: "saveDocument"),
        .renameContext(from: "panel", to: "inspector"),
    ]
)
```

The cases:

- `.renameAction(context:from:to:)` — an action's raw value changed.
- `.moveAction(from:to:)` — an action moved between contexts (uses ``ActionRef``).
- `.renameContext(from:to:)` — a context id changed.
- `.resetOverride(context:action:)` — drop a stored override (e.g. a default
  changed and you want users back on it).
- `.custom { state in … }` — arbitrary rewrites of the ``RawState``.

Initialization preserves the historical best-effort migration behavior: a
throwing custom migration is logged and later entries still run. Explicit
preparation and reload are transactional; a thrown migration leaves live state
unchanged and is reported by ``ShortcutRegistry/reloadResult()``.

## Diagnostics

``RawState`` is `CustomDebugStringConvertible` — its `debugDescription` is a
TOML-ish dump (contexts, actions, binding display strings, and non-default
preferences) suitable for bug reports.

## Topics

### Related Types

- ``ShortcutBindingsStore``
- ``UserDefaultsStore``
- ``FileStore``
- ``TOMLFile``
- ``TOMLPath``
- ``TOMLValue``
- ``TOMLEditPlan``
- ``TOMLDiagnostic``
- ``TOMLSourceLocation``
- ``RawState``
- ``Preferences``
- ``ShortcutSaveResult``
- ``ShortcutReloadResult``
- ``ShortcutMigration``
- ``ActionRef``
