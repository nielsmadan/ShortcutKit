# ShortcutKit Roadmap

Decided limitations — documented and defensible for v1, revisited post-1.0.

Speculative feature sketches and the API-review audit trail that produced today's
design both lived here and have been dropped; `git log -- docs/ROADMAP.md` and
`git log -- docs/api-review.md` recover them.

## Deferred to post-1.0 / v2

- **Command palette product** — a proposed `ShortcutKitCommands` target would expose searchable registered actions plus adopter-provided commands, with both an in-app sheet and a floating panel. The design has not been implemented or accepted into the package surface; revisit its module boundary, metadata needs, and presentation API against the current registry before building it.

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
