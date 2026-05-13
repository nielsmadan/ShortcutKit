# ShortcutKit — Planning Doc

A higher-level shortcut management library built on top of `ShortcutField`. This doc captures the vision, feasibility analysis, prior art, design concerns, and a suggested order of operations.

## Vision

A library that lets a dev:

- **Register shortcut contexts**, each with a set of actions. Actions have stable IDs, display names, default shortcuts, and category metadata.
- **Auto-generate settings pages** so users can rebind shortcuts without the dev writing UI.
- **Detect conflicts** — within a context, across simultaneously-active contexts (given a coactivation declaration), and ideally against known system shortcuts.
- **Activate contexts and bind callbacks** declaratively:
  ```swift
  activateContext("editor", actionMapping: [
      "save":  { save() },
      "undo":  { undo() },
  ])
  ```
- **Auto-generate a shortcut legend / cheatsheet** for any active set of contexts. Headless (returns a `[Category: [Action]]` data structure) or rendered (ships a SwiftUI view).
- **Discoverability HUD** — when a user invokes an action via a button or menu, briefly surface "this also has a shortcut: ⌘S".
- **Global (system-wide) shortcuts** integrated, so the library is a complete keyboard input layer (covers what `KeyboardShortcuts` does today).

## Feasibility (Swift)

Yes, fully feasible. Nothing about the feature list is blocked by the language. Idiomatic shape:

```swift
// Action declaration (per context, in your app)
enum EditorAction: String, ShortcutAction {
    case save, undo, redo, find
    var displayName: String { … }
    var defaultShortcut: Shortcut? { … }
}

// Per-instance binding
let editor = ShortcutContext<EditorAction>("editor") { action in
    switch action {
    case .save: viewModel.save()
    case .undo: viewModel.undo()
    case .redo: viewModel.redo()
    case .find: viewModel.openFind()
    }
}

// Activate when this view is on screen
SomeView()
    .activeShortcutContext(editor)
```

The harder bits are all solvable Swift problems:
- **Persistence migration** — action IDs need to stay stable across app versions; renaming a case requires a migration path.
- **Concurrency** — `@MainActor` for dispatch; events from `.onShortcut` already go through main.
- **Responder chain interaction** — bypass it (simpler, what `.onShortcut` does today) or plug into it (correct for accessibility / standard menu items).

Type safety: generics + `String`-backed `RawRepresentable` enums get most of the way. Loose alternatives (string keys) work too but lose compile-time checks.

## Prior art

Nothing on macOS reaches the scope described. The closest existing systems, ranked by similarity:

| System | Notes |
|---|---|
| **VS Code keybindings** | Gold standard. Commands ≈ actions, when-clauses ≈ contexts, conflict detection, auto-generated settings UI. Open source but JS/TS-only. |
| **KDE `KAction` / `KGlobalAccel`** | Mature (~20 years). Actions, defaults, `KShortcutsDialog`, conflict detection. Linux only. |
| **GNOME `GtkShortcutsWindow`** | Auto-generated cheatsheet UI but not the full action registry / settings flow. |
| **Flutter `Shortcuts` / `Actions` / `Intent`** | Built into Flutter. Maps key input → Intent → Action. Smaller than this vision, conceptually identical. |
| **Game engines' input maps** | Unity Input System, Godot Input Map, Unreal Enhanced Input. Different domain, same pattern: actions → bindings → rebinding UI. |
| **`KeyboardShortcuts` (sindresorhus)** | macOS, global hotkeys with a settings field. No context registry, no conflict graph, no legend. The global-shortcut piece you'd build on top of (or wrap). |

For Apple platforms specifically there's no equivalent. **You'd be filling a real gap.**

## Concerns / design decisions

### 1. Scope / packaging

Recommended structure: **one Swift Package, multiple library products**, each in its own target.

```swift
let package = Package(
    name: "ShortcutKit",
    products: [
        .library(name: "ShortcutKit",       targets: ["ShortcutKit"]),
        .library(name: "ShortcutKitUI",     targets: ["ShortcutKitUI"]),
        .library(name: "ShortcutKitGlobal", targets: ["ShortcutKitGlobal"]),
    ],
    dependencies: [
        .package(url: "…/ShortcutField", from: "2.0.0"),
    ],
    targets: [
        .target(name: "ShortcutKit",
                dependencies: [.product(name: "ShortcutField", package: "ShortcutField")]),
        .target(name: "ShortcutKitUI",
                dependencies: ["ShortcutKit"]),
        .target(name: "ShortcutKitGlobal",
                dependencies: ["ShortcutKit"]),
    ]
)
```

