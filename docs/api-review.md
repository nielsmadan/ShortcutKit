# ShortcutKit API Review — Outstanding Issues

High-level interface review (2026-05-21, `/review-interfaces`). No data-corruption
or invalid-state bugs found; architecture is sound. The systemic problem was an
**over-exposed public surface** — symbols one module needs from another were
marked `public` and leaked to every adopter.

**Resolution (cross-cutting pass, Step 1, 2026-06-04):** the premise was outdated.
Swift 5.9+'s **`package` access level** is the cross-module-internal mechanism the
review kept wishing for — all three modules are in one `Package.swift`, so symbols
UI/Global need from Core become `package` (visible across the package, invisible to
adopters), not `public`. This dissolves the systemic finding into a mechanical
access pass and lets the `__`-prefix hack be deleted. `@_spi` is unnecessary (it's
only needed across *separate* packages). Step 1 moved `attachedRegistry` (was
`public __attachedRegistry`), `globalBindings()`, `allContexts`, `scope(forContextID:)`,
and `contextIDsWithConflicts()` to `package`.

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

**Persistence — in-layer fixes (2026-05-28 cont.)**

- [x] **`FileStore` now takes prioritized URLs, namespace key, bootstrap flag.**
  `init(urls: [URL], format:, key: String?, createIfMissing: Bool)` plus a
  single-URL convenience. Adopters can search a fallback chain at the file
  level, embed ShortcutKit's data under `key` (dotted paths supported:
  `"config.shortcuts"`), and have the store touch the file at init so it's
  discoverable. Saves preserve sibling tables via read-modify-write; missing
  subtree on load returns empty state silently. Adopter-managed concurrent
  writes outside the library are explicitly the adopter's responsibility.

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

## Registry init (in-layer fixes, 2026-05-28)

- [x] **Duplicate context-ID precondition.** `ShortcutRegistry.init` now traps
  at construction if `contexts` contains two contexts with the same `id`. Catches
  the silent overwrite of `matchers` / `overrides` that would otherwise corrupt
  routing.
- [x] **Unknown-ID precondition on `mutuallyExclusiveContexts`.** Every ID in
  every mutex set must exist in `contexts`; otherwise traps. Catches typos and
  stale ID references that would silently no-op.

## Registry / activation (deferred)

- [ ] **Late context registration (`registry.register(_:)` / `unregister(_:)`).**
  Currently `contexts` is fixed at init. Adopters with plugin scenarios can't
  add or remove contexts at runtime. Feature spec — internal `attach(context:)`
  exists, would need register/unregister entry points, conflict re-analysis, table
  rebuild, persistence shape handling for plugin contexts (orphan-override
  semantics on uninstall), and a `contextsChanged` publisher so settings UI
  re-renders. Roughly 200–400 lines + design discussion. Pre-1.0 candidate if
  plugin scenarios matter.
- [ ] **Hierarchical mutex via context tree.** Today `mutuallyExclusiveContexts:
  [Set<String>]` is flat; encoding "onboarding XOR (editor AND document)"
  requires N×M pairwise sets. A `ShortcutContextTree.or/and/leaf` API would let
  the tree itself imply activation and mutex semantics. Substantial design
  change (cascading activation), worth dedicated brainstorming for v2.
- [ ] **`systemShortcutsProvider` → `@_spi(Testing)`.** Useful for tests, almost
  no real adopter need. Move behind the SPI strategy once that lands.
- [ ] **Silent corruption recovery on store load.** `load` failure logs and
  resets to empty `RawState`; adopter has no hook to surface a "your bindings
  were lost" message. Configurable `corruptionPolicy` option deferred for v1.
- [ ] **Silent migration-save failure.** Post-migration save errors are logged
  but init continues with in-memory state. Idempotent migrations are self-healing
  but the contract isn't enforced.

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
- [x] **`ActionFiredEvent.viaShortcut: Bool` → `source: ActionFiredEvent.Source`
  enum (2026-05-29).** Nested enum with cases `.shortcut`, `.programmatic`.
  Reads better at call sites (`event.source == .shortcut`) and extends if a
  third source emerges. HUD, example app, tests migrated; 191/191 pass.
- [ ] **`ActionFiredEvent` carries bare `contextID`/`actionID`** — could carry
  the new `ActionRef` value type for consistency with `ShortcutMigration.moveAction`.
- [ ] **`ActionFiredEvent` lacks `timestamp` / `Hashable` / kind+magnitude.**
  Possibly useful adds: `timestamp: Date` for adopters doing fire-rate analytics,
  `Hashable` for dedup. Continuous magnitude not carried by design (events are
  per-tick, not per-gesture). All optional polish.
