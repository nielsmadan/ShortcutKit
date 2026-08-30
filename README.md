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

## License

[MIT](LICENSE).
