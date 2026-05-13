# ShortcutKit

[![Swift 6.2](https://img.shields.io/badge/Swift-6.2-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-blue.svg)](https://developer.apple.com/macos/)
[![License](https://img.shields.io/badge/license-MIT-lightgrey.svg)](LICENSE)

VS Code–style keybindings for native macOS apps. Higher-level shortcut management built on top of [ShortcutField](https://github.com/nielsmadan/ShortcutField).

> ⚠️ **Pre-release.** ShortcutKit is under active development. Public API stabilizes at 1.0 alongside the documentation site at `shortcutkit.dev`. Track progress against the [phase plan](ShortcutKitDevelopment.md).

## Products

| Product | Purpose |
|---|---|
| `ShortcutKit` | Action registry, context activation, dispatch + notify, persistence, conflict detection. |
| `ShortcutKitUI` | Auto-generated settings view, legend, discoverability HUD. |
| `ShortcutKitGlobal` | System-wide (global) hotkeys integrated with the registry. |

## Installation

Swift Package Manager (once a pre-release tag exists):

```swift
dependencies: [
    .package(url: "https://github.com/nielsmadan/ShortcutKit", from: "0.1.0")
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

Phase 1 (Core) — in design.

See [`ShortcutKitDevelopment.md`](ShortcutKitDevelopment.md) for the vision document and [`docs/superpowers/specs/`](docs/superpowers/specs/) for the package design meta-spec.

## License

[MIT](LICENSE).
