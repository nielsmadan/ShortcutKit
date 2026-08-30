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
- [Beep suppression](#beep-suppression)

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

## Beep suppression

An intermediate chord step is a *successful* match, but ShortcutField hands the
event back to AppKit unless it must be consumed. With no responder for it, AppKit
plays the system alert sound.

`.advanced(consumeEvent: false)` means the matcher **advanced**; it never means
the prefix was rejected. `consumeEvent` is `true` only for a `keyDown` the focus
system would intercept (in `SequenceMatcher.handle(_:)`), so an ordinary ⌘K prefix
returns `false` and beeps.

*Verified 2026-08-30 against 2.4.0 (`0d4ebe1`).*

Two public entry points install the fix, both landing in
`BeepSuppressor.installOverride` (`SuppressShortcutBeep.swift`):

- **`View.suppressShortcutBeep()`** — for a hosting window you don't own, e.g. a
  `WindowGroup` scene.
- **`ShortcutTracking.installBeepSuppression()`** — the same install with no view
  or window to hang it off. Idempotent, so it is safe on every launch path.

**The mechanism is a runtime swizzle.**
`ShortcutTracking.installBeepSuppression()` passes `NSResponder.self`, so
`method_setImplementation` patches every responder in the process.
`View.suppressShortcutBeep()` passes the concrete hosting-window class; for a
standard window, `class_getInstanceMethod` resolves the inherited
`NSResponder.noResponder(for:)` method and produces the same process-wide patch.
If a custom `NSWindow` subclass overrides the selector, the modifier patches
that override instead. Installation dedupes on the *resolved method* rather than
the class passed in, but **there is no uninstall path.**

**Its behavioural reach is narrow**, which is what makes that acceptable: the
replacement returns early only when the event selector is `keyDown(with:)` *and*
`ShortcutTracking.isActive`. Every other selector, and every `keyDown` outside an
in-progress sequence, reaches the original implementation.

**Unrecognized keys still beep.** A step that fails to match calls `reset()`
before returning `.ignored`, so `isActive` is already `false` by the time AppKit
goes looking for a responder. Only genuine mid-sequence steps are silenced.

**An `NSWindow` subclass that overrides `noResponder(for:)` bypasses a
process-wide `NSResponder` patch.** Apply `View.suppressShortcutBeep()` inside
that window to patch the subclass's implementation, or override
`noResponder(for:)` directly and gate on `ShortcutTracking.isActive`.
