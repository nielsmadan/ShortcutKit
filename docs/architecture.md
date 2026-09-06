# Architecture

ShortcutKit is one Swift package with three library products and one release tag.
The split keeps the Core usable without SwiftUI settings or Carbon hotkeys while letting adopters add either layer independently.

## Product boundaries

| Product | Responsibility | Dependencies |
| --- | --- | --- |
| `ShortcutKit` | Action and context model, activation, dispatch, persistence, conflict analysis, headless key-binding data, and menu helpers | ShortcutField, TOMLKit, swift-toml-edit |
| `ShortcutKitUI` | Settings, recorder, legend, and shortcut-hint SwiftUI views | ShortcutKit, ShortcutField |
| `ShortcutKitGlobal` | System-wide registration and status through Carbon | ShortcutKit |

`ShortcutKit` is the umbrella Core product, not a façade over the other products.
The UI and Global targets depend inward on Core; Core does not import either of them.
ShortcutField remains the canonical owner of `Shortcut`, `Shortcut.Step`, and `Shortcut.Kind`, which Core re-exports for adopters.

## Data and dispatch flow

Adopters declare `CaseIterable` string-backed `ShortcutAction` values and group them in a stable-ID `ShortcutContext`.
A `ShortcutRegistry` combines declared defaults with persisted overrides and routes active local contexts or registered global contexts.

`ShortcutContext.dispatch(_:)` invokes the active handler and publishes an action-fired event.
`ShortcutContext.notify(_:)` publishes the same event without invoking the handler, for actions the adopter already executed elsewhere.
Lookup stays on the context through `shortcuts(for:)`, `displayStrings(for:)`, `isCustomized(_:)`, and `shortcutsChanges(for:)`.

Visible features follow a headless-first split.
Core owns `Sendable` data such as `KeyBindings`; `ShortcutKitUI` renders those values and owns presentation state.

## Persistence

Only user overrides and non-default preferences are stored; declared defaults remain in code and are merged at read time.
Context IDs and action raw values are persistence identifiers and must remain stable.
Renames, moves, and resets use an append-only list of idempotent, content-detecting `ShortcutMigration` values.
There is no applied-version counter, so every shipped migration must remain safe to run again.

`TOMLFile` owns lossless assignment edits, coherent snapshots, structured
diagnostics, stale-revision checks, and atomic file replacement. A namespaced
`FileStore` owns ShortcutKit's schema within those bytes. An adopter sharing the
file with another schema owns the aggregate validation and submits one composed
edit plan, so neither schema can commit a document invalid for the other.

## Package invariants

1. The three products ship from one package and one semantic-version tag.
2. Core never depends on UI or Global.
3. UI affordances are backed by headless `Sendable` Core values.
4. `dispatch(_:)` and `notify(_:)` remain distinct entry points.
5. Defaults live in code; persistence contains only overrides and non-default preferences.
6. Context IDs and action raw values are stable persistence IDs.
7. Migrations are append-only, idempotent, and content-detecting.
8. ShortcutField owns the shortcut value types; ShortcutKit does not redefine them.
9. Action enumeration uses `CaseIterable`, never reflection.
10. All public types are `Sendable`, and UI-bound types and mutation are main-actor isolated.
11. Public symbols are added for adopter needs; cross-target wiring stays internal or package-visible.
12. Tests live with the target that consumes the behavior, including cross-target integration tests in the consuming target's suite.

## Documentation ownership

The DocC catalogs under `Sources/<Target>/<Target>.docc/` document public APIs and adopter workflows.
This file owns package boundaries and invariants, `docs/decisions/` owns rationale, and `docs/ROADMAP.md` owns accepted future work.
