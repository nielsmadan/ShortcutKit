# ``ShortcutKit``

Action registry, context activation, dispatch, and persistence for macOS apps.

## Overview

ShortcutKit lets you declare shortcut **actions** as Swift enums, group them into **contexts**, and bind callbacks declaratively. The registry handles user customization persistence, conflict detection, and exposes a read API for showing the currently-effective binding in menus and other UI.

This module also re-exports [ShortcutField](https://github.com/nielsmadan/ShortcutField) — `Shortcut`, `Shortcut.Step`, `ContinuousShortcut`, and related types are available with a single `import ShortcutKit`.

> Public API arrives in Phase 1. See the [package design spec](https://github.com/nielsmadan/ShortcutKit/blob/main/docs/superpowers/specs/2026-05-13-shortcutkit-package-design.md) for the current state.

## Topics

### Phase 1 — Coming soon

- Action declaration (the `ShortcutAction` protocol)
- Context registration and activation
- Dispatch and notify
- Persistence and append-only migrations
- Within-context and cross-context conflict detection
- Lookup API: `shortcut(for:)`, `displayString(for:)`, `isCustomized(_:)`, `bindingChanges(for:)`
- Menu helpers: `NSMenuItem` and SwiftUI `KeyEquivalent` bridges