Why this beats separate packages:

- **No version matrix.** Single tag per release. `ShortcutKit 1.4.0` always matches `ShortcutKitUI 1.4.0` because they're the same package.
- **Lazy compilation.** A dev who only imports `ShortcutKit` doesn't pay binary cost for the UI module — SwiftPM compiles only what's imported.
- **Single CHANGELOG, single CI, single docs site.**
- **Devs add one dependency**, then per-target choose which products to use:
  ```swift
  .target(
      name: "MyApp",
      dependencies: [
          .product(name: "ShortcutKit",   package: "ShortcutKit"),
          .product(name: "ShortcutKitUI", package: "ShortcutKit"),
      ]
  )
  ```

Tradeoffs (minor):
- A bugfix in UI bumps the whole package version. (Not really a problem; SemVer handles this fine.)
- Bigger source tree to navigate. (Documentation can mitigate.)

This is what **`swift-collections`**, **`swift-async-algorithms`**, **`swift-syntax`**, and most multi-module Apple-ecosystem packages do. Versioning model is well-trodden.

If a piece grows to need its own release cadence (e.g. `ShortcutKitGlobal` evolves much faster than the core), spinning it out into a separate package later is a one-time migration. Start unified.

### 2. Action identity & persistence

- Actions need stable IDs across app versions. User customizations persist as `Codable`.
- Migration when actions are renamed or removed in app updates. Library should provide hooks: "this old ID maps to that new ID."
- Two layers of state: dev-declared **defaults** + user-declared **overrides**. Persist only overrides; defaults reload from code each launch.

### 3. Context activation model

Three viable shapes:

- **Stack-based**: contexts pushed/popped with view lifecycle. Simple, but misses cases like "always-active app shortcuts + view-specific overlay."
- **Tag-based**: multiple contexts simultaneously active. Flexible, intuitive, recommended starting point.
- **Predicate-based ("when clauses")**: VS Code's model — boolean expressions over app state. Most flexible, biggest implementation cost. Defer to v2.

Default to **tag-based** for v1.

### 4. Conflict detection — three rings

| Ring | Detectable? | Cost |
|---|---|---|
| Within a single context | Trivial | Free |
| Across simultaneously-active contexts | Yes, given a coactivation declaration | Medium |
| With system / OS shortcuts | Partially — Apple doesn't expose a list. Hardcode known reservations (⌘Q, ⌘W, ⌘H, ⌘Tab, ⌘Space, etc.) | Low effort, incomplete |
| With other apps' global shortcuts | Impossible to detect | N/A |

Document scope clearly. Don't promise more than you deliver.

### 5. Discoverability HUD

The cleanest API: route **all** action invocations through the dispatcher:

```swift
context.dispatch(.save, source: .button)
```

When `source != .shortcut && hasShortcut(action)`, show a HUD. This forces a small refactor in adopting apps (button click handlers go through the dispatcher) but produces a great UX. Without it, you'd need fragile mechanisms to detect "the user did the menu equivalent."

Throttling and "stop showing this hint after N times" are essential — a HUD that nags is worse than no HUD.

### 6. Settings UI auto-generation

High-value-per-LOC feature. SwiftUI view that takes the registry and produces:
- List grouped by context / category
- Inline `ShortcutRecorderView` per row for editing
- Search / filter
- Reset all / reset individual buttons
- Conflict highlighting

**Make it headless-first**: expose `[(category, [(action, currentShortcut, conflict?)])]` as data. Ship a default rendered view on top. Lets bespoke-design apps render their own without forking the library.

### 7. Responder chain integration

Decision:
- **Bypass** (use `NSEvent` local monitors like `.onShortcut` does today): simpler, works for any visual style. Cost: standard menu-bar shortcuts in `MainMenu.xib` don't flow through your system; apps double-declare.
- **Plug in**: actions become `NSResponder` methods or `NSApp.sendAction`. Menu shortcuts visible. Accessibility tools see them. Cost: more constrained design.