- [ ] **`UserDefaultsStore.clear()` convenience.** Adopters currently call
  `defaults.removeObject(forKey:)` from outside. Small ergonomic gap.
- [ ] **Continuous `dispatch(_:)` semantics doc.** `ctx.dispatch(.someContinuousAction)`
  sends `.continuous(magnitude: 1.0)` ("fire once"); not realistic in production
  but supports tests and macro replay. Worth a short doc note on `dispatch(_:)`.
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

## Conflicts — value types (in-layer fixes, 2026-05-29)

- [x] **Dropped redundant `shortcut:` from `.systemShared` / `.menuCollision`.**
  Both cases carried a standalone `shortcut:` associated value that was always
  `==` the `Occurrence.shortcut` they also carried (verified at both construction
  sites). Now `.systemShared(action:)` and `.menuCollision(action:menuItemTitle:)`.
  Consumers read `action.shortcut`. Analyzer, registry, ConflictPopover, tests
  updated.
- [x] **`Conflict.Severity` is now `Comparable`** (`.warning < .error`). Adopters
  can `conflicts.map(\.severity).max()` to find the worst severity. Declaration
  order gives the ordering via Swift's synthesized `Comparable`.

**Conflicts — deferred:**

- [ ] **`Occurrence` could fold into `ActionRef` + `shortcut`.** It's
  effectively `ActionRef(contextID:actionID:)` plus a `Shortcut`. Cross-cutting
  with the other ActionRef-propagation items.
- [ ] **`SystemHotKey` has no `Shortcut`-based convenience init.** Custom
  `SystemShortcutsProvider` authors work in raw `keyCode`/`modifiers`; a
  `SystemHotKey(_ shortcut: Shortcut)` convenience would let them suppress a
  conflict by shortcut rather than raw keycode.
- [ ] **`.menuCollision.menuItemTitle: String`** is fine (AppKit titles are
  already resolved at runtime), but worth a doc note that it's the displayed
  string, not a localization key.

## Conflicts — analysis surface ✅ (2026-05-25)

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

## Headless types ✅ (2026-05-30)

- [x] **Collapsed `KeyBindingsTable` + `KeyBindingsLegend` into one `KeyBindings`.**
  The two types described the same context-grouped shape with forked vocabulary
  (`sections`/`Section`/`Row` vs `groups`/`Group`/`Entry`) and the legend was a
  strict projection of the table. Now one `KeyBindings { groups: [Group], Group {
  contextID, entries: [Entry] }, Entry {...full metadata...} }`. The legend is a
  derived view: `bindings(for:).boundOnly()`. Dropped the UI-flavored
  "Table"/"Row" vocabulary for neutral data names.
- [x] **`Entry`, `Group` are `Identifiable`** (`Entry.id = "ctx.action"`,
  `Group.id = contextID`) — removes the manual-`id:` footgun for adopters
  rendering these in `ForEach` (and the `actionID`-not-unique-across-contexts
  collision).
- [x] **`KeyBindings.Entry` carries `contextID` + `actionID`** (the old legend
  `Entry` had neither) — enables mapping a legend row back to its action, e.g.
  a clickable cheat-sheet or the proposed command launcher.
- [x] **`Entry.description` added** (was on the table row, now carried through
  uniformly).
- [x] **Registry surface:** `keyBindingsTable` → `keyBindings`; `legend()` →
  `activeBindings()`; `legend(for:)` → `bindings(for:)`. `KeyBindings.filter(query:)`
  (fuzzy) and `.boundOnly()` (drop unbound + empty groups, for legends) added.
  `KeyBindingsLegendView(legend:)` → `init(bindings:)`, applies `.boundOnly()`
  internally. Full cascade through UI, Global, tests, example; 191/191 pass.

**Headless — deferred:**

- [x] **Context display name added (2026-05-30).** `AnyShortcutContext` now has
  `displayName: LocalizedStringResource`; `ShortcutContext` takes an optional
  `displayName:` on both inits, falling back to a title-cased rendering of `id`
  (`"canvas.shared"` → `"Canvas / Shared"`) via a Core helper. `KeyBindings.Group`
  carries the resolved `displayName`; settings picker, section headers, and the
  legend all render it instead of title-casing the raw id in the UI layer (that
  duplicated helper was deleted). Closes the `AnyShortcutContext`-displayName and
  headless-`Group`-displayName items together.
- [ ] **`Entry.conflicts` double-counts across entries** — a duplicate conflict
  appears in both entries' arrays. Correct per-entry (badge), but aggregate
  counts need dedup. Doc note.
- [ ] **`KeyBindings`/`Entry`/`Group` are `Equatable` not `Hashable`**
  (`LocalizedStringResource` blocks it). Document.

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

## ShortcutKitUI — proper walk (2026-05-31)

