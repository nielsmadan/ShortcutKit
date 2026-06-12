# ``ShortcutKit``

Declare keyboard shortcuts as Swift enums, group them into contexts, and let the
registry handle dispatch, user customization, persistence, and conflicts.

## Overview

ShortcutKit is the core of a small family of packages for adding
VS Code–style, user-customizable keyboard shortcuts to native macOS apps. The
mental model is three layers:

- **Actions** — a `String`-backed enum conforming to ``ShortcutAction``. Each case
  carries a ``ShortcutActionDefinition`` (display name, optional description, and
  default shortcut(s)). The raw value is the *stable persistence id*.
- **Contexts** — a ``ShortcutContext`` groups an action set and owns the dispatch
  of its actions. A context is `.local` (fires only while a view activates it) or
  `.global` (system-wide, via `ShortcutKitGlobal`).
- **The registry** — a ``ShortcutRegistry`` owns the contexts and is the hub for
  persistence, conflict detection, event routing, and the read API your menus and
  settings UI render from.

Customization is stored through a pluggable ``ShortcutBindingsStore`` (UserDefaults
by default, or a human-editable TOML/JSON ``FileStore``), and only the values a
user actually changes are written. Renames go through append-only
``ShortcutMigration``s so persisted ids stay stable forever.

This module re-exports [ShortcutField](https://github.com/nielsmadan/ShortcutField),
so `Shortcut`, `Shortcut.Step`, `ContinuousShortcut`, and related types are
available from a single `import ShortcutKit`.

To render a settings screen, legend, or discoverability HUD, add **ShortcutKitUI**.
For system-wide hotkeys, add **ShortcutKitGlobal**.

## Topics

### Essentials

- <doc:GettingStarted>

### Guides

- <doc:Contexts-and-Activation>
- <doc:Persistence-and-Migrations>
- <doc:Conflicts>

### Declaring Actions

- ``ShortcutAction``
- ``ShortcutActionDefinition``

### Contexts & Activation

- ``ShortcutContext``
- ``ContextScope``
- ``AnyShortcutContext``

### The Registry

- ``ShortcutRegistry``
- ``ActionRef``
- ``ActionFiredEvent``
- ``ShortcutDispatch``

### Persistence

- ``ShortcutBindingsStore``
- ``UserDefaultsStore``
- ``FileStore``
- ``RawState``
- ``Preferences``
- ``ShortcutMigration``

### Conflict Detection

- ``Conflict``
- ``Occurrence``
- ``SystemHotKey``
- ``SystemShortcutsProvider``
- ``CarbonSystemShortcuts``

### Rendering Data

- ``KeyBindings``

### Global Activation Seam

- ``GlobalActivator``
- ``GlobalBinding``
- ``BindingID``
- ``GlobalBindingStatus``
