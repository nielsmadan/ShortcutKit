# ShortcutKit — Package Design Spec

| | |
|---|---|
| **Date** | 2026-05-13 |
| **Status** | Approved (brainstorm complete, awaiting plan) |
| **Type** | Meta-spec — package-level decisions inherited by every phase |
| **Predecessor** | [`ShortcutKitDevelopment.md`](../../../ShortcutKitDevelopment.md) (planning doc, retained as input reference) |
| **Successor specs** | One per phase: Phase 1 (Core), Phase 2 (UI + HUD), Phase 3 (Global), Phase 4 (docs site) |

## 1. Scope and purpose

This spec locks in the package-wide decisions for **ShortcutKit**, a higher-level shortcut management library built on top of `ShortcutField`. It is a **meta-spec**: every phase's individual spec inherits the decisions made here and is responsible only for the narrower, phase-specific design.

What this spec decides:
- Package name, target structure, product layout, dependencies
- Public API conventions: action identity, dispatch + lookup, naming patterns
- Persistence model and migration strategy
- Repo tooling (lint/format/CI/hooks)
- Versioning, distribution, documentation strategy
- The 12 cross-phase invariants every phase must hold

What this spec defers:
- The exact API of `ShortcutContext<Action>` — Phase 1.
- The exact data model of `KeyBindingsTable` and the HUD overlay — Phase 2.
- The Carbon `RegisterEventHotKey` wrapping details — Phase 3.
- The docs site generator choice and content map — Phase 4.

### 1.1 Implementation deliverable for this spec

The plan derived from this spec produces the **package skeleton** — no feature implementation. Concretely:

- `Package.swift` per § 3, with empty target directories.
- Empty source files per target establishing the module (e.g. a single `Empty.swift` or a `ShortcutKit.swift` umbrella file containing module-level doc comments — Phase 1 fills in).
- One empty DocC catalog per target with a placeholder landing article.
- All repo tooling (`.swiftlint.yml`, `.swiftformat`, `lefthook.yml`, `Justfile`, `.github/workflows/ci.yml`, `.gitignore`) copied/adapted from ShortcutField.
- `Example/ShortcutKitExample.xcodeproj` skeleton with empty tabs.
- `README.md` skeleton with placeholder install snippet and feature table.
- `CHANGELOG.md` with the initial `## [Unreleased]` section.
- `lefthook install` run; `swift build` succeeds; `swift test` succeeds (no tests yet); `swiftlint .` passes.

The plan does NOT include any registry, context, dispatch, persistence, UI, or global-hotkey logic. Those belong to per-phase specs.

## 2. Vision recap

A library that lets a macOS dev:
- Register **shortcut contexts**, each with a set of actions. Actions have stable IDs, display names, default shortcuts, and category metadata.
- Auto-generate **settings pages** so users can rebind shortcuts without the dev writing UI.
- **Detect conflicts** within and across active contexts, plus warnings against known system shortcuts.
- **Activate contexts and bind callbacks declaratively.**
- Auto-generate a **shortcut legend / cheatsheet** for any active set of contexts.
- Surface a **discoverability HUD** ("this also has a shortcut: ⌘S") when an action is invoked via a non-shortcut source.
- Integrate **global (system-wide) shortcuts** so the library is a complete keyboard input layer.

See `ShortcutKitDevelopment.md` for the full vision, feasibility analysis, and prior-art comparison.

## 3. Package layout

```swift
// Package.swift
// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "ShortcutKit",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "ShortcutKit",       targets: ["ShortcutKit"]),
        .library(name: "ShortcutKitUI",     targets: ["ShortcutKitUI"]),
        .library(name: "ShortcutKitGlobal", targets: ["ShortcutKitGlobal"]),
    ],
    dependencies: [
        .package(url: "https://github.com/nielsmadan/ShortcutField", from: "2.0.0"),
    ],
    targets: [
        .target(
            name: "ShortcutKit",
            dependencies: [.product(name: "ShortcutField", package: "ShortcutField")]
        ),
        .target(
            name: "ShortcutKitUI",
            dependencies: [
                "ShortcutKit",
                .product(name: "ShortcutField", package: "ShortcutField"),
            ]
        ),
        .target(
            name: "ShortcutKitGlobal",
            dependencies: ["ShortcutKit"]
        ),
        .testTarget(name: "ShortcutKitTests",       dependencies: ["ShortcutKit"]),
        .testTarget(name: "ShortcutKitUITests",     dependencies: ["ShortcutKitUI"]),
        .testTarget(name: "ShortcutKitGlobalTests", dependencies: ["ShortcutKitGlobal"]),
    ]
)
```

