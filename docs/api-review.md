# ShortcutKit API Review — Outstanding Issues

High-level interface review (2026-05-21, `/review-interfaces`). No data-corruption
or invalid-state bugs found; architecture is sound. The systemic problem is an
**over-exposed public surface** — the package has no cross-module-internal
mechanism, so symbols one module needs from another were marked `public` and leak
to every adopter.

**Process note:** this is the running punch-list for the bottom-up API walkthrough.
As the review reaches each layer below, fix that layer's issues before moving up.
Tick items as resolved.

---

## Proposed: command launcher / palette (Phase 3.5 candidate)

A new SwiftUI component in the `ShortcutKitUI` module — a Notion / Superhuman
/ Linear-style modal palette with a search field and an enter-to-execute list
of every registered action. The conceptual fit is natural: actions are already
the right primitive (one declared, name'd, dispatchable thing per adopter
case), so a launcher is really just "enumerate every action across every
`includeInSettings` context, fuzzy-match on display name, execute on enter."

**Reuses what already exists:**
- `FuzzyFilter` (currently `internal` in Core — promote to `public`, or
  `@_spi(ShortcutKitUI) public`). Same scorer used by the settings search field.
- `registry.keyBindingsTable.sections.rows` for enumeration — every action is
  already in there with display name, context id, and effective shortcut.
- `ActionFiredEvent` and the `actionFired` publisher — the launcher's "execute"
  path emits the same event a shortcut would.

**Needs new public surface:**
- A `CommandLauncherView` (or `ShortcutCommandPalette`) — the palette view.
  Probably both a sheet-style and a window-style presentation (popular apps
  ship both).
- A trigger pattern — adopters usually bind ⌘K / ⌘⇧P themselves and present
  the view. Could ship as a `.commandLauncher(isPresented:)` view modifier.
- An adopter-level `registry.dispatch(contextID:actionID:)` — already on the
  deferred punch list ("no global dispatch convenience"). The launcher needs
  this to execute the selected row.
- Optionally an action-source extension point so adopters can inject
  *non-shortcut* commands into the same palette ("Open recent file…",
  "Switch workspace…"). Without this, the launcher only surfaces things that
  are also keystroke-bindable, which is a meaningful limit.

**Cross-cuts with existing punch-list items:**
- The `@_spi` strategy (FuzzyFilter promotion fits cleanly here).
- The deferred `registry.dispatch(contextID:actionID:)` convenience.
- `LocalizedStringResource` for `displayName` — the palette renders display
  strings prominently and language-switch reactivity will matter.
- The over-exposed-sub-views finding — the launcher will have sub-views
  (search field, row, result list) that should all be `internal`.

**Recommendation: spin into a real Phase 3.5 / Phase 4.** This is a
substantial UI addition (not a cleanup), it has its own design decisions
(action-source extensibility, presentation mode, keyboard navigation,
non-shortcut commands), and it overlaps enough with the cross-cutting design
pass that doing both at once is sensible. Add as a peer phase rather than a
punch-list bullet — tracked here so it isn't lost.

---

## Persistence layer ✅ (2026-05-23)

- [x] **`WrapSingleBindingsMigration` is `public` but a no-op breadcrumb.** Demoted
  to `internal`. Tests use `@testable import` so they still reach it.
- [x] **`RawState` ergonomic accessors.** Added `subscript(context:action:)`,
  `removeContext(_:)`, `contextIDs`, `actionIDs(in:)` for `.custom` migrations and
  custom-store authors. Empty-array / nil writes auto-prune the surrounding
  context entry so `overrides` stays canonical.
- [x] **`ShortcutMigration` consistency.** Introduced `public struct ActionRef`
  (`contextID`, `actionID`) and reshaped `.moveAction(from: ActionRef, to: ActionRef)`
  to replace the labeled-tuple associated values. `renameAction`/`renameContext`
  keep flat strings (their `from`/`to` labels are unambiguous on their own).
- [x] **`FileStore.init(url:format:)`** now defaults `format: .toml` (the headline
  human-editable case).
- [x] **CLAUDE.md doc drift** — corrected `migrationsApplied: N` line to reflect
  the actually-shipped design (idempotent content-detecting migrations, no counter).

