# ShortcutKitExample

A macOS SwiftUI app that demonstrates all three ShortcutKit products in one place.
The main window is a small **canvas app** (sidebar, inspector, canvas modes, a
new-project wizard) used to show the *realistic* mechanics; the **Settings**
window doubles as an in-app showcase of every UI component.

## Run it

```bash
just example      # from the repo root — builds and launches the app
```

(`just example` runs `xcodebuild` then launches the app; to only build, run the
`xcodebuild … build` step.)

## Where each feature is demonstrated

**Main window (realistic usage)**
- **Contexts & the activation stack** — app, sidebar, inspector, and per-mode
  canvas contexts activate/deactivate as views appear (`activeShortcutContext`).
- **Mutually-exclusive contexts** — the five canvas modes, the two selection
  contexts, and the wizard each form a mutex set.
- **Global hotkeys** — `⌃⌥⌘K` fires system-wide via `CarbonGlobalActivator`.
- **Discoverability HUD** — triggering an action by mouse shows its shortcut.
- **Sidebar legend** — `KeyBindingsLegendView` (`.sidebar`).
- **Menu bar** — the *Actions* menu shows each action's live shortcut via the
  `.shortcut(_:in:)` helper; re-binding in Settings updates it.

**Settings window (component showcase)**
- **Native / Dense** tabs — `KeyBindingsView` in both `KeyBindingsStyle`s, with
  live `ContextLayout` (stacked/picker) and search toggles.
- **Drop-in** tab — the canned `ShortcutPreferencesView`.
- **Legend** tab — `KeyBindingsLegendView` with a live `LegendStyle` picker
  (sidebar / modal / compact strip).
- **HUD** tab — a playground for `HintHUDOptions` (placement incl. `.cursor`,
  duration), `HintPolicy`, and a custom toast.
- **Quick Setup** tab — single-action `ShortcutBindingEditor` rows.
- **Diagnostics** tab — `reload()`, `clear()`, `RawState.debugDescription`, a
  `FileStore(.toml)` export, and the live conflict list.
- **Conflict badges** — a deliberately-clashing "Conflict Demo" context surfaces
  `duplicate` and `shadowedByGlobal` conflicts in the binding tables.

> Reset persisted customization with `just reset-example`.
