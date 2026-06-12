# Conflict Detection

The kinds of binding clashes ShortcutKit detects, and how to surface them.

## Overview

The registry continuously analyzes every context's effective bindings and
publishes the result as ``ShortcutRegistry/conflicts``. Detection re-runs whenever
bindings change, so a settings UI can show live warnings as the user edits. Each
``Conflict`` carries the ``Occurrence``s it involves (context id, action id, and
shortcut) so you can render and jump to the offenders.

## The kinds of conflict

``Conflict`` is an enum:

- **`duplicate`** — two actions in the same active scope share a shortcut.
- **`unreachablePrefix`** — a multi-step shortcut can never fire because a shorter
  shortcut consumes its prefix.
- **`systemShared`** — a binding collides with an enabled macOS system shortcut
  (see *System shortcuts*, below).
- **`menuCollision`** — a binding collides with an app menu item's key equivalent.
- **`shadowedByGlobal`** — a local binding is shadowed by a global one, which the
  OS intercepts first.
- **`unsupportedInScope`** — a binding can't work in its context's scope (e.g. a
  multi-step chord or continuous gesture in a `.global` context, which Carbon
  can't represent).

## Severity

Each conflict has a ``Conflict/Severity`` — `.warning` or `.error` — and `Severity`
is `Comparable`, so you can find the worst at a glance:

```swift
let worst = registry.conflicts.map(\.severity).max()
```

Cross-scope clashes (a global shadowing a local) escalate to `.error` because the
user simply won't be able to reach the shadowed binding.

## System shortcuts

The `systemShared` check compares bindings against the user's enabled macOS
keyboard shortcuts, read via ``CarbonSystemShortcuts`` (the default
``SystemShortcutsProvider``). To suppress specific entries, or to supply a custom
source, pass your own provider to the registry. A ``SystemHotKey`` can be built
from a single-key `Shortcut` for easy comparison:

```swift
if let hotKey = SystemHotKey(Shortcut("cmd+space")) { /* … */ }
```

## Topics

### Related Types

- ``Conflict``
- ``Occurrence``
- ``SystemShortcutsProvider``
- ``CarbonSystemShortcuts``
- ``SystemHotKey``
