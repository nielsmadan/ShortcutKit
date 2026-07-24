# Repository Guidelines

This is the single source of truth for agentic coding instructions. Claude Code
reads it via an `@AGENTS.md` import in `CLAUDE.md`; other agents read it directly.

## Project Structure & Module Organization

`ShortcutKit` is a Swift Package for macOS providing higher-level shortcut management, built on top of [ShortcutField](https://github.com/nielsmadan/ShortcutField). Three library products live under `Sources/`:

- **`Sources/ShortcutKit/` (Core)** — Action registry, context activation, dispatch + notify, persistence with append-only migrations, conflict detection, lookup API (`shortcuts(for:)`, `displayStrings(for:)`, `isCustomized(_:)`, `shortcutsChanges(for:)`), menu helpers. Re-exports ShortcutField's `Shortcut` and related types via `@_exported import`.
- **`Sources/ShortcutKitUI/`** — Auto-generated settings view (`KeyBindingsView`), legend (`KeyBindingsLegendView`), and discoverability HUD (`ShortcutHintHUD`).
- **`Sources/ShortcutKitGlobal/`** — System-wide hotkeys via Carbon `RegisterEventHotKey`; no external dependency on `KeyboardShortcuts`.

Tests mirror the source layout under `Tests/`. Each target has its own DocC catalog (`Sources/<Target>/<Target>.docc/`).

Specs and plans are tracked under `docs/superpowers/specs/` and `docs/superpowers/plans/`. The vision doc is [`ShortcutKitDevelopment.md`](ShortcutKitDevelopment.md); the package design meta-spec is [`docs/superpowers/specs/2026-05-13-shortcutkit-package-design.md`](docs/superpowers/specs/2026-05-13-shortcutkit-package-design.md).

## Build, Test, and Development Commands

Use `just` for the common workflow:

```bash
just build          # Build the package (swift build -Xswiftc -warnings-as-errors)
just test           # Run the full test suite (swift test)
just lint           # Check style with SwiftLint (--strict)
just lint-fix       # Apply SwiftLint auto-corrections before submitting
just format         # Format the repository with SwiftFormat
just clean          # Remove the build directory
just example        # Build and run the SwiftUI example app
just reset-example  # Clear the example app's persisted overrides
just tag-release-patch  # Tag and push a patch release
just tag-release-minor  # Tag and push a minor release
```

`pre-commit` (via `lefthook`) auto-runs `swiftformat` + `swiftlint --strict` on staged Swift files; `pre-push` runs `swift build` + `swift test`. Install hooks with `lefthook install` on a fresh checkout.

## Coding Style & Naming Conventions

This package targets Swift 6.2 (strict concurrency — all public types must be `Sendable`) and macOS 13+. Follow the existing style: 4-space indentation, 120-character line width, and `Sendable`-safe code for new types. UpperCamelCase for types (`ShortcutContext`), lowerCamelCase for properties and methods (`displayString`), and keep file names aligned with the primary type or extension they contain (`Shortcut+Matching.swift`-style extension files).

## Testing Guidelines

Tests use Swift Testing (`@Test`, `#expect`). Test files live in the target's matching `Tests/<Target>Tests/` directory. Cross-target integration tests live in the consuming target's test suite (e.g., UI ↔ Core integration goes in `ShortcutKitUITests/`, not `ShortcutKitTests/`).

When adding a DocC code example longer than 3 lines, add a matching test named `test_DocExample_<topicSlug>` in the target's test suite — keeps documentation from silently drifting from the API.

In `#expect`, don't put bare integer-literal arithmetic on one side of `==` against a `CGFloat`/`Double` — the macro evaluates the arithmetic operand as `Int`, giving a false failure that reads as "152.0 == 152 unequal". Use a single typed literal (`#expect(center.x == 152)`) or precompute the expected value into a `CGFloat`/`Double` `let`.

## Verifying dependency behavior

Before asserting what a dependency does — especially event handling, availability annotations, or OS event interception — read its source, don't reason from first principles. ShortcutField and KeyboardShortcuts are checked out as siblings (`../ShortcutField`, `../KeyboardShortcuts`); read them directly. (ShortcutField uses `NSEvent.addLocalMonitorForEvents`, so it *does* see OS-level shortcuts like ⌘Space — a first-principles guess got this wrong once.)

## Squashing history

Don't use the squash-commits skill's default `git merge --squash <tip> && git commit` here: the lefthook pre-commit reformats staged content (rebuilt tree diverges) and `rerere.enabled=true` replays stale conflict resolutions, producing phantom conflicts mid-rebuild. Rebuild the chain with `git commit-tree` instead (stamp each group-tip's exact tree onto a parent chain — no hook, no merge, no rerere), then `git reset --soft`. Verify `git diff ORIG_TIP NEW` is empty and keep a backup tag first.

## Phase status & phase-aware work

Implementation proceeds in 4 sequential phases (see [`ShortcutKitDevelopment.md`](ShortcutKitDevelopment.md) and the package design spec). The three library products are implemented and tested; the public API is stabilizing toward 1.0.

| Phase | Target | Status |
|---|---|---|
| Phase 1 | `ShortcutKit` (Core) | Implemented (pre-1.0) |
| Phase 2 | `ShortcutKitUI` | Implemented (pre-1.0) |
| Phase 3 | `ShortcutKitGlobal` | Implemented (pre-1.0) |
| Phase 4 | `shortcutkit.dev` docs site | Not started |

Each phase has its own brainstorm → spec → plan → execute cycle. Avoid pulling work from a later phase into an earlier one without revisiting the phase boundaries.

## Cross-phase invariants

All 12 invariants in §7 of the package design spec are load-bearing. The high-impact ones for day-to-day work:

1. **Stable persistence IDs** — action raw values and context IDs persist forever; renames go through declared migrations.
2. **Headless-first** — every UI affordance has a `Sendable` data type in Core, with the SwiftUI view layered in UI.
3. **Append-only migrations** — adopter appends to the migration list; migrations are idempotent / content-detecting (Zed-style) so no version counter is needed on `RawState`.
4. **ShortcutField is canonical** — never redefine `Shortcut` / `Step` / `Kind`.
5. **Public symbol minimalism** — default `internal`; promote to `public` only when adopters need it.
