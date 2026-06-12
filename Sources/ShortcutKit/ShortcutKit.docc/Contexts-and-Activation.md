# Contexts and Activation

How shortcut routing follows your UI — and how local and global contexts differ.

## Overview

A ``ShortcutContext`` groups an action set and decides where its handler lives. A
registry can hold many contexts; which one handles a given key press depends on
*activation*.

## Local contexts

A local context is created with just an id; its handler is supplied at activation
time by a view:

```swift
let editor = ShortcutContext<EditorAction>("editor")
```

```swift
SomeView()
    .activeShortcutContext(editor) { action, dispatch in
        // handle action
    }
```

A local context fires **only while a view that activated it is on screen.** This
ties shortcut availability to what the user is looking at — an inspector's
shortcuts work only while the inspector is visible, and stop when it closes.

### The activation stack (innermost wins)

When several views are active at once, their contexts stack. A key press is
offered to the **most-recently-activated** context first; if that context has no
binding for the press, it falls through to the next one down. This lets a focused
panel override an app-wide shortcut without either side knowing about the other.

### Mutually exclusive contexts

Some contexts represent modes that can never be active together (e.g. a canvas's
*select* vs *draw* mode). Declare them so the registry treats their bindings as
non-conflicting even when they reuse the same key:

```swift
ShortcutRegistry(
    contexts: [select, draw, shared],
    mutuallyExclusiveContexts: [["canvas.select", "canvas.draw"]]
)
```

## Global contexts

A `.global` context is registered system-wide (the OS delivers the shortcut even
when your app isn't frontmost). Because the OS can fire it at any time, its
handler is required **at construction**, not at view activation:

```swift
let launcher = ShortcutContext<LauncherAction>(global: "launcher") { action, _ in
    // handle action — runs regardless of view state
}
```

Global contexts are activated for the registry's lifetime, not by
`activeShortcutContext(_:dispatch:)`. They need **ShortcutKitGlobal**'s
`CarbonGlobalActivator` to actually register with the system. See that module's
documentation for the registration and permission flow.

> Note: Carbon's system hotkey API only represents single-key shortcuts, so a
> global context's effective bindings can't be multi-step chords or continuous
> gestures. ``Conflict`` surfaces an `unsupportedInScope` entry if one slips in.

## Dispatch vs. notify

Both run on a context (or, by id, on the registry):

- ``ShortcutContext/dispatch(_:)`` runs the bound handler **and** emits an
  `actionFired` event (so observers and the discoverability HUD see it). Use it
  when the user triggered the action another way — a toolbar button, a menu item.
- ``ShortcutContext/notify(_:)`` emits the event **without** running the handler —
  for when the side effect already happened by another path and you only want to
  record that the action fired.

## Topics

### Related Types

- ``ShortcutContext``
- ``ContextScope``
- ``ShortcutRegistry``
- ``ShortcutDispatch``
