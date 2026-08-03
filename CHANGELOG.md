# Changelog

All notable changes to ShortcutKit are documented here.

Entries are prefixed `[Core]`, `[UI]`, or `[Global]` so adopters can scan what affects them. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

The `0.x` line is pre-release: the public API is stabilizing toward 1.0 and may change between minor versions.

## [Unreleased]

### Added
- **[UI]** `KeyBindingsView` gains a `KeyBindingsPresentation`: `.standalone(search:layout:)` (the default self-contained pane) and `.embedded` — container-agnostic `Section`s (no scroll view, card, or search) to drop into your own `Form`/`List` so shortcuts sit natively alongside other settings.
- **[UI]** `LegendOptions.shortcutStyle` — render shortcuts as ShortcutField `.compact` SF-symbol / abbreviation labels (the default) or `.text` verbose words.
- **[UI]** Legend cells are fixed-width, gutter-aligned columns (shortcut right-aligned, label left-aligned), single-line with tail truncation and the full value shown on hover. `LegendOptions.labelWidth` (`.size` / `.flexible` / `.fixed(_)`) and the public `LegendOptions.cellWidth` size the columns.
- **[Core/UI]** User-controllable hint frequency: `registry.hintFrequency` / `setHintFrequency(_:)` (persisted like `hintsEnabled`, defaulted via `ShortcutRegistry(defaultHintFrequency:)`), surfaced as a picker in `ShortcutPreferencesView` and read live by the HUD.
- **[UI]** `HintPreferencesView` — the "show hints" toggle and frequency picker as bare `Form` rows to drop inside your own `Section`, so the hint controls compose into your settings layout instead of only inside the full `ShortcutPreferencesView` pane.
- **[UI]** `LegendOptions.appearance` — a `LegendAppearance` of per-slot fonts (`labelFont` / `shortcutFont` / `headerFont`, each a `LegendFont`) and colors (`labelColor` / `shortcutColor` / `headerColor`), so a legend can adopt a host app's type stack instead of forcing the system font. Every slot defaults to the built-in look; `LegendFont` leaves `face` and `size` `nil` to inherit, so overriding a typeface keeps `LegendSize` scaling.

### Changed
- **[UI]** The legend's shortcut column now renders in `Menlo` — a slashed zero and a tailed `l` keep `0`/`O` and `l`/`I` apart — and the shortcut is the emphasized half of each row (the label renders quieter), reversing the previous weighting.
- **[UI]** The legend is now explicitly fixed-size and does not scale with Dynamic Type. Its columns are measured with the same `NSFont` they render, and a scaled render against an unscaled measurement mis-fires the truncation tooltips; use `LegendSize` (or `LegendFont.size`) to resize it.
- **[Core] Breaking:** `HintPolicy` moved from `ShortcutKitUI` to `ShortcutKit` (re-exported, so `import ShortcutKitUI` still sees it) — it's now a persisted preference value, not just a HUD parameter.
- **[UI] Breaking:** `shortcutHintHUD(registry:policy:options:)` dropped its `policy:` parameter; the developer default moves to `ShortcutRegistry(defaultHintFrequency:)` and the effective frequency is now a user preference.
- **[UI] Breaking:** `KeyBindingsStyle.native` renamed to `.regular` — the axis is visual density (`.regular` vs `.dense`), and everything is equally "native" SwiftUI.
- **[UI] Breaking:** `KeyBindingsView`'s `searchEnabled:` / `contextLayout:` init params moved onto `.standalone(search:layout:)`, so they can't be set on an `.embedded` view where they don't apply.
- **[UI]** `ShortcutPreferencesView` now composes the `.embedded` `KeyBindingsView` inside a grouped `Form` (fixes the nested-scroll / double-card when it was the drop-in tab) and keeps a "Reset All…" button; its `searchEnabled` / `contextLayout` parameters were removed (search is host-owned in embedded layouts — add `.searchable` if wanted).
- Bumped ShortcutField to 2.2.3 (SF-symbol shortcut labels).

## [0.5.1] - 2026-06-26

### Added
- **[UI]** Legend styling: split into panel and sheet styles with a compact grid option, added size variants, and tightened the layout.
- **[UI]** Discoverability hint toast fades and inverts on show/dismiss.

### Changed
- Example app showcases the full API (per-mode and selection shortcuts, always-on hint HUD) and seeds demo conflicts via overrides instead of shipping bad defaults.

## [0.5.0] - 2026-06-12

