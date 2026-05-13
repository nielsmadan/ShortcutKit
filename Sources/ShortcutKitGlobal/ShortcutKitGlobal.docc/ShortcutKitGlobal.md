# ``ShortcutKitGlobal``

System-wide (global) hotkeys integrated with the ShortcutKit action registry.

## Overview

ShortcutKitGlobal reimplements global hotkey support on top of Carbon's `RegisterEventHotKey` and `NSEvent` monitors, without depending on third-party libraries. Each action in the registry can have a global binding in addition to its in-app binding.

> Public API arrives in Phase 3. See the [package design spec](https://github.com/nielsmadan/ShortcutKit/blob/main/docs/superpowers/specs/2026-05-13-shortcutkit-package-design.md) for the current state.

## Topics

### Phase 3 — Coming soon

- Global hotkey registration
- Permission/accessibility prompt flow
- Coexistence rules with in-app bindings