**Key decisions:**

- **3 products, 1 package.** Single tag per release; lazy compilation per import; one CHANGELOG, one CI, one docs site. Matches `swift-collections` / `swift-syntax` convention.
- **Umbrella target is `ShortcutKit` (no `Core`/`Base` suffix).** Core is useful standalone — registry + dispatch + persistence + conflict detection ships in one import. Sub-targets carry descriptive suffixes (`UI`, `Global`). This is the dominant Apple-ecosystem pattern.
- **ShortcutField is a hard dep of Core and UI.** It is the canonical source of the `Shortcut`, `Shortcut.Step`, `Shortcut.Kind` types. ShortcutKit does **not** redefine these types.
- **ShortcutKitGlobal does not depend on ShortcutField directly.** Global only needs the registry + dispatch from Core; it does not touch recorders. (It transitively gets `Shortcut` through Core.)
- **No `KeyboardShortcuts` dep.** ShortcutKitGlobal is reimplemented on Carbon `RegisterEventHotKey` + `NSEvent` monitors.
- **HUD lives in `ShortcutKitUI`.** Phase 2 ships the HUD as part of UI; Core exposes only the headless dispatch hook.

### 3.1 Target responsibilities

| Target | Concerns |
|---|---|
| **`ShortcutKit` (Core)** | `ShortcutAction` protocol; `ShortcutContext<Action>` registry; activation; dispatch + notify; persistence (load/save, append-only migrations); within-context and cross-context conflict detection; system-shortcut hardcoded warning list; headless `KeyBindingsTable` and `KeyBindingsLegend` data types; lookup API (`shortcut(for:)`, etc.); `NSMenuItem` helper; SwiftUI `KeyEquivalent` helper. |
| **`ShortcutKitUI`** | `KeyBindingsView` SwiftUI rendering of the table; `KeyBindingsLegendView` rendering of the legend; `ShortcutHintHUD` discoverability overlay; search/filter/reset affordances; conflict highlighting visuals. |
| **`ShortcutKitGlobal`** | System-wide hotkey registration via Carbon `RegisterEventHotKey`; permission/accessibility prompt flow; integration with the action registry (same action ID can have a global binding); global override persistence. |

## 4. Phase structure

Four phases, sequential. Each phase has its own narrower spec and ships independently.

| Phase | Target shipped | Scope |
|---|---|---|
| **Phase 1** | `ShortcutKit` (Core) | Registry, dispatch, persistence, conflicts, system warnings, lookup API, menu helpers |
| **Phase 2** | `ShortcutKitUI` | Settings view, legend view, HUD overlay, search/filter/reset, conflict highlighting |
| **Phase 3** | `ShortcutKitGlobal` | Carbon-based global hotkeys, permission UX, registry integration |
| **Phase 4** | `shortcutkit.dev` | Public documentation site, hosted DocC archives, guides, landing page |

**Rhythm:** each phase begins with its own brainstorm (one of the per-phase specs), then writing-plans, then execute-plans. Phase 2 design benefits from Phase 1 in adopter hands; Phase 3 conflict surface depends on Phases 1 and 2.

## 5. Public API conventions

### 5.1 Action declaration

Adopters declare actions as a `String`-backed `RawRepresentable` enum conforming to `ShortcutAction`:

```swift
enum EditorAction: String, ShortcutAction {
    case save, undo, redo, find

    var displayName: String { … }
    var defaultShortcut: Shortcut? { … }
    var category: ShortcutCategory? { nil }  // protocol-provided default
}
```

- `ShortcutAction` extends `RawRepresentable where RawValue == String` and `CaseIterable`. Compile-time-enumerable; no reflection.
- The `String` raw value is the **persistence ID** — stable forever (see § 6).
- `displayName` is required; `defaultShortcut` and `category` have protocol-provided defaults.

### 5.2 Context declaration

```swift
let editor = ShortcutContext<EditorAction>("editor") { action in
    switch action {
    case .save: viewModel.save()
    case .undo: viewModel.undo()
    case .redo: viewModel.redo()
    case .find: viewModel.openFind()
    }
}
```

