# Getting Started

Add a settings screen, a legend, a single-action editor, and a discoverability
HUD — each just needs your registry.

## A settings screen

The fastest path is ``ShortcutPreferencesView``, a ready-made Settings tab:

```swift
import ShortcutKitUI

struct SettingsScene: Scene {
    @ObservedObject var model: AppModel
    var body: some Scene {
        Settings { ShortcutPreferencesView(registry: model.registry) }
    }
}
```

For more control, embed ``KeyBindingsView`` directly. Pick the density with
``KeyBindingsStyle`` and, for many-context apps, a ``ContextLayout``:

```swift
KeyBindingsView(registry: model.registry, style: .native, contextLayout: .picker)
```

## A single-action editor

To ask for just one shortcut — say, in an onboarding step — use
``ShortcutBindingEditor``:

```swift
ShortcutBindingEditor(.save, in: model.editor, showsDescription: true)
```

> Important: The context you pass must already be attached to a registry (i.e.
> constructed and handed to `ShortcutRegistry(contexts:)`). An unattached context
> traps in debug builds.

## A legend (cheat sheet)

``KeyBindingsLegendView`` renders a read-only list of effective bindings, styled
with ``LegendStyle``:

```swift
KeyBindingsLegendView(registry: model.registry, style: .sidebar)
```

## The discoverability HUD

Attach `shortcutHintHUD(registry:policy:options:)` near your root view. When an
action fires via a non-shortcut path (a button, a menu) it briefly shows the
shortcut the user could have pressed — gated by the user's hint preference and by
a ``HintPolicy``:

```swift
ContentView()
    .shortcutHintHUD(registry: model.registry, policy: .oncePerSession)
```

Position and timing come from ``HintHUDOptions`` — including ``HintHUDPlacement``'s
nine fixed anchors and `.cursor`:

```swift
.shortcutHintHUD(
    registry: model.registry,
    options: HintHUDOptions(placement: .cursor, duration: .seconds(3))
)
```

For a fully custom toast, use the trailing-closure overload; it hands you a
``HintToastContext`` with the action name, shortcut, and prebuilt text:

```swift
.shortcutHintHUD(registry: model.registry) { hint in
    MyBrandedToast(title: hint.actionName, shortcut: hint.shortcut)
}
```
