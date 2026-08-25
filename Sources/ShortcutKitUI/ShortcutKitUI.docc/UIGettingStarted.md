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
chrome. Use the `isIncluded` closure to omit entries from a legend without
disabling or removing their shortcuts.

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

Position, timing, animation, and the hosting layer come from ``HintHUDOptions``.
``HintHUDPlacement`` provides nine fixed anchors and `.cursor`; the default
``HintHUDPresentation/view`` host stays inside the modified view:

```swift
.shortcutHintHUD(
    registry: model.registry,
    options: HintHUDOptions(
        placement: .cursor,
        duration: .seconds(3),
        transition: .fade
    )
)
```

Use ``HintHUDPresentation/window`` to cover the active app window, including an
attached sheet, or ``HintHUDPresentation/screen`` to place the hint within that
screen's visible frame. A shared ``ShortcutHintPresenter`` coordinates one hint
across every window in an app:

```swift
let hintPresenter = ShortcutHintPresenter(registry: registry)
let hintOptions = HintHUDOptions(placement: .top, presentation: .screen)

ContentView()
    .shortcutHintHUD(presenter: hintPresenter, options: hintOptions)
```

Keep the presenter alive at app-model scope and attach the same instance to each
window root. It selects the key or frontmost eligible window, applies hint
frequency once across the app, and dismisses any previous hint before showing a
replacement. Window and screen presentation use a click-through,
non-activating panel that follows the selected window's Space and disappears
when the app deactivates. With `.screen` plus `.cursor`, the pointer's screen is
used; other placements use the selected window's screen.

Apply ``ShortcutHintStyle`` after the HUD modifier to customize only the built-in
toast. Omitted values keep their defaults:

```swift
ContentView()
    .shortcutHintHUD(registry: model.registry)
    .shortcutHintStyle(.toast(
        font: .system(size: 13, weight: .medium),
        textColor: .white,
        backgroundColor: .indigo
    ))
```

The built-in ``ShortcutHintToastStyle`` inherits the surrounding font at its
automatic size and adapts its foreground, background, and subtle border to the
current color scheme. The action name and shortcut are emphasized. It also
provides explicit semantic sizes and rounded, capsule, rectangular, or
chrome-free containers. Define a custom ``ShortcutHintStyle`` when the
appearance needs a different composition.

For a fully custom toast, use the trailing-closure overload; it hands you a
``HintToastContext`` with the action name, shortcut, and prebuilt text:

```swift
.shortcutHintHUD(registry: model.registry) { hint in
    MyBrandedToast(title: hint.actionName, shortcut: hint.shortcut)
}
```

Window and screen hosts carry the standard visual environment into their
separate panel: color scheme, locale, layout direction, font, control size,
Dynamic Type size, Reduce Motion, and ``ShortcutHintStyle``. A custom toast that
depends on an app-specific environment object should capture that model in its
closure instead of reading it from the panel environment.