**Deferred suggestions** (still open, considered intentional for v1):
- `ShortcutBindingsStore` is `@MainActor` — forecloses async stores. Acceptable
  for a kB-sized overrides blob.
- No live-reload on `FileStore` despite "human-editable" framing.
- No `removeContext` migration case (use `.custom` + `removeContext(_:)` accessor).

**Open (raised during persistence walkthrough — fix when revisiting this layer):**

- [ ] **Library-owned UI preferences are persisted out-of-band.** The hint toggle
  (`shortcutkit.hintsEnabled`) and the dense-style toggle
  (`shortcutkit.style.dense`) are written by SwiftUI views via `@AppStorage`
  directly to `UserDefaults.standard`, bypassing the pluggable
  `ShortcutBindingsStore`. Adopters who pick `FileStore` to get a portable
  dotfile silently leave these settings behind in UserDefaults. With more such
  toggles likely coming, fix with a small `preferences` field on `RawState` (or a
  sibling `PersistedState` wrapper) that goes through the same store; UI
  components read/write through the registry rather than `@AppStorage`.
- [ ] **No `registry.reload()`.** The store is one-shot — there's no public way
  to ask the registry to re-read the store and pick up out-of-band changes
  (hand-edited file, sync, restore). The internal `GlobalBindingDiff` machinery
  already does the right kind of incremental apply; expose a `reload()` that
  calls `store.load()` and routes through the same notify-and-rebuild path as
  `setShortcuts`/`removeShortcut`.
- [ ] **`FileStore` owns the whole file** — adopters cannot share it with their
  own settings. Two reasonable fixes: (a) namespace the library's data under a
  configurable top-level key (default `"shortcuts"`) and do read-modify-write so
  sibling tables survive saves; or (b) promote `TOMLCoding` (and possibly
  `JSONCoding`) to `public` so adopters can compose their own store on top. (a)
  is the user-friendly answer; (b) is the v1 escape hatch.
- [ ] **No outbound change notification.** Adopters wanting to mirror to iCloud,
  git-commit on change, or otherwise observe persistence have to wrap their own
  `ShortcutBindingsStore`. Consider a `registry.persistedStateChanges`
  publisher, or a documented `ShortcutBindingsStore`-decorator pattern.
- [ ] **No first-class import / export.** Email-a-shortcut-set / import-a-file
  flows are achievable via direct `FileStore.save`/`load` against a chosen URL,
  but every adopter reinvents the menu pair. A small `ShortcutPreferencesView`
  Import…/Export… affordance + a documented pattern would cover most apps.
- [ ] **No diagnostics helper.** No `RawState.debugDescription` producing a
  TOML-style dump for bug reports; adopters end up `print(state.overrides)`-ing
  the raw nested dictionary. Cheap to add.

## Core — action / context (in-layer fixes, 2026-05-23)

- [x] **`ShortcutAction` protocol's `Hashable` requirement is redundant.** Dropped
  — enums with `String` raw values get `Hashable` synthesized automatically.
- [x] **`shortcutChanges(for:)` was first-binding-only with no plural sibling.**
  Added `shortcutsChanges(for:) -> AnyPublisher<[Shortcut], Never>` and
  refactored the singular publisher to derive from it via `.map(\.first)` —
  single subject per action, one source of truth.
- [x] **`displayString(for:)` was first-only.** Added
  `displayStrings(for: Action) -> [String]` plural sibling.

## Core — action / context (in-layer fixes, 2026-05-26 cont.)

- [x] **`ContextScope` now `Hashable`.** Was `Sendable` only — `ctx.scope == .global`
  worked via Swift's implicit equality synthesis for plain-case enums, but
  `Set<ContextScope>` / dictionary-key usage failed. One-character fix.
- [x] **`ShortcutContext.dispatch(_:)` matches the action's declared kind.**
  Was always sending `.discrete` to the closure even for continuous actions —
  closure with `switch kind { case .continuous(...): }` would silently never
  fire for adopter-driven dispatch. Fixed by dispatching with `.discrete` for
  discrete actions and `.continuous(magnitude: 1.0)` for continuous ones
  ("fire once programmatically" semantics). Added a regression test;
  `ShortcutDispatch.discrete` doc no longer claims adopter-driven dispatch always
  uses it.
