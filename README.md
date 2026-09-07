# ShortcutKit

[![Swift 6.2](https://img.shields.io/badge/Swift-6.2-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-blue.svg)](https://developer.apple.com/macos/)
[![License](https://img.shields.io/badge/license-MIT-lightgrey.svg)](LICENSE)

VS Code–style keybindings for native macOS apps. Higher-level shortcut management built on top of [ShortcutField](https://github.com/nielsmadan/ShortcutField).

> ⚠️ **Pre-release.** ShortcutKit is under active development. Public API stabilizes at 1.0 alongside the documentation site at `shortcutkit.dev`. Track what's planned in the [roadmap](docs/ROADMAP.md).

## Products

| Product | Purpose |
|---|---|
| `ShortcutKit` | Action registry, context activation, dispatch + notify, persistence, conflict detection. |
| `ShortcutKitUI` | Auto-generated settings view, legend, discoverability HUD. |
| `ShortcutKitGlobal` | System-wide (global) hotkeys integrated with the registry. |

## Installation

Swift Package Manager (pre-1.0 — pin a minor version, as the API may change):

```swift
dependencies: [
    .package(url: "https://github.com/nielsmadan/ShortcutKit", from: "0.5.1")
]
```

Per-target imports:

```swift
.target(
    name: "MyApp",
    dependencies: [
        .product(name: "ShortcutKit",       package: "ShortcutKit"),
        .product(name: "ShortcutKitUI",     package: "ShortcutKit"),
        .product(name: "ShortcutKitGlobal", package: "ShortcutKit"),
    ]
)
```

## Status

All three products — `ShortcutKit` (Core), `ShortcutKitUI`, and `ShortcutKitGlobal` — are implemented and tested. The public API is stabilizing toward 1.0; the `shortcutkit.dev` docs site is still to come.

See [`docs/ROADMAP.md`](docs/ROADMAP.md) for the forward-looking backlog and [`docs/architecture.md`](docs/architecture.md) for package boundaries and invariants.

## Releases

Run `just release` from a clean, current `main` checkout with complete history and matching
local/origin release tags. It proposes a version, runs `just check`, then prompts. Enter `y` to
publish, a version or `patch`/`minor`/`major` to revise the proposal, or press Enter to cancel.
This tooling requires Python 3.9+ in addition to the development tools.

`just release minor` and `just release 1.0.0` preselect an override through the same prompt.
`just release --dry-run` reads Git state and previews without checks or publication. `--yes`
explicitly confirms unattended use; other nonterminal invocations fail. `feat` proposes a minor
bump, `fix`/`perf` a patch, and breaking changes a major bump (minor during `0.x`). Maintenance-only
changes require an explicit bump.

Confirmation atomically pushes `main` and an annotated tag for Swift Package Manager consumers.
There is no version-file preparation commit. The preview counts existing local commits included
in the push. Checks are declared in `scripts/release.json`. Failed pushes leave the local tag for
inspection; public tags must not be replaced.

## License

[MIT](LICENSE).