### Added
- **[Core]** `registry.dispatch` / `notify` by `ActionRef` (and `contextID:actionID:` overloads) to fire an action by id from a palette, URL scheme, or persisted ref.
- **[Core]** `registry.reload()` re-reads the store and applies out-of-band edits through the notify-and-rebuild path; `UserDefaultsStore.clear()`; `RawState.debugDescription`.
- DocC documentation for all three modules — landing pages with curated Topics, a Getting Started per module, and Core concept guides (contexts/activation, persistence/migrations, conflicts). Rendered docs are hosted on the Swift Package Index.

### Changed
- **[UI]** `HintHUDStyle` renamed to `HintHUDOptions`.
- **[Core]** `clear()` is now a `ShortcutBindingsStore` requirement; `reload()` returns a result.

## [0.4.0] - 2026-06-10

First tagged release. The three library products are implemented and tested.

### Added
- Package skeleton: three library products (`ShortcutKit`, `ShortcutKitUI`, `ShortcutKitGlobal`), test targets, DocC catalogs, repo tooling (SwiftLint, SwiftFormat, lefthook, Justfile, GitHub Actions CI), Swift Package Index config, and a SwiftUI example app (`Example/ShortcutKitExample.xcodeproj`).

- **[Core]** Action registry: `ShortcutAction` protocol + `ShortcutActionDefinition` (localizable `displayName`, optional `description`, default shortcut(s)). Re-exports ShortcutField (`Shortcut`, `Shortcut.Step`, `ContinuousShortcut`, …) via `@_exported import`.
- **[Core]** `ShortcutContext<Action>` (local + global) and `ShortcutRegistry` (`ObservableObject` hub for routing, persistence, conflicts, and the read API). Context activation via `.activeShortcutContext(_:dispatch:)` with the handler bound at activation; cross-context exclusivity via `mutuallyExclusiveContexts`.
- **[Core]** Dispatch + notify: typed `context.dispatch(_:)` / `notify(_:)`, emitting `ActionFiredEvent` tagged with `source` (`.shortcut` / `.programmatic`). `ShortcutDispatch` supports `.discrete` and `.continuous(magnitude:)`.
- **[Core]** Lookup API: `shortcuts(for:)`, `displayStrings(for:)`, `isCustomized(_:)`, `shortcutsChanges(for:)`. Override mutation via `setShortcuts` / `removeShortcut` / `reset` / `resetAll`.
- **[Core]** Persistence: pluggable `ShortcutBindingsStore` — `UserDefaultsStore` and a human-editable `FileStore` (TOML/JSON, `key:` namespacing with dotted paths, prioritized URL fallback chain, `createIfMissing`). Only user-changed values are written. `RawState` with ergonomic accessors; `Preferences`. Hint preference persisted through the store.
- **[Core]** Append-only, content-detecting `ShortcutMigration`s (rename / move via `ActionRef`) — persisted ids stay stable with no version counter.
- **[Core]** Conflict detection: within-context, cross-context, system-reserved (via `SystemShortcutsProvider` / `CarbonSystemShortcuts`), and menu collisions. `Conflict` (with `Comparable` severity), `Occurrence`, `SystemHotKey`.
- **[Core]** Menu helpers (`.shortcut(_:in:)` view modifier, `NSMenuItem` integration) and the headless render model `KeyBindings` (grouped, `Identifiable` entries) with fuzzy `.filter(query:)` and `.boundOnly()`.

- **[UI]** `KeyBindingsView` — auto-generated settings table with inline recorders, search/filter, reset, and conflict highlighting; `.stacked` and `.picker` context layouts; `KeyBindingsStyle`.
- **[UI]** `ShortcutBindingEditor<Action>` — single-action, registry-bound binding editor for onboarding and custom per-action UI.
- **[UI]** `KeyBindingsLegendView` — snapshot and registry-observing inits.
- **[UI]** `ShortcutHintHUD` via `.shortcutHintHUD(registry:policy:options:toast:)` — placement (3×3 anchor grid + `.cursor`), duration, and a custom-toast `@ViewBuilder`; gated by the user's hint preference (`HintPolicy`).
- **[UI]** `ShortcutPreferencesView` — canned preferences pane. Library UI strings ship localized against the package bundle.

- **[Global]** `ShortcutKitGlobal` — system-wide hotkeys via Carbon `RegisterEventHotKey`, with no external `KeyboardShortcuts` dependency.
- **[Global]** Registry integration: an action id can carry a global binding; `globalBindings()` returns `GlobalBinding`, and `GlobalBindingStatus` reports a closed `FailureReason`.

[Unreleased]: https://github.com/nielsmadan/ShortcutKit/compare/v0.5.1...HEAD
[0.5.1]: https://github.com/nielsmadan/ShortcutKit/compare/v0.5.0...v0.5.1
[0.5.0]: https://github.com/nielsmadan/ShortcutKit/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/nielsmadan/ShortcutKit/releases/tag/v0.4.0