- [x] **Mixed-kind defaults trap at definition time.** `ShortcutActionDefinition.init(_:defaults:)`
  now `precondition`s that all `defaults` share the same `Shortcut.Kind`. Adopters who
  mix `Shortcut("cmd+s")` with a continuous default see a clear failure during development.
- [x] **`displayName` localizable + `description` added.** `displayName` is now
  `LocalizedStringResource` (still adopts string literals through
  `ExpressibleByStringLiteral` — adopters who don't localize change nothing).
  New optional `description: LocalizedStringResource?` for help text/tooltips.
  Cascade: `KeyBindingsTable.Row` and `KeyBindingsLegend.Entry` now hold
  `LocalizedStringResource`; their `Hashable` conformances downgraded to
  `Equatable` since `LocalizedStringResource` is `Equatable` but not `Hashable`
  (no real callers needed `Hashable`). Menu helpers + HUD + search-filter sites
  resolve via `String(localized:)`.

## Core — action / context (deferred)

- [x] **Singular / plural API redundancy removed (2026-05-26).** Deleted
  `ShortcutContext.shortcut(for:)`, `displayString(for:)`,
  `shortcutChanges(for:)`, and `KeyBindingsTable.Row.effectiveShortcut`.
  Callers use `.shortcuts(for:).first` / `.displayStrings(for:).first` /
  `.shortcutsChanges(for:).map(\.first)` / `.effectiveShortcuts.first`. The
  plural API is the canonical Phase 1.5 shape; singular convenience kept for
  back-compat from Phase 1 was clutter. 181/181 tests pass.
- [ ] **`ShortcutContext.includeInSettings` is a non-`@Published` `var`.**
  Mutating it at runtime doesn't refresh `KeyBindingsView`'s picker. Either
  doc-flag this clearly or promote to `@Published`.
- [ ] **`ShortcutContext.scope` `public let` immutability undocumented.** Add a
  doc note (and same for `id`).
- [x] **Activation-bound handler refactor (2026-05-28).** The
  "closure-at-construction" model was replaced with handler-binds-at-activation:
  `ShortcutContext("id")` for local contexts (no closure), with the dispatch
  closure supplied at `.activeShortcutContext(ctx, dispatch: handler)`.
  `ShortcutContext(global: "id") { ... }` keeps the construction-time closure
  for `.global` contexts (required, since the OS fires them whether or not a
  view is mounted). Internal `__setActiveHandler` / `__clearActiveHandler`
  test seams added for tests that drive matcher-routing without a SwiftUI host.
  Dispatch routing falls back: `activeHandler` (local) → `globalDispatchClosure`
  (global) → silent no-op. Example app migrated: `AppContextModel`,
  `SidebarContextModel`, `InspectorContextModel`, `WizardContextModel`,
  `CanvasModeContextModel` (8 sub-contexts), `GlobalContextModel`. Eliminated
  the `ModelHolder` weak-back-reference workaround that the closure-at-init
  pattern needed. 181/181 tests pass; example app updated.
- [ ] **`ActionFiredEvent` carries bare `contextID`/`actionID`** — could carry
  the new `ActionRef` value type for consistency with `ShortcutMigration.moveAction`.
- [ ] **No global `registry.dispatch(contextID:actionID:)` / `registry.notify(...)`
  for adopters.** Today the only registry-level dispatch hook is the
  `@_spi`-candidate `fireGlobalAction`. A documented adopter-facing pair would
  cover the "I'm far from my context but have its ID" case without the
  ambiguity of a global typed dispatch.
- [ ] **`dispatch(_:)` vs `notify(_:)` purpose disparity not telegraphed by
  names.** Documentation pass, possibly rename `notify` to something more
  explicit like `recordFired(_:)`.
- [ ] **Orphaned-override garbage collection.** Persisted overrides for actions
  that no longer exist in the adopter's enum linger indefinitely. Optional
  load-time pruning behind a registry init flag, with a logged warning.

## Core — registry / context / actions (in-layer fixes, 2026-05-25)

- [x] **`bindingsPerAction` removed.** The `BindingsPerAction` enum, its registry
  property, init param, and the UI `canAddMore` test seam were stored but
  unenforced — no production code path capped binding counts, the dense renderer
  hardcoded 2 slots independently, and `canAddMore` only gated a test-only
  `appendEmptyBinding`. Deleted the enum + registry knob + UI plumbing; tests
  updated. Data model remains `[Shortcut]` (unlimited at the persistence layer).
- [x] **`reset` ↔ `resetAction` body divergence fixed.** `reset(contextID:actionID:)`
  now delegates to `resetAction(contextID:actionID:)` (was routing through
  `setOverride(...nil)`). Single source of truth for the "clear one override"
  semantics, with the desirable early-return-on-no-op behavior preserved.
  `setOverride(...nil)`'s no-early-return path remains a separate divergence and
  is covered by the deferred "override-mutation consolidation" item below.

## Core — registry / context / actions (other deferred)

- [ ] **`ShortcutRegistry` override-mutation API is a misuse magnet (High).**
  5+ overlapping public methods for "change a binding": `setOverride` (singular —
  silently truncates a multi-binding action), `setShortcuts(_:for:in:)`,
  `setShortcuts(_:contextID:actionID:)`, `reset`, `resetAction` (a *divergent copy*
  of `reset` despite its doc claiming it's an alias), `removeShortcut`,
  `clearAllOverrides`, `resetAll`. Three verbs for "clear", two for "set",
  inconsistent singular/plural. Consolidate: pick one vocabulary; demote the
  string-keyed UI-only variants to `@_spi`/`internal`; make `resetAction` call
  `reset` so the bodies can't diverge; drop singular `setOverride` or document it
  as deliberately single-binding. (`Registry/ShortcutRegistry+Overrides.swift`)
- [ ] **Verb inconsistency for "revert overrides":** `ShortcutContext.resetAllToDefaults()`
  vs `ShortcutRegistry.resetAll()` vs `clearAllOverrides(contextID:)` — three names,
  one concept. Align on one.
- [ ] **`ShortcutContext.__attachedRegistry` is `public` (the only real `__` leak).**
  A `__`-prefixed hook in a `public extension ShortcutContext` block, so members
  default to `public`. UI module's inline mode uses it. Change to
  `@_spi(ShortcutKitUI) public` — this is also the canonical first item for the
  unified SPI policy queued at the top of this doc.
  (`Context/ShortcutContext.swift:227-237`)
- [x] **"Accidentally-public test seams" claim corrected (2026-05-25).**
  `ShortcutRegistry.__flushPendingSave()`, `__activeContextIDs`, `__router` are
  declared at default (internal) access inside `public final class ShortcutRegistry`,
  so they're already internal — not public, despite the punch list's earlier
  claim. `RegistryEventRouter` and `ContinuousCoalescer` are themselves internal,
  so their `__` seams don't escape either. No action required for those symbols.
- [ ] **`ActionFiredEvent.viaShortcut: Bool`** — readability: a
  `enum Trigger { case shortcut, programmatic }` reads better and extends if a
  third source appears. Low priority.

## Conflicts ✅ (2026-05-25)

- [x] **`SystemHotKey` manual `Hashable`** — punch-list claim was wrong:
  `NSEvent.ModifierFlags` conforms to `OptionSet` + `Equatable` but **not**
  `Hashable`, so synthesis can't derive it. The hand-written `hash(into:)`
  combining `modifiers.rawValue` is required. Kept the implementation; added a
  one-line doc noting *why* the manual conformance exists so future readers
  don't make the same mistake.
- [x] **`Conflict.severity` doc drift** — false positive. The current comment
  *does* cover the within-vs-cross-context distinction for both `duplicate` and
  `unreachablePrefix` accurately. Punch-list entry was stale (likely written
  against an older revision). No change needed.

## Menu helpers ✅ (2026-05-25)

- [x] **`public typealias ShortcutKit = ShortcutKitHelpers` deleted.** The
  alias existed solely so one test could write `ShortcutKit.resolveKeyboard...`.
  Test rewritten to call `ShortcutKitHelpers.resolveKeyboardEquivalent(...)`
  directly via `@testable import ShortcutKit`.
- [x] **`ShortcutKitHelpers` demoted to `internal`.** Verified there are no
  adopter call sites: production code uses the internal 3-arg sibling
  `resolveKeyboardEquivalent(for:in:given:)`, the redundant public 2-arg
  overload was a pure delegate (the 3-arg already defaults `given: nil`) — both
  the overload and the public access removed. Net: the whole "menu helpers"
  public surface goes from 1 namespace + alias + 2 overloads → 0 public
  symbols. The `.shortcut(_:in:)` view modifier remains the only adopter-facing
  API in this layer.

## ShortcutKitUI — in-layer fixes (2026-05-26)

- [x] **Over-exposed sub-views demoted (Critical/High).** `ShortcutRowView`,
  `ContextPickerView`, `ConflictStripeView`, `ConflictPopover`, `SearchField`
  (struct decls, init params, `let` properties, `body`, and the static helpers
  `ConflictStripeView.color(for:)` / `SearchField.filter(_:query:)`) demoted to
  `internal`. Confirmed no adopter usage by grepping the example app and
  Sources; only `KeyBindingsView` (their composition parent) and tests reference
  them, and tests already use `@testable import`. 26/26 UI tests pass.
- [x] **`searchEnabled` default asymmetry kept, doc tightened.** The differing
  defaults (`registry`-init: `true`; `context`-init: `false`) mirror real
  adopter usage patterns and were already documented at the type level — but
  the asymmetry was discoverable only by reading the type-level doc. Added an
  explicit paragraph on each `init` explaining its default and why it differs
  from the other initializer. No API break.
- [x] **`@AppStorage` literal drift fixed.** `ShortcutPreferencesView` now
  references `Self.hintsEnabledStorageKey` / `Self.denseStyleStorageKey` instead
  of duplicating the strings. `ShortcutHintHUD` now references
  `ShortcutPreferencesView.hintsEnabledStorageKey` instead of the literal. The
  example app was already using the constants; now the library's own
  consumption is too.

## ShortcutKitUI — deferred

- [ ] **`ScopedShortcutRecorder.discreteWidth`/`continuousWidth`** are bare
  `(native:dense:)` tuples read cross-file; `continuousWidth` may be unused.
  Consider a small struct or fold the width logic in. Low priority.
- [ ] **`ScopePolicy` mirrors Core's `ContextScope`** — defensible (UI module wants
  its own type + `validate`), but confirm the duplication earns its keep.

## ShortcutKitGlobal

- [ ] **`fireGlobalAction(contextID: String, actionID: String)` (High)** — a
  cross-module Core↔Global seam exposed to *all* adopters, with two adjacent
  `String` params (transposition compiles, silently no-ops). Collapse the two
  strings into the `BindingID` the only caller already holds:
  `fireGlobalAction(_ id: BindingID)`. Mark `@_spi(GlobalActivator) public` so it
  leaves ordinary adopters' autocomplete. Same `@_spi` for `globalBindings()`.
  (`Registry/ShortcutRegistry+Global.swift`)
- [ ] **`GlobalBindingStatus.failed(reason: String)` is stringly-typed (Medium)** —
  defeats the `Equatable` conformance that exists so adopters can branch on status.
  Replace with a closed `FailureReason` enum (`registrationRejected`,
  `reregistrationFailed`). (`Activation/GlobalActivator.swift`)
- [ ] **`globalBindings()` returns anonymous `[(id: BindingID, shortcut: Shortcut)]`**
  — introduce a named `GlobalBinding: Sendable, Hashable` struct.
- [ ] **`fireGlobalAction` "fire" naming** — Core's verb for "run an action" is
  *dispatch* (`dispatch`, `dispatchFromMatcher`); "fire" is the past-tense event
  noun (`actionFired`). If the method survives as a seam, rename to
  `dispatchGlobalAction`.
- [ ] **`CarbonGlobalActivator.status` is pull-only** — mutates async from three
  sources; a live settings UI must poll. Consider exposing a publisher. Defensible
  for v1; flag as a known limitation.
