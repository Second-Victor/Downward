# PLANS.md

## Goal of the next stage

The hardening stage described in this document is now largely complete.
The next stage of Downward should build on that foundation rather than reopening the same trust/state passes.

The codebase is already beyond prototype stage.
The right plan now is:

1. preserve the hardened file-safety, restore, and cancellation boundaries,
2. keep scaling limits explicit before larger browser/search/editor work lands,
3. use the stronger base for richer product work without re-centralizing responsibility.

---

## Guiding principle

Treat the next roadmap as **expansion on top of hardened boundaries**.

Downward still edits real user files in a user-selected folder.
That means new feature work must preserve the recent hardening around workspace trust, snapshot application, cancellation, restore, and editor ownership.

---

## Phase 0 — Trust and state correctness

Status: completed foundation work.

### P0.1 Harden the workspace containment boundary

**Why first**

This is the only finding that directly threatens the app’s core trust model.
The app must not be able to follow redirected descendants outside the chosen workspace.

**Deliverables**

- define redirected-descendant policy,
- skip or explicitly reject symbolic links / other escape paths,
- enforce containment in enumeration, open/save, and file mutations,
- add tests for symlinked files and folders.

**Exit condition**

The app can clearly say: “Only files truly inside the chosen workspace are surfaced and mutated.”

### P0.2 Unify snapshot winner policy across refreshes and mutations

**Why now**

The app already solved refresh-vs-refresh.
It still needs one coherent rule for refresh-vs-mutation.
That is the next biggest source-of-truth issue.

**Deliverables**

- one winning workspace state application boundary,
- no older refresh can overwrite post-mutation browser state,
- browser/document/recent-file reconciliation always runs against the winning snapshot,
- UI does not allow accidental mutation/refresh interleaving without a defined policy.

**Exit condition**

All workspace state replacements are ordered and intentional.

### P0.3 Remove `Task.detached` from cancelable read-side I/O

**Why now**

The UI already avoids many stale-apply bugs.
The next problem is wasted background work and weak cancellation semantics.

**Deliverables**

- refresh/open/revalidate work inherits cancellation cleanly,
- generation guards remain, but cancellation now also stops unnecessary work sooner,
- tests prove cancellation behavior where practical.

**Exit condition**

Canceled loads/refreshes are cheap no-ops, not silently continuing background file work.

---

## Phase 1 — Ownership hardening

Status: completed foundation work.

### P1.1 Reduce coordinator pressure without rewriting the architecture

**Why now**

`AppCoordinator` is still the main policy sink.
If feature work continues before this pressure is reduced, every new behavior will keep piling into one file.

**Deliverables**

- extract smaller helpers/controllers around:
  - workspace state application,
  - document presentation/restore reconciliation,
  - maybe error routing,
- preserve today’s behavior and tests,
- make it easier to change one domain without touching all others.

**Exit condition**

`AppCoordinator` remains the top orchestrator, but not the implementation home for every policy rule.

### P1.2 Scope error ownership by surface

**Why now**

Global error slots will become harder to reason about as the app gains richer search/settings/editor flows.

**Deliverables**

- explicit launch/reconnect errors,
- workspace/browser alert channel,
- editor-local failure channel,
- fewer unrelated flows writing to the same slot.

**Exit condition**

Error lifetime is explainable without reading half the app.

### P1.3 Make fallback observation truly degraded mode

**Why now**

The current fallback behavior is acceptable for today, but it is not the right steady-state architecture.
Fixing it now will keep editor trust simpler before more editor features arrive.

**Deliverables**

- explicit trigger or policy for fallback mode,
- lighter ongoing polling burden,
- lightweight diagnostics around which observation mode is active.

**Exit condition**

File presenter callbacks are primary; fallback is obviously secondary.

### P1.4 Make new-workspace selection persistence transactional

**Why now**

Restore/reconnect behavior is too important to leave selection persistence half-ordered.

**Deliverables**