- [x] **`ShortcutStyle` → `KeyBindingsStyle`, env value → init parameter.** The
  name overpromised (it only affects the bindings table + recorders; the legend
  has its own `LegendStyle` and the HUD ignores it). Renamed to parallel
  `LegendStyle` and scoped honestly. Converted from a `@Environment` value +
  `.shortcutStyle(_:)` modifier to an init parameter on `KeyBindingsView(registry:style:)`
  and `ScopedShortcutRecorder(...:style:)` — consistent with how `LegendStyle`
  is already passed to `KeyBindingsLegendView`, drops the env-key + modifier
  machinery. Deleted `ShortcutStyleEnvironment.swift`. Threaded through
  `ShortcutRowView` (internal). 190/190 tests pass.
- [ ] **`.dense` coverage is partial (documented).** Only the bindings table +
  recorders honor it; the legend and HUD render at fixed sizes. Documented on
  `KeyBindingsStyle`; extending dense rendering to the legend/HUD is deferred
  visual-design work.

## ShortcutKitUI — ShortcutBindingEditor + recorder demotion (2026-06-02)

- [x] **Added `ShortcutBindingEditor<Action>`** — public single-action,
  registry-bound binding editor (`init(_ action:in:style:showsDescription:)`).
  Renders the action's display name + optional description + recorder(s) +
  conflict feedback + reset, persisting through the attached registry.
  Composes the internal `ShortcutRowView`. Serves onboarding ("ask for the 5
  most important shortcuts") and any custom per-action UI without the adopter
  hand-plumbing raw `Shortcut?` bindings. 3 tests.
- [x] **`ScopedShortcutRecorder` demoted to `internal`.** It was a thin wrapper
  over ShortcutField's recorder — not worth headline public status. Now the
  inner cell composed by both `KeyBindingsView` and `ShortcutBindingEditor`.
  Public UI binding-editing surface is now two meaningful altitudes: the whole
  table (`KeyBindingsView`) and one action (`ShortcutBindingEditor`).
- [x] **`ScopePolicy` demoted to `internal`** (+ `Validation`/`RejectReason`).
  Only the internal recorder uses it now.

## ShortcutKitUI — context picker layout (2026-06-02)

- [x] **`ContextLayout` + `.picker` mode added to `KeyBindingsView` full mode.**
  `init(registry:style:searchEnabled:contextLayout:)`. `.stacked` (default) is
  the prior all-contexts-stacked behavior; `.picker` shows a context selector
  (segmented for ≤3 contexts, dropdown for more, with 🌐 badges + per-context
  conflict dots) and renders only the selected context's rows — solves endless
  scroll for shortcut-heavy apps. This also **resurrected `ContextPickerView`**,
  which was dead code (only its own tests referenced it; never wired into any
  view). Now an internal sub-view of `.picker` mode. Back-compat (default
  `.stacked`). 196/196 tests pass.
- [x] **`KeyBindingsView` stale doc fixed** — init signatures now include
  `style:`; `keyBindingsTable` reference corrected to `keyBindings`; added a
  steer toward `ShortcutBindingEditor` for single-action UI.

## ShortcutKitUI — legend (2026-06-02)

- [x] **Added registry-based `KeyBindingsLegendView(registry:style:contextIDs:)`.**
  Observes the registry and updates live as bindings change — reactivity parity
  with `KeyBindingsView` (which already takes the registry). The snapshot init
  `init(bindings:style:)` stays for fixed pre-filtered sets. Implemented via a
  private `LiveLegend` (`@ObservedObject`) dispatching to a shared `LegendBody`.
  Example app simplified to the registry init (drops manual recompute).
- [x] **`LegendStyle` doc leak fixed** — removed the internal "Phase 2 Task 17"
  references; documented that the legend shows each action's primary binding only.
- [decided] **Legend visibility (global toggle + per-panel dismiss) stays with
  the app.** Principle: the library owns content it *places* (the HUD, which it
  auto-suppresses via `hintsEnabled`); the app owns content *it* places (the
  legend's sidebar/sheet/window). The library shouldn't blank app-placed content
  via a global flag or reach into the app's hierarchy for an X button. Apps that
  want a unified "show hints" setting read `ShortcutPreferencesView.hintsEnabledStorageKey`
  and gate their own `KeyBindingsLegendView`. No new API.

## ShortcutKitUI — hint HUD (2026-06-03)

- [x] **Hint toast template localized.** Was `"Tip: \(name) is bound to \(shortcut)"`
  with only the action name resolved — the scaffold was hardcoded English. Now
  `String(localized: "Tip: \(name) is bound to \(shortcut)")` so translators get
  the whole "Tip: %@ is bound to %@" format. Consistent with the displayName /
  description localization.
- [x] **`ShortcutHintHUD` `ViewModifier` demoted to `internal`.** Adopters apply
  it via `.shortcutHintHUD(registry:policy:)`; nobody constructs the type. Only
  the modifier function stays public (standard SwiftUI pattern).
- [x] **HUD doc literals fixed** — reference `ShortcutPreferencesView.hintsEnabledStorageKey`
  instead of the raw `@AppStorage("shortcutkit.hintsEnabled")` string.
- [ ] **[pre-v1] HUD placement + duration options.** Toast is hardcoded
  `.topTrailing` / 2s. Add `alignment:` (and likely `duration:`) to
  `.shortcutHintHUD(...)`. Ship before v1.
- [ ] **[pre-v1] HUD custom appearance.** `HintToast` is a fixed private
  `.thinMaterial` style; let adopters restyle (custom-content closure or style).
  Ship before v1.

## ShortcutKitUI — preferences pane (2026-06-03)

- [x] **`ShortcutPreferencesView` forwards `searchEnabled` + `contextLayout`** to
  the embedded `KeyBindingsView`. The canned preferences pane can now use the
  `.picker` layout for many-context apps instead of being stuck on `.stacked`.
  Doc literal fixed to reference the storage-key constant.
- [ ] **[pre-v1 / cross-cutting] Preferences persistence split-brain.**
  `ShortcutPreferencesView`'s `hintsEnabled` + `denseStyle` toggles (and the HUD's
  read of `hintsEnabled`) go through `@AppStorage` → `UserDefaults.standard`,
  bypassing the pluggable `ShortcutBindingsStore`. Adopters using `FileStore`
  silently leave these in UserDefaults. Fix: route library UI prefs through a
  `preferences` field on `RawState` (or a sibling persisted state) so they share
  the adopter's store. This is the same item flagged in the persistence layer at
  the start of the review — belongs to the cross-cutting design pass.
- [ ] **[deferred] Library UI strings resolve against the main bundle.**
  SwiftUI string-literal labels (`ShortcutPreferencesView` toggle/section titles)
  and the HUD toast are localizable, but `LocalizedStringKey` / `String(localized:)`
  resolve against `Bundle.main`, so ShortcutKit can't ship its own translations —
  adopters must add the keys to their catalog. If the library wants to ship
  localizations, the UI strings need explicit `bundle:` lookups. Localization-
  packaging decision; affects the HUD + preferences labels.
- [ ] **[noted] `ShortcutPreferencesView` is fixed composition.** No adopter-row
  injection into "General"; adopters wanting custom sections compose
  `KeyBindingsView` directly. Intentional — this is the canned option.

## ShortcutKitUI — deferred

- [ ] **`ScopePolicy` duplicates Core's scope-validation rule** (now internal,
  lower urgency). `ScopePolicy.validate` re-implements
  `ConflictAnalyzer.detectUnsupportedInScope`, and `ScopePolicy.RejectReason` is
  byte-identical to `Conflict.UnsupportedReason`. Consolidate the rule into Core
  (`ContextScope.unsupportedReason(for:)`) so the analyzer + recorder share one
  source; then `ScopePolicy` can collapse to a thin scope alias or vanish.
