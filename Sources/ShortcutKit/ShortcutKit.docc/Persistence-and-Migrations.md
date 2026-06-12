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

`FileStore`'s `key:` namespaces ShortcutKit's data under a subtree and does a
read-modify-write, so the library's section can live in the same file as your
app's other settings without clobbering them. `key: nil` puts the data at the file
root.

### Re-reading after out-of-band changes

If the file changes underneath you — a hand edit, a sync, a restore — call
``ShortcutRegistry/reload()`` to re-read the store and refresh bindings, conflicts,
and the published `keyBindings`. It returns `false` (and leaves current state
untouched) if the read fails.

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

## Diagnostics

``RawState`` is `CustomDebugStringConvertible` — its `debugDescription` is a
TOML-ish dump (contexts, actions, binding display strings, and non-default
preferences) suitable for bug reports.

## Topics

### Related Types

- ``ShortcutBindingsStore``
- ``UserDefaultsStore``
- ``FileStore``
- ``RawState``
- ``Preferences``
- ``ShortcutMigration``
- ``ActionRef``
