# 0003 — Warn on layout-exclusive keys; do not warn on ⌥+letter

Date: 2026-08-23 · Status: Accepted

## Context

TanStack Hotkeys' `validateHotkey` warns that *"Alt+letter combinations may not
work on macOS due to special characters."* Borrowing it looked like free value
for our conflict model.

## Decision

Reject the ⌥+letter warning; add `Conflict.layoutExclusiveKey` instead.

The borrowed warning does not transfer. It exists because TanStack keys off
`event.key` — the *character* — so ⌥+A yields `å` and breaks matching, which is
why they fall back to `event.code`. ShortcutField has no such hazard on either
side, verified in its source:

- **Matching** is `event.keyCode == keyCode` — physical, layout-independent.
- **Display** resolves through `TISCopyCurrentASCIICapableKeyboardLayoutInputSource`
  + `UCKeyTranslate` with dead keys suppressed, against the user's *current*
  layout.

Shipping it would have warned users about a problem we do not have.

The real macOS residual is different: some physical keys exist on only one
keyboard family. `kVK_ISO_Section` (`§`/`±`) is absent from ANSI and JIS boards;
the `kVK_JIS_*` keys exist only on Japanese ones. Because matching is by key
code, such a binding works perfectly for whoever recorded it and is unreachable
on anyone else's hardware — invisible to the developer who created it.

## Consequences

- `.warning` severity, not `.error`: the binding is valid, just not portable.
- Detection scans every step of a chord — a layout-exclusive key in position two
  makes the chord equally unreachable.
- **Do not port prior-art warnings without checking the premise against our own
  event model.** This one was three lines from shipping. See the ShortcutField
  facts in `AGENTS.md`.