- [x] **`ScopedShortcutRecorder.discreteWidth`/`continuousWidth` tuples** — now
  internal-only (recorder is internal), read cross-file by `KeyBindingsView`'s
  dense column header. Minor organization nit; not adopter surface. Left as-is.
- [ ] **`ShortcutBindingEditor` / `KeyBindingsView` inline silently no-op on an
  unattached context** (`__attachedRegistry` weak ref → throwaway empty registry
  → renders nothing). Should trap or warn. Same footgun both share.

## ShortcutKitGlobal — walked (2026-06-03)

- [x] **`globalBindings()` returns a named `GlobalBinding` struct** (was an
  anonymous `[(id: BindingID, shortcut: Shortcut)]` tuple). `GlobalBinding:
  Sendable, Hashable { id, shortcut }` in Core. Callers unchanged (`.id`/`.shortcut`
  access is identical); `CarbonGlobalActivator` updated.
- [x] **`GlobalBindingStatus.failed(reason:)` is now a closed `FailureReason`
  enum** (`registrationRejected` / `reregistrationFailed`), was a free-form
  `String`. The `Equatable` conformance is now meaningful — adopters can branch
  on the cause. `CarbonGlobalActivator`'s two failure sites updated.
- [x] **Example `ContextWiring` stale `bindingsPerAction: .two` removed** — the
  example app (not in `swift build`/`swift test`) hadn't been updated when
  `bindingsPerAction` was deleted; it wouldn't have compiled. Swept the rest of
  the example for other renamed/removed symbols — clean.

### ShortcutKitGlobal — deferred to the cross-cutting pass

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
