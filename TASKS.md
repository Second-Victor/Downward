# TASKS.md

## Purpose

This task list reflects the **current** state of the Downward codebase. It is not the original bootstrap checklist anymore. Use this as the safe implementation backlog from here.

Status legend:

- `[x]` complete in the current codebase
- `[~]` partially complete or needs refinement
- `[ ]` not started / still planned
- `[!]` high-risk area that needs regression protection

---

## Current baseline already in place

### App shell and composition

- [x] `AppContainer` builds the live graph
- [x] `AppSession` holds shared root state
- [x] `AppCoordinator` orchestrates restore, navigation side effects, workspace actions, and editor actions
- [x] root launch states exist for no workspace, restoring, ready, invalid access, and failure

### Workspace access and persistence

- [x] workspace bookmark storage exists
- [x] session restore storage for the last open document exists
- [x] workspace restore is attempted on launch
- [x] invalid workspace access can transition to reconnect UI

### Workspace browser

- [x] recursive workspace enumeration exists
- [x] supported file filtering exists
- [x] folders sort before files
- [x] browser UI exists for nested folder navigation
- [x] create file flow exists
- [x] rename file flow exists
- [x] delete file flow exists

### Editor core

- [x] markdown/text files open into `TextEditor`
- [x] editor state is stored in `OpenDocument`
- [x] debounce autosave exists
- [x] save queueing exists when typing continues during a save
- [x] save acknowledgement merge logic exists to preserve newer edits
- [x] manual reload / overwrite / preserve-edits conflict actions exist
- [x] background/disappear save flush exists

### Testing baseline

- [x] bookmark store tests exist
- [x] session store tests exist
- [x] workspace enumerator tests exist
- [x] workspace restore/mutation tests exist
- [x] document manager tests exist
- [x] editor autosave tests exist
- [x] editor conflict tests exist
- [x] smoke tests exist for coordinator-level flows

---

## Immediate documentation sync

### Goal

Make the repo docs accurate enough that they can be trusted again as the project's source of truth.

### Tasks

- [x] Update `AGENTS.md` to match the real app name, current architecture names, and current save model
- [x] Update `PLANS.md` so silent autosave and exceptional-only conflict UI are part of product intent
- [x] Update `ARCHITECTURE.md` to describe `AppCoordinator`, `WorkspaceManager`, `DocumentManager`, and `EditorViewModel` as they actually exist
- [x] Replace the old bootstrap-oriented `TASKS.md` with a current backlog

### Acceptance criteria

- [x] The docs no longer refer to `WorkspaceService` / `DocumentService` as the primary architecture
- [x] The docs no longer imply that frequent conflict popups are normal UX
- [x] A new coding agent can follow the docs without being sent backwards

---

## Phase 1 — Harden active-document save and external-change behavior

### Goal

Keep the active editor calm during normal typing while preserving recovery for true external changes.

### Tasks

- [x] Audit `DocumentManager` save and revalidation behavior for any remaining self-conflict edge cases
- [x] Add a regression test for repeated autosaves on one open document where the user keeps typing between save completions
- [x] Add a regression test for same-document external change visibility while the editor is open
- [x] Define and document the exact policy for when external changes should silently refresh versus require resolution
- [x] Ensure foreground revalidation and any live-refresh mechanism share the same conflict policy
- [x] Confirm save-state UI stays calm during successful autosave bursts

### Acceptance criteria

- [x] Routine typing on a healthy file never requires repeated manual overwrite taps
- [x] The app's own saves do not later appear as `modifiedOnDisk`
- [x] A true external delete or move still surfaces recoverably
- [x] Same-document external refresh behavior is predictable and covered by tests

### Suggested files

- `Downward/Domain/Document/DocumentManager.swift`
- `Downward/Features/Editor/EditorViewModel.swift`
- `Downward/App/AppCoordinator.swift`
- `Tests/DocumentManagerTests.swift`
- `Tests/EditorAutosaveTests.swift`
- `Tests/EditorConflictTests.swift`

---

## Phase 2 — Workspace mutation coherence while editor is open

### Goal

Make create/rename/delete flows fully coherent when the current editor is affected.

### Tasks

- [~] Verify rename of the currently open file updates all of:
  - `session.openDocument`
  - `session.path`
  - restorable document session
  - visible browser selection
