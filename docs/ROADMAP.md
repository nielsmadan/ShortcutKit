# ShortcutKit Roadmap

Forward-looking backlog. The per-layer API-review audit trail that produced most
of today's design (2026-05 → 07) has served its purpose and lives in git history —
`git log -- docs/api-review.md` recovers the full resolved punch-list and the
rationale behind the current public surface.

## Proposed features (unscheduled)

### Debug surface (designed, awaiting plan)

A Core debug data surface — ordered activation stack, a per-keystroke outcome
publisher, and a recording flag — consumed by a debug window in the Example app.
Answers "why didn't my shortcut fire", which today has no supported answer: five
separate paths lead to a silent keystroke and none is observable.

Design is complete and approved:
[`specs/2026-08-25-shortcutkit-debug-surface-design.md`](superpowers/specs/2026-08-25-shortcutkit-debug-surface-design.md).
Staged so a full event trace later is a consumer-side change with no Core API
churn. A `ShortcutKitDevTools` product was designed and deliberately rejected as
premature.

### Sanctioned conflicts

`Conflict` / `Severity` has no acknowledgement channel, so a deliberate overlap
warns in the settings pane forever. Wanted: a way to record "this one is fine".

Not small — the acknowledgement has to persist, which touches `RawState` and the
migration list (invariant 1). Needs its own design pass. Prior art: TanStack
Hotkeys makes this a per-registration `conflictBehavior` policy; only its
`'allow'` case maps onto a persisted-override model, and `'replace'` / `'error'`
actively fight one.

### Runnable example per feature (Phase 4)

TanStack ships one minimal runnable example per hook, and it is what makes their
docs read as complete. Our DocC catalogues cover the reference half. Pairs with
the existing `test_DocExample_<topicSlug>` rule — an example that is both
compiled and rendered cannot drift.

## Cross-repo follow-ups (ShortcutField)

- **Focus-gate attribution.** ShortcutField's text-input focus gate returns
  `.ignored`, indistinguishable from "did not match", so ShortcutKit cannot
  report *why* a keystroke vanished. Reporting it needs `ShortcutMatchResult`
  enriched with a reason. Blocks the debug surface from distinguishing
  focus-gated keystrokes from unbound ones (see that spec's §6).
- **Key-repeat suppression for `.onShortcut`.** `allowsKeyRepeat` lives on
  `ShortcutActionDefinition`, so ShortcutField's own `.onShortcut` adopters
  cannot opt out of auto-repeat. Push the primitive down if anyone asks.

### Command launcher / palette (Phase 3.5 candidate)

A Notion / Superhuman / Linear-style modal palette in `ShortcutKitUI`: a search
field over every registered action, enter-to-execute. Actions are already the
right primitive, so the launcher is "enumerate every `includeInSettings` action,
fuzzy-match on display name, dispatch on enter."

- **Reuses:** `FuzzyFilter`, `KeyBindings` enumeration, `ActionFiredEvent`, and
  `registry.dispatch(contextID:actionID:)`.
- **Needs:** a `CommandLauncherView` (sheet + window presentations) and a
  `.commandLauncher(isPresented:)` modifier; optionally an action-source
  extension point so adopters can inject non-shortcut commands ("Open recent…").
- Substantial UI addition with its own design decisions (presentation, keyboard
  nav, non-shortcut commands) — treat as a peer phase, not a cleanup bullet.

### KeyboardShortcuts 3.0 parity pickups

Additive, headless-first (data type in Core, UI layered on top):

- **Customizable recorder validation** (highest value) — a `validate: (Shortcut)
  -> ValidationResult` closure on `ShortcutBindingEditor` / `KeyBindingsView`, so
  adopters can reject specific combos ("don't let users bind ⌘Q here"), surfaced
  through the existing inline-rejection path. Today only scope-policy validation
  exists. Doesn't touch the data model.
- **Repeating key-down for discrete actions** — hold-to-repeat at the system
  key-repeat cadence (macOS 13+), as a `ShortcutDispatch` variant or an
  `ShortcutActionDefinition` flag. Genuinely missing behavior (hold-to-nudge).
- **Async-sequence event API** — a thin `for await` wrapper
  (`registry.actionEvents` / `events(for:)`) over the existing Combine
  publishers; keep Combine, add the async surface. Nice-to-have, lower priority.

Considered and skipped: `Shortcut#isTakenBySystem` convenience,
`storedNames`, `Shortcut#toSwiftUI`, and `Recorder` binding support — already
covered by the registry-centric design or a poor fit. Full analysis in git
history.

## Deferred to post-1.0 / v2

Decided limitations — documented and defensible for v1:

- **Late context registration** — runtime register/unregister, a `contextsChanged`
  publisher, and orphan-override semantics. Post-1.0; contexts are fixed at init.
- **Hierarchical mutex via a context tree** — v2; the flat
  `mutuallyExclusiveContexts` covers v1.
- **Configurable corruption-recovery policy** — post-1.0; v1 logs and resets to
  empty on load failure.
- **Migration-save-failure enforcement** — post-1.0; idempotent migrations make
  logged-and-continue acceptable.
- **Orphaned-override GC** — post-1.0; stale overrides for removed actions are
  inert (lookup ignores them).
- **Global-activator status publisher** — post-1.0; a live settings UI polls
  `CarbonGlobalActivator.status` for now.
- **Debug events for global shortcuts** — Carbon hotkeys fire through
  `CarbonGlobalActivator` straight to the context and never reach
  `RegistryEventRouter`, so they produce no debug events. Needs a second
  emission point in `ShortcutKitGlobal`.
- **`ScopePolicy` / Core scope-rule consolidation** — optional internal cleanup;
  both sides are internal and independently tested.