**Recommend**: bypass-by-default + opt-in `bridgeToResponderChain()` for apps that want their action map to also drive the menu bar.

### 8. Global shortcuts integration

Two paths:
- **Wrap `KeyboardShortcuts`** as a soft dependency. Cheap, leverages a mature library.
- **Reimplement** to control the entire stack and avoid pulling in another package's preference UI.

Probably **wrap first** to ship faster; reimplement if `KeyboardShortcuts`' design pulls against yours.

### 9. Localization

- Action display names need localization (`String.LocalizationValue`).
- Shortcut glyphs (⌘ ⇧ ⌃ ⌥) are universal; labels around them aren't.

### 10. Discoverability scope on macOS

`?` to show all shortcuts is a web/game pattern. Apple's HIG has no strong precedent for it. Recommendation: ship just the headless data for the legend; let consuming apps render the cheatsheet however fits their brand. Avoids owning a visual that won't match every adopter.

### 11. Marketing positioning

Lead with: **"VS Code-style keybindings for native macOS apps."** Clear, recognizable, accurate. The HUD and legend are bonus features that close the loop on user discovery.

## Suggested order of operations

Each phase ships independently and is meaningful alone. Resist building all four in one go — the API for later phases improves based on what you learn from the earlier ones.

### Phase 1 — `ShortcutKit` core

- `ShortcutAction` protocol
- `ShortcutContext<Action>` registry
- Tag-based context activation
- Action dispatch (with `source:` tagging)
- Persistence (defaults + overrides via `Codable`)
- Within-context conflict detection
- Cross-context conflict detection (with explicit coactivation declarations)
- System-shortcut warnings (hardcoded list)

Most of the value is here. A dev with this can already build a settings page by hand using `ShortcutField`.

### Phase 2 — `ShortcutKitUI`

- Headless data model: `KeyBindingsTable` representing the registry
- `KeyBindingsView` SwiftUI view that renders the table with inline `ShortcutRecorderView`s
- Search, filter, reset buttons
- Conflict highlighting
- Headless legend: `KeyBindingsLegend` data structure
- Optional rendered `KeyBindingsLegendView`

### Phase 3 — `ShortcutKitGlobal`

- Wrapper over `KeyboardShortcuts` (or reimplementation)
- Integration with the action registry: same action ID can have a global binding
- Permission handling (accessibility prompt where needed)

### Phase 4 — discoverability HUD

- `ShortcutHintHUD` — small overlay that surfaces "this has a shortcut" when an action fires from a non-shortcut source
- Throttling, dismiss rules, "shown N times → stop" logic
- Headless first (notify a closure with the action that just fired); rendered HUD as a default

## Open questions

- Naming. `ShortcutKit` works but might collide with apps' internal naming. Alternatives: `Hotkey`, `KeybindingKit`, `Bindings`. Decide before public release; renaming after is painful.
- License. Mirror `ShortcutField`'s.
- macOS minimum. SwiftUI generations matter — `Shortcuts` and `Actions`-style APIs benefit from newer platform versions.
- Whether to integrate `ShortcutField`'s headless extraction (`ShortcutRecordingSession`) before `ShortcutKit` ships, since the settings UI consumes the recorder. Probably yes — gives Phase 2 a clean dependency.

## Risks

- **Scope creep.** Easy to keep adding "one more useful feature." Discipline: each phase should be releasable on its own.
- **Apple's input layer evolving.** macOS 26's keyboard / focus changes (Liquid Glass, refreshed `MainMenu`) might shift the responder-chain decision. Watch for relevant additions before locking down phase 3.
- **Adoption depends on `ShortcutField` being trusted.** ShortcutKit consumes it, so the recorder needs to be solid first.
- **Documentation burden grows fast** when you have four products. Plan a docs strategy (DocC archives per target) before phase 2.

## Summary

Feasible in Swift. Real gap on macOS — VS Code-quality keybindings haven't been ported to the Apple ecosystem. Single Swift Package with multiple library products is the right packaging — avoids version-matrix pain, follows Apple-ecosystem convention. Build in four phases starting with the core registry; each phase is shippable and meaningful alone.
