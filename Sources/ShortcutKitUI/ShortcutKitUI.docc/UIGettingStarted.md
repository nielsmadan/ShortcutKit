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

When shortcuts sit **alongside other settings** in a pane (the common case), embed
``KeyBindingsView`` in your own `Form` with the `.embedded` presentation — it emits
one `Section` per context and inherits the native grouped styling and single scroll:

```swift
Form {
    Section("Display") { Toggle("Show hints", isOn: $showHints) }
    KeyBindingsView(registry: model.registry, presentation: .embedded)
}
.formStyle(.grouped)
```

Use the default `.standalone` presentation only when the view is the **entire** tab
(it owns its own scroll, search field, and Reset-All button). For a single context,
`KeyBindingsView(context:)`; pick density with ``KeyBindingsStyle``.

Pass `showsDescriptions: true` to render each action's `description` (for the actions
that declare one) as a subtitle under its name:

```swift
KeyBindingsView(registry: model.registry, presentation: .embedded, showsDescriptions: true)
```

When you compose the settings screen yourself, drop ``HintPreferencesView`` wherever
you want the hint controls — it emits the "show hints" toggle and the frequency
picker as bare `Form` rows, so you can put them in your own `Section` alongside other
preferences instead of taking the whole ``ShortcutPreferencesView`` pane:

```swift
Form {
    Section("Display") {
        Toggle("Menu bar icon", isOn: $showMenuBarIcon)
        HintPreferencesView(registry: model.registry)
    }
    KeyBindingsView(registry: model.registry, presentation: .embedded)
}
.formStyle(.grouped)
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
KeyBindingsLegendView(registry: model.registry, style: .panel)
```

Use `.embedded` when the surrounding view owns the legend's padding and
background. It renders only the legend content, without scrolling or container
chrome.

## The discoverability HUD

Attach `shortcutHintHUD(registry:options:)` near your root view. When an action
fires via a non-shortcut path (a button, a menu) it briefly shows the shortcut the
user could have pressed — gated by the user's `hintsEnabled` preference and paced
by their `hintFrequency`. Set the defaults for both on the registry; the user can
override them in ``ShortcutPreferencesView``:

```swift
let registry = ShortcutRegistry(
    contexts: [...],
    defaultHintFrequency: .oncePerSession
)
// ...
ContentView()
    .shortcutHintHUD(registry: registry)
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
