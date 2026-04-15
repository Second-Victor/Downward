# TASKS.md

## Purpose

This file is the forward-looking backlog for the current Downward codebase. Earlier implementation phases are complete and are retained here only as a compact status record.

Status legend:

- `[x]` complete in the current codebase
- `[~]` partially complete or worth refining
- `[ ]` not started / planned backlog
- `[!]` high-risk area that should keep strong regression coverage

---

## Phase status summary

### Phase 1 — Harden active-document save and external-change behavior

- [x] complete
- [x] active-document autosave stays calm during routine typing
- [x] save acknowledgements merge confirmed disk metadata without clobbering newer edits
- [x] same-document external refresh follows the same calm policy as foreground revalidation
- [x] regression tests cover self-save conflict prevention and external same-document refresh

### Phase 2 — Workspace mutation coherence while editor is open

- [x] complete
- [x] open-file rename updates document identity, route, and restore session
- [x] open-file delete clears stale editor state intentionally
- [x] nested mutation refreshes keep browser/editor state coherent

### Phase 3 — Restore and reconnect polish

- [x] complete
- [x] workspace bookmark restore is validated before reuse
- [x] last-open document restore is relative-path based and only happens when safe
- [x] stale restore state is cleared instead of reopening ghost editor UI

### Phase 4 — Browser/editor polish and operational cleanup

- [x] complete
- [x] browser selection and editor content stay coherent under refresh and async races
- [x] stale routes are trimmed intentionally after refresh or invalidation
- [x] lifecycle revalidation cannot overwrite a newer selection

### Phase 5 — Editor quality-of-life and shipping polish

- [x] complete
- [x] save-state chrome is failure-only during routine editing
- [x] the editor shows quiet identity/path context and an intentional empty-file state
- [x] UTF-8 and line-ending policy is explicit at the document boundary
- [x] focused tests cover empty-file, large-file, and route-scoped editor status behavior

### Phase 6 — Release readiness, cleanup, and documentation sync

- [x] complete
- [x] stale phase-era copy and dead stub-era error paths removed
- [x] root docs synced to the current architecture and persistence model
- [x] task list converted into a real forward backlog
- [x] critical regression coverage reviewed and tightened where high-value
- [x] restore now clears unreadable last-open document targets instead of retrying them forever

---

## Critical behavior coverage

These behaviors are currently covered well enough that future changes should treat them as protected surfaces:

- [x] bookmark persistence and invalid bookmark restore handling
- [x] session-store persistence for last open document identity
- [x] workspace enumeration, filtering, sorting, and descendant-folder retention
- [x] workspace create, rename, and delete behavior
- [x] open-document load/save/revalidate behavior
- [x] calm autosave, queued-save ordering, and save-ack merge semantics
- [x] external same-document refresh while editing
- [x] missing-file and conflict recovery flows
- [x] restore/reconnect behavior and stale-session cleanup
- [x] browser/editor coherence during refresh, switching, and async races

---

## Current known limitations

- [x] one workspace is active at a time
- [x] one live document session is active at a time
- [x] documents are treated as UTF-8 plain text
- [x] in-app mutations cover files, not folder rename/move
- [x] external same-document refresh is focused on the active editor session rather than general background sync

These are explicit limits, not accidental gaps.

---

## Backlog after Phase 6

### Persistence and diagnostics

- [x] Add lightweight debug-only diagnostics around save/revalidate transitions to make real-device file-provider issues easier to investigate
- [x] Add one short contributor checklist in `AGENTS.md` for changes touching save, restore, or mutation flows
- [x] Audit key user-facing recovery strings for consistency with the current app behavior

### Test coverage follow-up

- [ ] Add targeted UI tests for the highest-risk end-to-end flows:
  - first-launch workspace pick
  - open document and autosave
  - open-file rename/delete from the browser
  - reconnect after invalid workspace restore
- [ ] Keep expanding regression tests before any future save/conflict refactor

### Workspace and editor refinement

- [ ] Investigate folder rename/move support if it becomes a product requirement
- [ ] Consider broader workspace refresh diagnostics or profiling for larger real-world folders
- [x] Keep UTF-8-only plain-text support explicit unless a broader import policy is requested

### Deferred unless explicitly requested

- [ ] live markdown preview
- [ ] syntax highlighting
- [ ] custom text engine
- [ ] tabs or multi-document editing
- [ ] Git integration
- [ ] plugin architecture
- [ ] app-owned mirrored storage model
- [ ] formatting toolbar / rich text features

---

## Working rule from here

Before implementing new work, check:

1. does it preserve calm autosave behavior?
2. does it keep the workspace folder as source of truth?
3. does it keep browser, editor, and restore state coherent?
4. is there targeted regression coverage for the risky part?

If any answer is no, fix that first.