- successful first snapshot before bookmark becomes current persisted workspace,
- or rollback behavior on failed selection,
- tests covering failed-selection persistence.

**Exit condition**

Failed selections do not silently become tomorrow’s restore target.

---

## Phase 2 — Scalability groundwork

Status: early groundwork is complete; larger-scale follow-up remains future-facing.

Important framing:

- the current whole-snapshot workspace model is still the correct base for today’s product because it keeps refresh, restore, reconnect, and mutation reconciliation simple and trustworthy,
- Phase 2 is not about replacing that model early,
- it is about documenting and preparing for the point where very large trees or richer search would need a more scalable browser/search layer than “replace the accepted snapshot and rescan it.”

### P2.1 Stabilize workspace identity beyond absolute path strings

**Why**

Recent files currently depend on absolute workspace path.
That is too weak for bookmark-based restore/reconnect over time.

**Deliverables**

- more stable workspace identity for recent files and related persistence,
- clear migration behavior for existing stored items.

### P2.2 Separate search presentation from the tree row model

**Why**

The app currently reuses one row style for tree and search, and path disambiguation suffered.
The browser and search result surfaces now have different needs.

**Deliverables**

- browser row optimized for inline tree browsing,
- search row optimized for filename + path disambiguation,
- tests/previews that reflect the difference.

### P2.3 Move search off the hot render path

**Why**

Whole-tree synchronous search is fine today, but not a scalable base.

**Deliverables**

- cached/debounced search state in the view model,
- a documented threshold for when a proper index or other derived search structure becomes necessary,
- no regression in simple filename/path search.

### P2.4 Document the single-document model and its future escape hatch

**Why**

This project is still intentionally single-document.
That should remain explicit before anyone tries to bolt on multi-pane behavior.

**Deliverables**

- architecture docs clearly state the limit,
- any future multi-pane proposal starts with an explicit ownership redesign instead of incidental changes.

### P2.5 Document the whole-snapshot browser/search scaling boundary

**Why**

Whole-snapshot replacement is clean and appropriate for the current app.
It is also the place future contributors are most likely to accidentally overextend once they start thinking about larger workspaces, richer search, or more incremental browser behavior.

**Deliverables**

- docs explicitly state why the current snapshot model is the right tradeoff today,
- docs explicitly state which future features would require a more scalable browser/search model,
- no speculative fake index/diff architecture is introduced ahead of actual need.

---

## Phase 3 — Cleanup and contributor ergonomics

Status: baseline cleanup is complete; future work here should stay incremental.

### P3.1 Remove dead or half-migrated APIs

Targets include:

- unused lifecycle observer state,
- old browser helper APIs that no longer drive live UI,
- dead row/model helpers,
- preview-only leftovers that imply obsolete navigation patterns.

### P3.2 Align previews with live product behavior

Previews should reflect:

- inline tree browsing,
- current row metadata,
- search result disambiguation,
- actual compact vs regular navigation assumptions.

### P3.3 Add diagnostics where the app currently “fails quietly” by design

Especially around:

- partial enumeration skips,
- fallback observation mode,
- workspace reconnect causes.

---

## What should still wait for explicit design

The following should not become casual incremental work without an explicit design pass:

- multi-pane or multi-window editor experiments,
- content search or other indexed search behavior,
- very large-workspace browser work that assumes whole-snapshot replacement will scale indefinitely,
- optimistic/incremental snapshot UI work.

The current base is good enough to evolve, but these still need intentional design boundaries first.

---

## Recommended execution order from here

1. keep new feature work inside the current single-document and whole-snapshot boundaries
2. tighten preview/sample-data realism whenever UI surfaces change materially
3. design browser/search scaling intentionally before content search or very large-workspace work
4. revisit the coordinator/document ownership boundaries only when a concrete feature genuinely needs it

---

## Exit criteria for this roadmap stage

This roadmap stage is now materially complete.
The next meaningful exit criteria should be tied to whichever future feature boundary is chosen next, not to re-proving the hardening work that already landed.
