# ``ShortcutKitGlobal``

Register a registry's `.global` contexts as system-wide hotkeys.

## Overview

ShortcutKitGlobal activates the `.global`-scoped contexts in a
`ShortcutRegistry` as system-wide hotkeys, so they fire even when
your app isn't frontmost. It's built on Carbon's `RegisterEventHotKey` — no
third-party dependency, and **no Accessibility or Input Monitoring permission**
(unlike a global event tap), so it works in a sandboxed, App Store–distributed app.

You declare global contexts in Core (`ShortcutContext(global:dispatch:)`); this
module's ``CarbonGlobalActivator`` walks the registry for them and registers their
effective bindings with the system. It keeps the registration in sync as the user
re-binds, and reports per-binding outcomes through the registry's global status
seam.

```swift
import ShortcutKitGlobal

let activator = CarbonGlobalActivator()
try activator.start(model.registry)   // at launch
// …
activator.stop()                       // at teardown
```

> Note: Carbon system hotkeys are single-key only. A global context's multi-step
> chord or continuous gesture can't be registered; Core surfaces that as an
> `unsupportedInScope` `Conflict`.

## Topics

### Essentials

- <doc:GlobalGettingStarted>

### Activation

- ``CarbonGlobalActivator``
- ``GlobalActivatorError``
