# 0002 — Key-repeat suppression is per-action policy in Core

Date: 2026-08-23 · Status: Accepted

## Context

Holding a key repeats the action. That is right for nudging and wrong for
deletions. TanStack Hotkeys models this as `requireReset`, defaulting to
`false` — so its default matches ours and only the opt-out was missing.

[ADR 0001](0001-event-matching-fixes-belong-in-shortcutfield.md) argues that
event-matching concerns belong in ShortcutField, which would suggest pushing
this down too.

## Decision

Keep it in ShortcutKit as `ShortcutActionDefinition.allowsKeyRepeat`
(default `true`), gated in `ContextMatcher.handle(_:)`.

ADR 0001's tests do not apply: suppressing repeats is a statement about what an
*action* means, not about how an event matches. `ContextMatcher` is also the
only place that sees both the `NSEvent` and the matched action —
`RegistryEventRouter` sees the event but not which action won.

## Consequences

- No ShortcutField release needed; the change did not couple to work in flight
  there.
- `.onShortcut` adopters cannot opt out of auto-repeat. Accepted; if anyone
  asks, the primitive moves down and the field becomes a pass-through. Tracked
  in `docs/ROADMAP.md`.
- A suppressed repeat still returns `.fired` so the event is consumed —
  otherwise held-key repeats leak into the responder chain and beep.
- Reading `NSEvent.isARepeat` throws on scroll and gesture events, so the
  `.keyDown` guard before it is load-bearing and pinned by a test.
