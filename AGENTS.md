# Repository Guidelines

## Project Structure & Module Organization

`ShortcutKit` is a Swift Package for macOS. Three library products live under `Sources/`:

- `Sources/ShortcutKit/` — Core: registry, dispatch, persistence, conflicts. Re-exports `ShortcutField`.
- `Sources/ShortcutKitUI/` — Auto-generated settings UI, legend, and discoverability HUD.
- `Sources/ShortcutKitGlobal/` — System-wide hotkeys via Carbon.

Tests mirror the source layout under `Tests/`. Each target has its own DocC catalog (`Sources/<Target>/<Target>.docc/`).

Specs and plans are tracked under `docs/superpowers/specs/` and `docs/superpowers/plans/`. The vision doc is `ShortcutKitDevelopment.md` at the repo root.

## Build, Test, and Development Commands

Use `just` for the common workflow:

- `just build` builds the Swift package with `swift build -Xswiftc -warnings-as-errors`.
- `just test` runs the full test suite with `swift test`.
- `just lint` checks style with SwiftLint (`--strict`).
- `just format` formats the repository with SwiftFormat.
- `just lint-fix` applies SwiftLint auto-corrections before submitting.

`pre-commit` (via `lefthook`) auto-runs `swiftformat` + `swiftlint --strict` on staged Swift files; `pre-push` runs `swift build` + `swift test`. Install hooks with `lefthook install` on a fresh checkout.

## Coding Style & Naming Conventions

This package targets Swift 6.2 and macOS 13+. Follow the existing style: 4-space indentation, 120-character line width, and `Sendable`-safe code for new types. UpperCamelCase for types (`ShortcutContext`), lowerCamelCase for properties and methods (`displayString`), and keep file names aligned with the primary type or extension they contain (`Shortcut+Matching.swift`-style extension files).

## Testing Guidelines

Tests use Swift Testing (`@Test`, `#expect`). Test files live in the target's matching `Tests/<Target>Tests/` directory. Cross-target integration tests live in the consuming target's test suite (e.g., UI ↔ Core integration goes in `ShortcutKitUITests/`, not `ShortcutKitTests/`).

When adding a DocC code example longer than 3 lines, add a matching test named `test_DocExample_<topicSlug>` in the target's test suite — keeps documentation from silently drifting from the API.

## Phase-aware work

Implementation proceeds in 4 sequential phases (see `ShortcutKitDevelopment.md` and the package design spec). Each phase has its own brainstorm → spec → plan → execute cycle. Avoid pulling work from a later phase into an earlier one without revisiting the phase boundaries.
