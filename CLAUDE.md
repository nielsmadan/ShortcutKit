# CLAUDE.md

## Build & Run

```bash
just build    # Build the package
just test     # Run tests
just lint     # Run SwiftLint
just format   # Run SwiftFormat
just lint-fix # Auto-fix SwiftLint violations
just clean    # Remove build directory
just tag-release-patch  # Tag and push a patch release
just tag-release-minor  # Tag and push a minor release
```

`just example` is omitted until the Phase 1 Xcode example app is added.

## Architecture

ShortcutKit is a Swift package providing higher-level shortcut management for macOS apps, built on top of [ShortcutField](https://github.com/nielsmadan/ShortcutField). Three library products:

- **`ShortcutKit` (Core)** — Action registry, context activation, dispatch + notify, persistence with append-only migrations, conflict detection, lookup API (`shortcut(for:)`, `displayString(for:)`, `isCustomized(_:)`, `bindingChanges(for:)`), menu helpers. Re-exports ShortcutField's `Shortcut` and related types via `@_exported import`.
- **`ShortcutKitUI`** — Auto-generated settings view (`KeyBindingsView`), legend (`KeyBindingsLegendView`), and discoverability HUD (`ShortcutHintHUD`).
- **`ShortcutKitGlobal`** — System-wide hotkeys via Carbon `RegisterEventHotKey`; no external dependency on `KeyboardShortcuts`.

## Phase status

| Phase | Target | Status |
|---|---|---|
| Phase 1 | `ShortcutKit` (Core) | Not started |
| Phase 2 | `ShortcutKitUI` | Not started |
| Phase 3 | `ShortcutKitGlobal` | Not started |
| Phase 4 | `shortcutkit.dev` docs site | Not started |

Vision doc: [`ShortcutKitDevelopment.md`](ShortcutKitDevelopment.md).
Package design meta-spec: [`docs/superpowers/specs/2026-05-13-shortcutkit-package-design.md`](docs/superpowers/specs/2026-05-13-shortcutkit-package-design.md).

## Code Style

- SwiftLint (`--strict`) and SwiftFormat configured.
- 4-space indentation, 120 char max width.
- Swift Testing framework (`@Test`, `#expect`).
- Swift 6.2 language mode (strict concurrency — all public types must be `Sendable`).
- macOS 13+ minimum deployment target.
- Pre-commit hook (via `lefthook`) auto-formats and lints staged Swift files; pre-push runs `swift build -Xswiftc -warnings-as-errors` and `swift test`.

## Cross-phase invariants

All 12 invariants in §7 of the package design spec are load-bearing. The high-impact ones for day-to-day work:

1. **Stable persistence IDs** — action raw values and context IDs persist forever; renames go through declared migrations.
2. **Headless-first** — every UI affordance has a `Sendable` data type in Core, with the SwiftUI view layered in UI.
3. **Append-only migrations** — adopter appends to the migration list; library tracks `migrationsApplied: N` in persistence.
4. **ShortcutField is canonical** — never redefine `Shortcut` / `Step` / `Kind`.
5. **Public symbol minimalism** — default `internal`; promote to `public` only when adopters need it.