- [~] Verify delete of the currently open file produces the intended recovery state and no stale routes remain
- [ ] Add a focused test for renaming the open document while it has unsaved edits
- [ ] Add a focused test for deleting the open document while the editor is visible
- [ ] Confirm browser refresh and editor state stay consistent after workspace mutations in nested folders

### Acceptance criteria

- [ ] Renaming the open file never leaves a stale route or stale relative path behind
- [ ] Deleting the open file never leaves the app pretending the file still exists
- [ ] Mutation behavior is covered by coordinator or smoke tests

### Suggested files

- `Downward/App/AppCoordinator.swift`
- `Downward/Domain/Workspace/WorkspaceManager.swift`
- `Downward/Features/Workspace/WorkspaceViewModel.swift`
- `Tests/MarkdownWorkspaceAppSmokeTests.swift`
- `Tests/WorkspaceManagerRestoreTests.swift`

---

## Phase 3 — Restore and reconnect polish

### Goal

Make workspace restore and session restore feel more intentional and resilient.

### Tasks

- [ ] Verify the last-open document restore path handles renamed or missing files gracefully
- [ ] Improve reconnect messaging when bookmark access is invalid but the workspace name is known
- [ ] Add tests for restore when the saved relative path now points to a missing file
- [ ] Add tests for clearing workspace state after invalid restore scenarios
- [ ] Review whether any top-level errors should be downgraded from alerts to calmer inline messaging

### Acceptance criteria

- [ ] Relaunch into a valid workspace feels seamless
- [ ] Relaunch into an invalid workspace explains recovery clearly
- [ ] The app never restores a stale document session blindly

### Suggested files

- `Downward/App/AppCoordinator.swift`
- `Downward/Domain/Persistence/SessionStore.swift`
- `Downward/Features/Root/RootViewModel.swift`
- `Downward/Features/Root/ReconnectWorkspaceView.swift`
- `Tests/SessionStoreTests.swift`
- `Tests/MarkdownWorkspaceAppSmokeTests.swift`

---

## Phase 4 — Browser and editor polish

### Goal

Polish the core experience without expanding scope.

### Tasks

- [ ] Review `EditorOverlayChrome` to ensure save/error states are visible but not noisy
- [ ] Review empty states and loading states across workspace and editor flows
- [ ] Improve long-name handling and accessibility labels in workspace rows
- [ ] Audit previews so every user-facing screen has at least one representative preview state
- [ ] Add or refresh sample data for conflict, empty, reconnect, and failed-save states

### Acceptance criteria

- [ ] Core screens are previewable and visually coherent
- [ ] The UI feels intentionally minimal rather than unfinished
- [ ] Error and empty states are easy to understand

### Suggested files

- `Downward/Features/Editor/EditorOverlayChrome.swift`
- `Downward/Features/Workspace/WorkspaceScreen.swift`
- `Downward/Features/Workspace/WorkspaceFolderScreen.swift`
- `Downward/Features/Workspace/WorkspaceRowView.swift`
- `Downward/Shared/PreviewSupport/PreviewSampleData.swift`

---

## Phase 5 — Performance and regression safety

### Goal

Reduce the chance that future edits quietly break the save or restore model.

### Tasks

- [ ] Add targeted regression tests before any refactor of save/conflict logic
- [ ] Review enumeration and reload cost for larger workspaces
- [ ] Consider adding lightweight logging around save/revalidate transitions for debug builds only
- [ ] Audit generation-based async guards in workspace and editor flows
- [ ] Add a short contributor checklist for changes touching persistence logic

### Acceptance criteria

- [ ] Important persistence regressions are caught by tests
- [ ] Debugging save-state issues is easier in development builds
- [ ] Larger workspace refreshes remain responsive enough for MVP scope

### Suggested files

- `Downward/Infrastructure/Logging/DebugLogger.swift`
- `Downward/Features/Editor/EditorViewModel.swift`
- `Downward/Features/Workspace/WorkspaceViewModel.swift`
- `Tests/EditorAutosaveTests.swift`
- `Tests/DocumentManagerTests.swift`
- `AGENTS.md`

---

## Deferred unless explicitly requested

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

Before implementing a new feature, check it against this list:

1. does it preserve calm autosave behavior?
2. does it keep the workspace folder as source of truth?
3. does it keep browser, editor, and restore state coherent?
4. is there a targeted test for the risky part?

If the answer to any of those is no, fix that first.
