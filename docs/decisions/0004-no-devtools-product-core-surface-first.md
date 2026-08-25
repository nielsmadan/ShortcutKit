# 0004 — No DevTools product; ship the Core debug surface first

Date: 2026-08-25 · Status: Accepted

## Context

ShortcutKit tells a developer nothing when a shortcut fails to fire, and there
are five separate paths to that silence. TanStack Hotkeys ships a devtools panel
per framework, and the obvious mirror was a fourth product,
`ShortcutKitDevTools`, with its own window scene.

## Decision

Add the debug data surface to Core only. The Example app is the first consumer,
as a debug window. No new product.

A product in `Package.swift` is a permanent contract, and demand for this one is
unproven — the shape was carried over from a web ecosystem rather than tested
against this repo. The Core symbols are identical either way, so going
Core-first commits to nothing extra and defers the part that cannot yet be
justified.

## Consequences

- The Example app is a consumer we can be rough with: if `stackDepth` is not
  what you want to see, or `noMatch` is too coarse, changing it costs a commit
  instead of a deprecation.
- Core exposes a *stream* and stores nothing, so the later event trace is a
  consumer-side change with no Core API churn. That staging is the point of the
  design.
- Promotion to a product later stays additive.
- Design: `docs/superpowers/specs/2026-08-25-shortcutkit-debug-surface-design.md`
  (local-only unless force-added); summary in `docs/ROADMAP.md`.
