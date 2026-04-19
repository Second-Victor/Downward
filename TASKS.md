# TASKS.md

## Purpose

This file is the active backlog and steering summary for Downward.
It intentionally replaces the older split between separate plans, debt, review, and QA steering docs.

---

## Current state

The repo is no longer in emergency hardening mode.
The strongest current foundations are:

- the workspace trust boundary,
- relative-path-first open identity,
- restore and reconnect behavior,
- quiet autosave and calmer revalidation,
- recent files and editor appearance persistence,
- a broad test suite around risky behaviors.

The main risks now are **maintainability**, **large-file pressure**, and **real-device UI polish**, not basic correctness.

---

## Current guardrails

These are not backlog items. They are shipping expectations.

- Browser, search, and recent-file opens should stay relative-path-first whenever that identity is already known.
- Final file-system operations must still validate against the chosen workspace root.
- Redirected descendants must not re-enter the browser or document pipeline.
- The app still owns one active live document session at a time.
- Autosave should remain quiet.
- Conflict UI should remain exceptional.
- Refreshes and mutations must continue to reconcile under one explicit winner policy.
- Settings and editor polish must not push unrelated logic into Views or into `PlainTextDocumentSession`.

---

## Highest-priority work

### 1. Split the giant smoke-test suite

**Why**

`Tests/MarkdownWorkspaceAppSmokeTests.swift` is valuable but too large to stay healthy.

**Success**

- preserve current cross-feature coverage,
- move feature-specific cases into smaller suites,
- keep only true end-to-end smoke flows in the remaining file.

**Likely files**

- `Tests/MarkdownWorkspaceAppSmokeTests.swift`
- new focused test files in `Tests/`

### 2. Remove repeated whole-tree relative-path lookup from hot paths

**Why**

`WorkspaceSearchEngine` and `RecentFilesStore` still do repeated snapshot-wide path re-resolution that is correct but unnecessarily expensive.

**Success**

- carry relative paths while traversing,
- avoid repeated `snapshot.relativePath(for:)` work,
- keep user-visible behavior unchanged.

**Likely files**

- `Downward/Features/Workspace/WorkspaceSearchEngine.swift`
- `Downward/Domain/Persistence/RecentFilesStore.swift`
- `Downward/Domain/Workspace/WorkspaceSnapshotPathResolver.swift`

### 3. Stabilize editor top chrome and first-line placement on iPhone and iPad

**Why**

The current `MarkdownEditorTextView` top-clearance behavior is still fragile on real devices.
This is now an active product issue, not a theoretical polish task.

**Success**

- the first visible line is not hidden under top chrome,
- placeholder and caret start position stay aligned,
- behavior remains correct on iPhone and iPad,
- the solution is dynamic rather than device-specific magic numbers.

**Likely files**

- `Downward/Features/Editor/MarkdownEditorTextView.swift`
- `Downward/Features/Editor/EditorScreen.swift`
- related editor tests if added

### 4. Keep `AppCoordinator` from regaining feature logic

**Why**

`AppCoordinator.swift` is still the easiest place for “just one more rule” to accumulate.

**Success**

- new navigation rules land in `WorkspaceNavigationPolicy`,
- workspace-state application rules land in `WorkspaceSessionPolicy`,
- the coordinator stays an orchestrator instead of becoming the architecture.

### 5. Protect `PlainTextDocumentSession` and the renderer from feature creep

**Why**

`PlainTextDocumentSession.swift` and `MarkdownStyledTextRenderer.swift` are both real boundaries and easy places to overstuff.

**Success**

- session code stays focused on file truth,
- rendering code stays focused on markdown presentation,
- new editor UX does not automatically land in either file.

### 6. Ship the settings redesign as a real maintained surface

**Why**

The current settings screen works but still looks like a stopgap compared with the desired product direction.

**Success**

- replace the plain `Form` presentation with the card-style settings flow,
- wire existing editor and workspace settings to the redesigned UI,
- keep undeveloped sections as explicit placeholders rather than fake-complete settings.

**Likely files**

- `Downward/Features/Settings/SettingsScreen.swift`
- small dedicated settings subviews if needed

---

## Secondary cleanup

### 7. Remove stale editor bridge leftovers

`EditorTextViewHostBridge.swift` and its tests appear to describe an older editor implementation path.
The current shipping editor already uses `MarkdownEditorTextView` directly.

Clean this up so the codebase and docs stop telling two different stories.

### 8. Keep preview and sample data aligned with the real product model

Preview and sample identity should stay close to the same relative-path-first model used in production so visual testing stays useful.

### 9. Keep docs truthful

Any editor, navigation, or settings change should be reflected in:

- `AGENTS.md` when it changes a hard rule,
- `ARCHITECTURE.md` when it changes ownership,
- `TASKS.md` when it changes active priorities or known pressure points.

---

## Intentional debt that is acceptable for now

- `AppCoordinator.swift` is still large, but not yet a rewrite case.
- `PlainTextDocumentSession.swift` is still dense, but it is currently the right file-session boundary.
- The app still uses one whole workspace snapshot and simple filename/path search.
- URL-only open paths still exist for compatibility, but should stay secondary.

---

## Explicit non-goals right now

Do not start these without a design pass first:

- content search,
- a second editor implementation,
- multi-window or multi-pane live editing,
- an app-owned mirrored document store,
- large-scale architecture rewrites without a concrete product need.
