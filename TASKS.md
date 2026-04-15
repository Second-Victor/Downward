# TASKS.md

## Purpose

This file is the forward roadmap for the current Downward codebase. The stabilization and release-readiness phases are complete; what remains should be future-facing, realistic, and aligned with the app's existing file-based editor model.

Status legend:

- `[x]` complete in the current codebase
- `[~]` worth refining soon
- `[ ]` planned backlog
- `[!]` high-risk surface that should keep strong regression coverage

---

## Completed foundation

These are already in place and should be treated as protected behavior, not as open feature work:

- [x] calm autosave with save-ack merge semantics
- [x] same-document live refresh with calm revalidation policy
- [x] open-file rename/delete coherence while the editor is visible
- [x] workspace restore, reconnect, and stale-session cleanup
- [x] browser/editor coherence under async races and refreshes
- [x] empty-folder support in the workspace browser
- [x] release-readiness polish for disclosure UI, supported-file copy, and real-device QA guidance
- [x] persisted editor font family and size preferences

---

## Protected surfaces

Future changes should keep these areas strongly regression-covered:

- [!] bookmark persistence and invalid-bookmark recovery
- [!] session-store restore for the last open document
- [!] workspace enumeration, filtering, sorting, and empty-folder visibility
- [!] create / rename / delete behavior inside the workspace
- [!] active-document open / save / reload / revalidate behavior
- [!] autosave ordering and save-ack merge semantics
- [!] same-document external refresh while editing
- [!] missing-file and conflict recovery flows
- [!] restore / reconnect behavior and stale-session cleanup
- [!] browser / editor coherence during refresh, switching, and async races

---

## Future feature themes

The roadmap from here should stay grouped into three layers:

1. **Near-term polish**
   Small, high-confidence improvements that make the app feel tighter, safer, and easier to validate.
2. **Next feature wave**
   Features that materially improve everyday use without changing the app's core philosophy.
3. **Later optional expansions**
   Valid ideas, but not required for the current minimal file-based editor direction.

---

## Near-term polish

### Validation and QA

- [ ] Add targeted UI tests for the highest-risk end-to-end flows:
  - first-launch workspace pick
  - open document and autosave
  - open-file rename/delete from the browser
  - reconnect after invalid workspace restore
- [ ] Keep expanding regression tests before any future save/conflict refactor
- [ ] Add one lightweight release checklist for pre-ship simulator + real-device sanity passes

### Workspace and editor quality

- [ ] Profile larger workspace refreshes and document-load paths, then document any practical size limits if needed
- [ ] Continue small accessibility polish where it improves real use:
  - VoiceOver wording on file/folder rows
  - recovery messaging clarity
  - Dynamic Type checks on edge-state screens
- [ ] Refine recovery messaging only where it reduces ambiguity during reconnect, missing-file, or failed-save flows

### Tooling and maintainability

- [ ] Keep debug-only diagnostics around save/revalidate/restore transitions easy to inspect during real-device investigation
- [ ] Add one short contributor note for testing provider-backed changes before merging persistence-sensitive work

---

## Next feature wave

### Browser productivity

- [x] Add lightweight file search/filter within the current workspace snapshot
- [ ] Add a recent-files or quick-reopen surface that stays workspace-relative and minimal
- [ ] Evaluate folder rename/move support if it becomes a real product requirement

### Editor productivity

- [ ] Add keyboard shortcuts for common actions on iPad and hardware-keyboard use:
  - refresh workspace
  - create file
  - open settings
  - reload conflicted file where applicable
- [ ] Add a lightweight document info surface for the active file:
  - relative path
  - last saved time
  - file size if already available cheaply
- [ ] Consider a small set of editor preferences only if they stay minimal and do not create a new storage model

### Recovery and workflow polish

- [ ] Improve recovery UX for missing-file and reconnect states if real-device QA shows recurring confusion
- [ ] Consider a small “recently opened” restore aid only if it remains relative-path based and workspace-scoped

---

## Later optional expansions

These are reasonable ideas, but they are not part of the current stable-release direction:

- [ ] markdown preview
- [ ] syntax highlighting
- [ ] custom text engine
- [ ] tabs or multi-document editing
- [ ] multi-window / multi-scene workflow improvements
- [ ] Git integration
- [ ] plugin architecture
- [ ] app-owned mirrored storage model
- [ ] formatting toolbar / rich text features
- [ ] broader import policy beyond UTF-8 plain text

---

## Current known limitations

- [x] one workspace is active at a time
- [x] one live document session is active at a time
- [x] documents are treated as UTF-8 plain text
- [x] in-app mutations cover files, not folder rename/move
- [x] external same-document refresh is focused on the active editor session rather than general background sync
- [x] real-device file-provider timing can vary, so live same-document refresh is best-effort rather than a hard realtime guarantee

These are explicit limits, not accidental gaps.

---

## Working rule from here

Before implementing any new work, check:

1. does it preserve calm autosave behavior?
2. does it keep the workspace folder as source of truth?
3. does it keep browser, editor, and restore state coherent?
4. is there targeted regression coverage for the risky part?

If any answer is no, fix that first.
