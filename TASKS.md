# TASKS.md

## Purpose

This file is the forward roadmap for the current Downward codebase **after a full code review**.

The previous roadmap assumed stabilization was largely done. The review shows a narrower and more important truth: the app is close, but a few file-boundary and lifecycle issues still need to be closed before more feature work.

Status legend:

- `[x]` complete in the current codebase
- `[~]` worth refining soon
- `[ ]` planned backlog
- `[!]` high-risk surface that must stay regression-covered

---

## Protected behavior already in place

These are real strengths and should be preserved while fixing the remaining trust issues:

- [x] calm autosave with save-ack merge semantics
- [x] same-document revalidation that avoids self-conflict after the app’s own saves
- [x] active-file rename/delete coherence in the browser/editor flow
- [x] restore and reconnect flows with stale-session cleanup
- [x] workspace-relative recent-files UI
- [x] editor appearance preferences
- [x] strong smoke-test coverage for async session and navigation behavior

---

## Immediate release blockers

No new feature wave should outrank these items.

### Security-scoped workspace access

- [ ] Use security-scoped bookmark options correctly for bookmark creation and bookmark resolution
  - acceptance:
    - bookmark creation is explicitly security-scoped
    - bookmark resolution is explicitly security-scoped
    - restore/reconnect are validated on real devices with iCloud Drive and one provider-backed folder
- [!] Keep restore, reconnect, and invalid-bookmark recovery strongly regression-covered

### Canonical file identity

- [ ] Introduce one canonical workspace-relative identity for files and folders across:
  - snapshot nodes
  - recent files
  - restore session
  - rename/delete reconciliation
  - search result metadata
- [ ] Treat `displayName` as presentation-only data
- [ ] Stop rebuilding persisted relative paths from display names

### Editor load / observation lifecycle

- [ ] Cancel delayed document loads when the editor route disappears
- [ ] Prevent late document loads from reactivating a document the user already left
- [ ] Only keep live observation active while the matching editor is actually visible
- [ ] Ensure rename/disappear flows restart observation only for the current logical document

### Coordinated workspace mutations

- [ ] Move create / rename / delete onto the same coordinated file-access model used by document reads/writes
- [ ] Make rename/move semantics explicit for any live presenter / observer state
- [ ] Keep open-document mutation flows coherent without depending on uncoordinated filesystem side effects

---

## Next hardening wave

These should follow immediately after the blocker set.

### Refresh and concurrency correctness

- [ ] Add end-to-end generation protection for overlapping workspace refreshes
- [ ] Ensure stale refresh results cannot overwrite newer session state from:
  - manual refresh
  - pull-to-refresh
  - scene-activation refresh
- [!] Keep browser/editor coherence strongly regression-covered during overlapping refresh work

### Save durability and write semantics

- [ ] Decide and document the document-write durability model
  - direct coordinated write with explicit tradeoffs, or
  - temp-write-and-replace where safe
- [ ] Add failure-mode tests around save interruptions or mid-write failures where practical
- [ ] Keep the “newer in-memory edits survive old acknowledgements” contract intact

### Observation efficiency

- [ ] Reduce no-change churn from fallback live observation
  - gate revalidation when metadata is unchanged
  - add backoff or degrade-to-poll only when presenter notifications appear unreliable
- [ ] Keep same-document live refresh best-effort without turning it into constant provider churn

### Workspace snapshot resilience

- [ ] Make enumeration resilient to unreadable nested folders where possible
- [ ] Define an explicit policy for hidden/package/metadata-like folders
- [ ] Document practical workspace-scale expectations after profiling
- [ ] Keep empty real folders visible even when they contain no supported files

### Rename edge cases and cleanup

- [ ] Fix case-only rename handling for case-insensitive providers
- [ ] Remove or wire up dormant states and code paths:
  - `WorkspaceAccessState.restorable`
  - live `modifiedOnDisk` conflict policy or its removal
  - unused coordinator helpers

---

## Regression test expansion

These tests should be added before or alongside the hardening work above:

- [ ] delayed editor load followed by immediate navigation away
- [ ] overlapping workspace refreshes with delayed enumerator results
- [ ] recent-file pruning when display names differ from canonical path components
- [ ] case-only rename behavior
- [ ] unreadable nested folder during workspace snapshot creation
- [ ] observation fallback does not endlessly revalidate unchanged clean documents
- [ ] coordinated create/rename/delete behavior for active files
- [ ] real-device checklist for bookmark restore and provider-backed mutation flows

---

## Quality and maintainability

These are still worthwhile, but they now rank below the trust-hardening work.

### Tooling and diagnostics

- [~] Keep debug-only diagnostics around save / revalidate / restore / mutation transitions easy to inspect
- [ ] Add one short contributor note for testing provider-backed changes before merging persistence-sensitive work
- [ ] Add a lightweight release checklist for simulator plus real-device sanity passes

### Accessibility and UX polish

- [~] Continue small accessibility polish where it improves real use:
  - VoiceOver wording on file/folder rows
  - recovery-message clarity
  - Dynamic Type checks on edge-state screens
- [ ] Add a lightweight active-document info surface only after trust hardening lands

---

## Feature work that can wait

These are valid ideas, but they should not outrank the file-boundary fixes above.

### Browser and editor productivity

- [x] lightweight in-memory workspace search
- [x] workspace-relative recent-files sheet
- [ ] keyboard shortcuts for common iPad / hardware-keyboard actions
- [ ] lightweight document info surface
- [ ] minimal additional editor preferences
- [ ] evaluate folder rename/move support only if it becomes a real requirement

### Later optional expansions

- [ ] markdown preview
- [ ] syntax highlighting
- [ ] tabs or multi-document editing
- [ ] multi-window / multi-scene workflow improvements
- [ ] Git integration
- [ ] plugin architecture
- [ ] formatting toolbar / rich-text features
- [ ] broader import policy beyond UTF-8 plain text
- [ ] custom text engine
- [ ] app-owned mirrored storage model

---

## Working rule from here

Before implementing any new work, check:

1. does it preserve calm autosave behavior?
2. does it keep the workspace folder as source of truth?
3. does it keep file identity canonical across restore, recents, and mutations?
4. does it avoid resurrecting stale async state?
5. is there targeted regression coverage for the risky part?

If any answer is no, fix that first.
