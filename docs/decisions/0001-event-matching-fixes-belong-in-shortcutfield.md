# 0001 — Event-matching fixes belong in ShortcutField, not ShortcutKit

Date: 2026-08-24 · Status: Accepted

## Context

Bare-key shortcuts fired while the user was typing into a text field: binding
`K` to "search" made the letter `k` unusable in every field in the app. The bug
was noticed in ShortcutKit, and `RegistryEventRouter.handle(_:)` looked like a
convenient chokepoint — it is the single funnel for all local dispatch.

## Decision

Fix it in ShortcutField's matcher instead, and let ShortcutKit inherit it
through the dependency.

Two tests decide which layer owns a fix of this kind:

1. **Does `.onShortcut` have the same bug without ShortcutKit?** Here it did —
   a ShortcutKit-level fix would have left every standalone ShortcutField
   adopter broken.
2. **Does the fix need matcher-internal state?** It needed `currentStep` to let
   a chord's bare second step through. `RegistryEventRouter` observes
   `.advanced` only *after* a matcher consumed the event, so it cannot tell
   start-of-chord from mid-chord without duplicating sequence state.

## Consequences

- Accept a cross-repo release rather than working around it in Core. Shipped as
  ShortcutField 2.4.0; ShortcutKit needed **no code change** — that inheritance
  is the signal the layering was right.
- ShortcutField's gate returns `.ignored`, indistinguishable from "did not
  match", so ShortcutKit cannot report *why* a keystroke vanished. Tracked in
  `docs/ROADMAP.md` under cross-repo follow-ups.
- Generalised beyond the original brief: Escape and F1–F20 fire in fields as
  "keys that produce no text", while navigation and editing keys deliberately
  stay with the field because they act on the text.
