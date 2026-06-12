# Getting Started

Declare a global context, then activate it system-wide.

## Declare a global context

A `.global` context's handler runs whether or not any view is on screen, so it's
supplied at construction (in Core):

```swift
import ShortcutKit

enum LauncherAction: String, ShortcutAction {
    case toggle
    var definition: ShortcutActionDefinition { .init("Toggle Launcher", "cmd+shift+space") }
}

let launcher = ShortcutContext<LauncherAction>(global: "launcher") { action, _ in
    switch action {
    case .toggle: AppWindow.toggle()
    }
}

let registry = ShortcutRegistry(contexts: [launcher /* + your local contexts */])
```

## Activate it

Create a ``CarbonGlobalActivator`` and `start` it with the registry, typically at
app launch. It registers every `.global` context's effective bindings with the
system and keeps them in sync as the user re-binds.

```swift
import ShortcutKitGlobal

@MainActor
final class AppModel: ObservableObject {
    let registry = ShortcutRegistry(contexts: [launcher])
    private let globalActivator = CarbonGlobalActivator()

    func startGlobalHotkeys() {
        do { try globalActivator.start(registry) }
        catch { /* GlobalActivatorError.alreadyStarted, etc. */ }
    }

    func stopGlobalHotkeys() { globalActivator.stop() }
}
```

`start(_:)` throws ``GlobalActivatorError`` (e.g. `.alreadyStarted`). Per-binding
registration outcomes — including a combo the system rejected — are reported
through the registry's global binding status, so a settings UI can show which
global shortcuts actually took.

## Mixing global and local

A registry can hold both. Local contexts still fire only while activated by a view
(`activeShortcutContext(_:dispatch:)`); global contexts fire system-wide for the
activator's lifetime. If a local and a global binding collide, Core flags a
`shadowedByGlobal` `Conflict` (escalated to `.error`, since the OS
intercepts the global one first).
