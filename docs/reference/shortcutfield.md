# ShortcutField behaviour

How our recorder/matching dependency actually behaves. Anchored to
**ShortcutField 2.4.0** (`0d4ebe1`); checked out as a sibling at
`../ShortcutField`.

Every claim says how it was established. **Verified** = we read the source or ran
it, with the date and version. **Documented** = upstream says so. When the
dependency moves, re-check the verified claims first — no changelog will tell you
they changed.

## Contents

- [Matching is by physical key code](#matching-is-by-physical-key-code)
- [Display resolves against the current layout](#display-resolves-against-the-current-layout)
- [Event delivery](#event-delivery)
- [The text-input focus gate (2.4.0)](#the-text-input-focus-gate-240)
- [Internal seams we rely on](#internal-seams-we-rely-on)

## Matching is by physical key code

`DiscreteShortcut.Step` stores `kind: .key(keyCode: UInt16)` and matching is
`event.type == .keyDown && event.keyCode == keyCode`
(`Matching/DiscreteShortcut+Matching.swift`). Shortcuts are therefore
**layout-independent**.

*Verified 2026-08-23 against 2.3.1; unchanged in 2.4.0.*

**Why it matters:** hazards that afflict character-keyed libraries do not apply.
⌥+letter producing `å`, Shift+number producing punctuation — these break
libraries that key off `event.key` (TanStack Hotkeys falls back to `event.code`
for exactly this reason). We nearly shipped a borrowed "⌥+letter may not work"
warning on that false premise. See
[ADR 0003](../decisions/0003-layout-exclusive-keys-warn-optionletter-does-not.md).

**The real residual:** some physical keys exist on only one keyboard family —
`kVK_ISO_Section` on ISO, `kVK_JIS_*` on JIS. Those bindings work for whoever
recorded them and are unreachable elsewhere.

## Display resolves against the current layout

`keyToCharacter(keyCode:)` goes through
`TISCopyCurrentASCIICapableKeyboardLayoutInputSource` + `UCKeyTranslate` with
`kUCKeyActionDisplay` and `kUCKeyTranslateNoDeadKeysBit`
(`DiscreteShortcut+KeyMapping.swift`, adapted from sindresorhus/KeyboardShortcuts).

*Verified 2026-08-23 against 2.3.1.*

So a key renders with the cap the user actually has, and dead keys are
suppressed. Non-Latin layouts fall back to an ASCII-capable layout — that is what
"ASCIICapable" in the API name buys.

## Event delivery

`ShortcutEventDispatcher` installs a single app-wide
`NSEvent.addLocalMonitorForEvents`, lazily on first registration and torn down
when the last handler unregisters. Handlers are called **newest-first, all of
them** — the ordering is a guarantee, not early termination, so prefix-sharing
matchers advance in parallel.

*Verified 2026-08-25 against 2.4.0.*

**Consequence:** it *does* see OS-level shortcuts like ⌘Space. A
first-principles guess got this wrong once.

`ShortcutRecordingState.isAnyRecording` is a global gate at the top of
`handleEvent` — while any recorder is active, no matcher sees events.

## The text-input focus gate (2.4.0)

While an editable `NSTextView` is first responder, a matching keystroke is
surrendered to the field. The rule is derived from the step's **shape**, not
configured:

| Step | Behaviour while editing |
|---|---|
| Carries ⌘ or ⌃ | fires |
| Escape, F1–F20 (`producesNoText`) | fires |
| Bare key, or ⇧/⌥-only | suppressed |
| Any step where `currentStep > 0` | fires |

*Verified 2026-08-25 against 2.4.0 (`fb0e78a`).*

**`NSTextView` is the only check**, and that is sufficient: AppKit installs a
text field's *field editor* — an `NSTextView` — as first responder, so it covers
`NSTextField`, `NSSearchField`, `NSTextView`, and the SwiftUI controls backed by
them. Buttons and other non-text responders are excluded by construction.

**Known gap, upstream's own note:** a `WKWebView` with a focused `contenteditable`
reports `false`. Detecting it needs an async `evaluateJavaScript` round trip, and
this runs synchronously inside an `NSEvent` monitor.

**The gate returns `.ignored`** — the same value as "did not match". A caller
cannot distinguish a focus-gated keystroke from an unbound one. This is what
blocks our debug surface from reporting the reason; tracked in
`docs/ROADMAP.md`.

## Internal seams we rely on

Both are `internal`, reachable from our tests via `@testable import ShortcutField`
(SwiftPM builds dependencies with testability in debug).

- **`TextInputFocus.responderOverride`** — replaces the live key-window lookup.
  Needed because a unit-test process has no key window, so the live lookup always
  reports no focus. Used by `TextInputFocusGateTests`.
- **`SequenceMatcher.currentStep` / `isTracking`** — `private(set)`, so
  mid-sequence state is *not* reachable from ShortcutKit. This is the constraint
  that decided [ADR 0001](../decisions/0001-event-matching-fixes-belong-in-shortcutfield.md).

*Verified 2026-08-25 against 2.4.0.*
