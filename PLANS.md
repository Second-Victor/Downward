# PLANS.md

## Product direction

Downward should keep moving toward this shape:

- one user-selected workspace folder
- one calm, trustworthy plain-text editor
- one fast inline file tree for browsing
- minimal ceremony for create / rename / delete / reopen
- clear recovery when the file boundary becomes unreliable

The next release should be a **hardening release**, not a feature-sprint release.

The current codebase is already good enough that the limiting factor is no longer “missing MVP features.”
It is now **robustness under change**.

---

## Release goal

### Goal: make the app safe to extend

This release should make future work cheaper and lower-risk by tightening four boundaries:

1. **navigation ownership**
2. **editor host ownership**
3. **refresh / observation ownership**
4. **workspace enumeration and write-policy ownership**

If these are tightened now, later features like:

- better search and quick open
- richer recent files UX
- find in document
- markdown preview
- document tabs / multiwindow ideas
- folder creation and richer file operations
- editor polish and theme work

will be much easier to build without reopening trust bugs.

---

## Release themes

## Theme 1 — One navigation model per layout mode

### Outcome

The app should have explicit, predictable navigation state.

### What “done” looks like

- compact mode owns a real stack path
- regular mode owns a real detail selection model
- rotating between size classes does not resurrect stale routes
- old folder-route assumptions are removed from live app code

### Why this matters

The browser has already changed product direction from “folder route drill-down” to “inline tree.”
The navigation model needs to catch up.

---

## Theme 2 — The editor host becomes an owned boundary, not a tactical workaround

### Outcome

Editor layout and future editor polish sit on a stable integration layer.

### What “done” looks like

- text inset and scroll-indicator behavior are deterministic
- editor bridging code is isolated and documented
- document switching, focus changes, and iPad resizing do not break layout
- future editor work has one clear place to plug into

### Why this matters

The app is now close enough to “real editor” territory that TextEditor integration details are no longer incidental UI tweaks.
They are part of the core product experience.

---

## Theme 3 — Refresh and observation become calm and authoritative

### Outcome

The newest workspace snapshot always wins, and the editor stops doing unnecessary background churn.

### What “done” looks like

- stale refresh results cannot overwrite newer state
- observation fallback behaves like degraded mode, not a permanent timer
- file-presenter and fallback behavior are cheap when nothing changes
- document reconciliation stays quiet and trustworthy

### Why this matters

The app’s trust model depends on “what is on disk right now?” always meaning the same thing everywhere.

---

## Theme 4 — File-boundary policy becomes explicit

### Outcome

The repo clearly states what it does with unreadable descendants, provider-backed saves, and write durability tradeoffs.

### What “done” looks like

- enumeration policy is documented and tested
- partial snapshots are supported when appropriate
- write strategy is explicitly chosen and documented
- on-device QA expectations are written down

### Why this matters

Future features are much easier to add once the file-boundary policy stops being implicit.

---

## Not the focus of this release

These can wait until after the hardening pass unless they are tiny cleanups:

- markdown preview
- folder creation
- undo/redo expansion
- richer settings sections
- extra toolbar polish
- search ranking improvements beyond current filename/path matching
- large UI redesigns

---

## Success criteria

This release is successful if all of the following are true:

1. compact/regular navigation transitions are deterministic
2. editor inset behavior is stable on iPhone and iPad
3. overlapping refreshes cannot reapply stale snapshots
4. clean editors do not constantly revalidate on a fixed timer forever
5. unreadable nested content no longer unnecessarily kills the whole workspace
6. the write-durability decision is documented and tested as far as practical
7. docs and tests match the current inline-tree product model

---

## Suggested release order

### Phase 1 — Navigation hardening

- separate compact path state from regular detail selection
- normalize size-class transitions
- remove or quarantine legacy folder-route behavior
- update smoke tests

### Phase 2 — Editor-host hardening

- isolate the editor inset bridge
- remove fragile ad hoc lifecycle behavior
- add focused previews / smoke coverage

### Phase 3 — Refresh and observation hardening

- close stale-refresh overwrite hole
- reduce fallback revalidation churn
- add overlapping-refresh tests and no-change observation tests

### Phase 4 — File-boundary hardening

- define partial enumeration policy
- document write durability policy
- add provider-focused QA checklist

### Phase 5 — Cleanup and feature-readiness

- remove dead route/state leftovers
- simplify browser-row APIs
- tighten docs so future prompts and agent work start from the current truth

---

## Future-feature readiness gates

Before starting another substantial feature, the codebase should be able to answer “yes” to all of these:

- can I describe regular iPad navigation without mentioning compact stack internals?
- can I describe editor inset behavior without saying “there’s a workaround in the screen file?”
- can two overlapping refreshes produce only one winner?
- can an unchanged visible document stay open without repeated background churn?
- can one unreadable child folder avoid taking down the whole workspace?
- is the file-write durability decision documented in one obvious place?

If any answer is no, keep hardening first.
