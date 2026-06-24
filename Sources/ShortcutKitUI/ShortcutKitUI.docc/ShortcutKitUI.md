# ``ShortcutKitUI``

Drop-in SwiftUI for shortcut customization: a settings screen, a legend, a
single-action editor, and a discoverability HUD.

## Overview

ShortcutKitUI renders the headless data a `ShortcutRegistry`
exposes. Hand any of these views a registry and they stay in sync as bindings
change. Adopters who want bespoke visuals can read the same data types from
ShortcutKit and skip this module.

- ``KeyBindingsView`` — the settings table: every context's actions with inline
  recorders, search, conflict badges, and a reset control. Choose the visual
  density with ``KeyBindingsStyle`` and the multi-context layout with
  ``ContextLayout``.
- ``ShortcutPreferencesView`` — a ready-made Settings tab wrapping
  `KeyBindingsView` plus the "show hints" toggle.
- ``ShortcutBindingEditor`` — one action's editor, to drop into an onboarding flow
  or a custom layout.
- ``KeyBindingsLegendView`` — a read-only cheat sheet, styled with ``LegendStyle``.
- The **`shortcutHintHUD(registry:policy:options:)`** view modifier — a transient
  "you could've used ⌘S" toast when an action fires via a non-shortcut path.
  Tune frequency with ``HintPolicy`` and placement/duration with ``HintHUDOptions``.

```swift
import ShortcutKitUI

// A complete settings pane:
ShortcutPreferencesView(registry: model.registry)

// Discoverability HUD on your root view:
ContentView().shortcutHintHUD(registry: model.registry)
```

## Topics

### Essentials

- <doc:UIGettingStarted>

### Settings UI

- ``KeyBindingsView``
- ``ShortcutPreferencesView``
- ``ShortcutBindingEditor``
- ``ContextLayout``
- ``KeyBindingsStyle``

### Legend

- ``KeyBindingsLegendView``
- ``LegendStyle``
- ``LegendOptions``
- ``LegendColumns``
- ``LegendEntryLayout``

### Discoverability HUD

- ``HintPolicy``
- ``HintHUDOptions``
- ``HintHUDPlacement``
- ``HintToastContext``