- `ShortcutContext<Action>` is generic over the `ShortcutAction` type; dispatcher closure is exhaustive (compiler-enforced switch).
- Context ID (`"editor"`) is a `String`. Used as the persistence key prefix and as the identifier in cross-context coactivation declarations.

### 5.3 Action invocation: two entry points

The library has **two** action entry points, both on `ShortcutContext`:

```swift
// Execute + notify — the all-in path. Library invokes the bound closure AND
// fires the "action happened" notification (which may trigger the HUD).
editor.dispatch(.save, source: .button)

// Notify only — adopter ran their own code, but still wants the HUD to
// surface "this has a shortcut: ⌘S". Library does NOT invoke the closure.
editor.notify(.save, source: .button)
```

- The `source` parameter is shared: `.shortcut`, `.button`, `.menu`, `.programmatic`.
- HUD eligibility rule: `source != .shortcut && hasBinding(action)`, regardless of which entry point fired.
- `.onShortcut`-driven matches always go through `dispatch` internally with `source: .shortcut` — that path is library-owned.

This gives adopters three migration stages:
1. Ship without using the library's invocation API — no HUD, registry only.
2. Add `notify(...)` calls next to existing handlers for free HUD.
3. Consolidate to `dispatch(...)` and let the library run the closures.

### 5.4 Lookup API (read path)

Every context exposes lookup for the currently-effective binding:

```swift
extension ShortcutContext {
    /// Currently-effective shortcut for an action (override-or-default).
    public func shortcut(for action: Action) -> Shortcut?

    /// Convenience: human-readable, e.g. "⌘S" or "⌘K ⌘C".
    public func displayString(for action: Action) -> String?

    /// Whether the current binding differs from the action's default.
    public func isCustomized(_ action: Action) -> Bool

    /// Stream of binding changes (so views update when the user rebinds in
    /// settings). Phase 1 picks the exact reactive primitive — `@Observable`
    /// is not available on macOS 13, so likely a `Combine.Publisher` or a
    /// notification-style mechanism.
    public func bindingChanges(for action: Action) -> some Publisher<Shortcut?, Never>
}
```

Use cases:
- Display the binding in a menu label: `"Save"  →  "Save (\(editor.displayString(for: .save) ?? ""))"`
- Set on an `NSMenuItem`: see § 5.7.
- Show the binding in a custom toolbar button tooltip.

### 5.5 View modifiers

Verb-led, prefix `shortcut...`:

```swift
SomeView()
    .activeShortcutContext(editor)                  // bind context to view lifecycle
    .shortcutContextCoactivation([editor, finder])  // declare contexts that coactivate
```

### 5.6 Naming patterns

- Public types native to ShortcutKit use `Shortcut<Concept>`: `ShortcutAction`, `ShortcutContext`, `ShortcutCategory`, `ShortcutRegistry`.
- Public types in the table/legend domain reuse VS Code vocabulary: `KeyBinding<Concept>` — `KeyBindingsTable`, `KeyBindingsView`, `KeyBindingsLegend`, `KeyBindingsLegendView`.
- View modifiers: verb-led, `shortcut...` or `activeShortcutContext...` prefix.
- No `Manager` / `Service` / `Helper` suffixes in public API. Internal types may use them; public types must not.
- ShortcutField's `Shortcut` is **re-exported** via `@_exported import ShortcutField` in `ShortcutKit`. Adopters get the type without a second import line.

### 5.7 Menu integration (sketch — Phase 1 finalizes)

**SwiftUI:**
- Adopters can read `editor.displayString(for: .save)` for labels.
- A `Shortcut.swiftUIKeyEquivalent` / `swiftUIModifiers` pair (in Core) enables `.keyboardShortcut(...)` if they want SwiftUI to also dispatch. Note: SwiftUI's `.keyboardShortcut` dispatches the button action itself — adopters should NOT also bind `.onShortcut` for the same key, or they'll double-fire.

**AppKit `NSMenuItem`:**
- A helper extension (in Core) maps a `Shortcut?` to `keyEquivalent` + `keyEquivalentModifierMask`. Multi-step shortcuts cannot be expressed in NSMenuItem; they degrade to no shortcut shown.
- Setting `NSMenuItem.keyEquivalent` makes AppKit dispatch the menu item's action — again, adopters using this should not double-bind `.onShortcut` for the same action. The bypass-vs-bridge decision is Phase 1's detailed spec (your `ShortcutKitDevelopment.md` Concern #7).

### 5.8 Headless-first principle

Every visible affordance ships in two layers:
1. **Headless `Sendable` data type** — lives in Core.
2. **Default rendered SwiftUI view** — lives in UI, layered on top of the data.

Concretely:
- Phase 2 UI table: `KeyBindingsTable` (Core) + `KeyBindingsView` (UI).
- Phase 2 Legend: `KeyBindingsLegend` (Core) + `KeyBindingsLegendView` (UI).
- Phase 2 HUD: notification/closure hook (Core, fired by `dispatch` / `notify`) + `ShortcutHintHUD` rendered overlay (UI).

This lets bespoke-design adopters fully consume ShortcutKit without forking the library's visuals.

## 6. Persistence and migration

### 6.1 Persistence shape

Stored data is a flat dictionary keyed by context ID then action ID, plus a single applied-count integer:

```jsonc
{
  "migrationsApplied": 3,           // adopter-list applied count
  "libraryMigrationsApplied": 0,    // library-internal applied count
  "overrides": {
    "editor": {
      "save": { /* Shortcut Codable */ },
      "undo": { /* Shortcut Codable */ }
    },
    "window": {
      "close": { /* Shortcut Codable */ }
    }
  }
}
```

- Only **overrides** are persisted. Defaults are reloaded from code each launch.
- `Shortcut` Codable shape is owned by ShortcutField; ShortcutKit does not redefine it.
- Storage location: Phase 1 picks (likely `UserDefaults` with a stable key, or a JSON file under `Application Support`).

### 6.2 Migration model: append-only with applied count

Adopters declare migrations as a list passed to the registry:

```swift
ShortcutRegistry(
    contexts: [editor, window],
    migrations: [
        .renameAction(context: "editor", from: "save", to: "saveDocument"),
        .moveAction(from: ("editor", "find"), to: ("window", "find")),
        .resetOverride(context: "editor", action: "save"),
        .renameContext(from: "editor", to: "document"),
        .custom { rawStore in /* free-form mutation */ },
    ]
)
```

**Mechanism:**
1. On load, library reads `migrationsApplied: N` from persistence (default 0 if absent).
2. Library runs migrations at indices `N`, `N+1`, …, `count - 1` in order.
3. Library writes back the new applied count.

**Constraints (adopter responsibilities):**
- Never reorder migrations.
- Never remove migrations from the front of the list.
- Appending is always safe.

Each migration runs exactly once per user. Custom closures do not need to be idempotent. The library can also evolve its own on-disk format using a parallel mechanism — a separate `libraryMigrationsApplied: N` field stored alongside `migrationsApplied`, driving an internal (non-adopter-visible) migration list. The two counts are independent.

### 6.3 Migration ops (sketch — Phase 1 finalizes)

```swift
enum ShortcutMigration: Sendable {
    case renameAction(context: String, from: String, to: String)
    case moveAction(from: (context: String, action: String),
                    to: (context: String, action: String))
    case resetOverride(context: String, action: String)
    case renameContext(from: String, to: String)
    case custom(@Sendable (inout RawStore) throws -> Void)
}
```

Phase 1 spec defines the exact `RawStore` type and the precise semantics on collision (e.g., what `renameAction` does if the target key already exists).

### 6.4 Cases that do NOT need migration

- **New action added** in a release: no stored override exists → user gets the default automatically.
- **Action removed** in a release: stored override becomes an orphan → library silently drops it on next save (no migration entry needed).
- **Default shortcut changed**: user override (if any) wins; otherwise new default applies.

## 7. Cross-phase invariants

Every phase's implementation MUST hold these.

1. **Stable persistence IDs.** Action raw values and context IDs are persistent forever. Renames/moves/resets handled via `migrations:` per § 6. Adopters append, never reorder, never remove from the front.

2. **Headless-first.** Every visible affordance ships as a `Sendable` data type in Core first, with a rendered SwiftUI view layered on top in UI. No exceptions.

3. **Two-entry-point dispatch.** `dispatch(action, source:)` and `notify(action, source:)` are both available on `ShortcutContext`. HUD eligibility is `source != .shortcut && hasBinding(action)`, regardless of entry point.

4. **Sendable everywhere.** All public types are `Sendable` (Swift 6.2 strict concurrency). `@MainActor` for dispatch into UI; computation paths off-main where safe.

5. **Two-layer state.** Defaults declared in code (per-action `defaultShortcut`). Overrides persisted as `Codable`. Library merges at read time; never persists defaults.

6. **Naming patterns.** See § 5.6.

7. **ShortcutField is canonical.** ShortcutKit does NOT redefine `Shortcut` / `Step` / `Kind`. Re-exported via `@_exported import ShortcutField` in Core.

8. **No reflection.** Action enumeration is `CaseIterable`. No `Mirror`, no runtime introspection.

9. **Test convention.** Each target's `XYZTests` uses Swift Testing (`@Test`, `#expect`). Cross-target integration tests live in the consuming target's test target.

10. **Public symbol minimalism.** Default to `internal`. Promote to `public` only when adopters need it. Use `package` visibility for cross-target wiring (Swift 5.9+).

11. **Append-only migrations.** Persistence stores `migrationsApplied: N`; each migration runs exactly once. Library maintains a parallel internal applied count for its own format changes.

12. **Read API on `ShortcutContext`.** `shortcut(for:)`, `displayString(for:)`, `isCustomized(_:)`, `bindingChanges(for:)` are always available. Menu / `NSMenuItem` / SwiftUI `KeyEquivalent` helpers ship from Core.

## 8. Repo tooling

Mirror ShortcutField's tooling exactly, set up at repo init.

| File | Source | Adaptations |
|---|---|---|
| `.swiftlint.yml` | Copy verbatim from ShortcutField | None |
| `.swiftformat` | Copy verbatim | None |
| `lefthook.yml` | Copy verbatim | `pre-commit`: swiftformat + swiftlint --strict. `pre-push`: `swift build -Xswiftc -warnings-as-errors` + `swift test`. |
| `Justfile` | Copy + adapt | Same `build`/`test`/`lint`/`lint-fix`/`format`/`clean`/`tag-release-*` recipes. `example` recipe points at `Example/ShortcutKitExample.xcodeproj`. |
| `.github/workflows/ci.yml` | Copy verbatim | `macos-26` runner, build+test job, separate lint job. |
| `.gitignore` | Copy verbatim | Standard Swift defaults. |
| `.swiftpm/` | Excluded via `.gitignore` | Xcode-generated, not tracked. |

**Day-1 setup includes `lefthook install`** so hooks are active from the very first commit. Warnings-as-errors gate matches ShortcutField; `--strict` linter posture matches ShortcutField.

## 9. Versioning and distribution

- **SemVer.** Single tag across all products. `v1.4.0` versions every product simultaneously. UI-only fix bumps everyone — accepted cost, matches swift-collections / swift-syntax convention.
- **Pre-1.0 (`0.x`)** through Phases 1–3. **1.0 release ships with Phase 4** (when the public docs site at `shortcutkit.dev` is live).
- **Tagging:** `just tag-release-{patch,minor,major}` (copy ShortcutField's recipe).
- **CHANGELOG.md** at package root. Entries prefixed `[Core]` / `[UI]` / `[Global]` per release section so adopters can scan what affects them.
- **Distribution:** Swift Package Manager only. No CocoaPods, no Carthage.
- **Repo:** `github.com/nielsmadan/ShortcutKit`. MIT license (mirror ShortcutField).

## 10. Documentation strategy

**During Phases 1–3 (code-only):**
- One DocC catalog per target: `Sources/ShortcutKit/ShortcutKit.docc`, `Sources/ShortcutKitUI/ShortcutKitUI.docc`, `Sources/ShortcutKitGlobal/ShortcutKitGlobal.docc`. Each has its own landing article + symbol-graph reference. Per-target catalogs let adopters who only use one module read just its docs.
- One top-level `README.md` at package root. Sections: features summary table, install snippet, 5-minute Core quickstart, per-target "next steps."
- DocC archives indexed by Swift Package Index automatically — de-facto stopgap docs host while `shortcutkit.dev` is offline.
- Per-DocC landing articles include runnable code snippets; any code block in a DocC `.md` longer than 3 lines has a matching test case in the target's test suite (naming: `test_DocExample_<topicSlug>`).
- No per-target README. Source trees stay clean.

**Phase 4: `shortcutkit.dev`**
- Static site (generator chosen in Phase 4 spec — DocC-only with theming vs Docusaurus/Vitepress/Mintlify consuming DocC archives, based on guide-vs-reference content ratio at that time).
- CNAME setup, HTTPS via GitHub Pages or Cloudflare Pages.
- Auto-publish on tagged releases.
- README updated to point at `shortcutkit.dev` once live.

## 11. Example app

One umbrella `Example/ShortcutKitExample.xcodeproj` at the package root. Tabbed UI exercising each target:

| Tab | Demonstrates |
|---|---|
| **Core** | Define a context, declare actions, see them fire (without UI). |
| **Settings UI** | Auto-generated `KeyBindingsView` editing a registry. |
| **Legend** | `KeyBindingsLegendView` for the currently active contexts. |
| **HUD** | Discoverability HUD firing on `notify(...)` from a button. |
| **Global** | System-wide hotkey registration and recorder integration. |

Matches ShortcutField's example pattern. Single set of build/run steps; cross-target interactions can be demoed (e.g. UI + Global on one tab).

## 12. Spec organization

```
docs/superpowers/specs/
  2026-05-13-shortcutkit-package-design.md     ← this spec
  YYYY-MM-DD-shortcutkit-phase1-core.md         ← Phase 1: Core (future brainstorm)
  YYYY-MM-DD-shortcutkit-phase2-ui.md           ← Phase 2: UI + HUD (future brainstorm)
  YYYY-MM-DD-shortcutkit-phase3-global.md       ← Phase 3: Global (future brainstorm)
  YYYY-MM-DD-shortcutkit-phase4-docsite.md      ← Phase 4: shortcutkit.dev (future brainstorm)
```

Each per-phase brainstorm starts after the previous phase ships (or is at least feature-complete). Each per-phase spec references back to this meta-spec for invariants and conventions; it does not re-decide them.

## 13. Out of scope (deferred or explicitly excluded)

- **Predicate-based context activation ("when clauses" à la VS Code).** Tag-based activation is v1; predicate-based deferred to a hypothetical v2.
- **System-shortcut detection by introspection.** Apple doesn't expose the live list. Phase 1 hardcodes a known set (⌘Q, ⌘W, ⌘H, ⌘Tab, ⌘Space, …) and treats it as a warning, not a hard error. Document the scope clearly.
- **Cross-app global shortcut conflict detection.** Impossible — no public API to enumerate other apps' bindings.
- **CocoaPods / Carthage distribution.** SPM only.
- **iOS / iPadOS / visionOS support.** macOS only, in line with `KeyboardShortcuts` and ShortcutField's domain.
- **Multi-step `NSMenuItem` shortcuts.** AppKit menus cannot express them; multi-step shortcuts live outside the menu bar.
- **Localization beyond display name strings.** Glyphs are universal; labels around them use `String.LocalizationValue` on action `displayName`. No deeper i18n machinery.
- **Action discoverability via `?` cheatsheet view** (popular in web/games). Library exposes the headless `KeyBindingsLegend`; rendering the `?` overlay is left to adopting apps. No HIG precedent on macOS.

## 14. Risks

- **Scope creep across phases.** Discipline: each phase ships a meaningful product; resist "one more useful feature" rolling into the prior phase's plan.
- **Apple's input layer evolving (macOS 26+).** Liquid Glass and `MainMenu` refresh may shift the responder-chain decisions for Phase 1 and Phase 2. Watch for relevant additions before locking Phase 3 details.
- **Adoption depends on ShortcutField stability.** ShortcutKit consumes it; if ShortcutField's `Shortcut` shape needs to evolve, ShortcutKit's persistence story needs an internal migration. The applied-count mechanism handles this internally.
- **Documentation burden.** Four targets means four DocC catalogs to maintain. Plan a docs strategy (auto-generation, link-checking) before Phase 4. Per-DocC code block ↔ test convention helps.

## 15. Open questions for per-phase specs

Carried forward, not decided here:

- **Phase 1**: storage backend (UserDefaults vs Application Support JSON), reactive primitive for `bindingChanges(for:)` (Combine vs notifications), responder-chain bypass-or-bridge default, the exact `ShortcutMigration` op enum + collision semantics, the system-shortcut hardcoded list and how it surfaces.
- **Phase 2**: HUD throttling rules ("shown N times → stop"), conflict highlighting visual treatment, search/filter UX, `KeyBindingsView` style modifiers (matching ShortcutField's style API).
- **Phase 3**: permission prompt UX, Carbon event tap teardown, global ⇄ in-app coexistence rules.
- **Phase 4**: static site generator choice, content map.

## 16. Approval

| Item | Status |
|---|---|
| Brainstorm sections 1–6 (this spec) | Approved |
| Spec self-review | Pending |
| User review of written spec | Pending |
| Transition to writing-plans | Pending |
