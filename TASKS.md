# TASKS.md

## Purpose

This file is the **active engineering backlog** for Downward.

The repo is no longer in an emergency correctness phase. The workspace trust model, editor restore flow, file mutation flow, recent files, pull-to-refresh, and editor appearance settings are all present and materially stronger than they were.

The next work should therefore focus on four things:

1. keeping the current file-safety and editor-state guarantees intact,
2. reducing the few maintainability hotspots that are still easy to regress,
3. making the existing test suite easier to trust and evolve,
4. only then resuming user-visible polish in small, safe passes.

This backlog is intentionally shaped by the current codebase, not by older plans.

---

## Current release guardrails

These are not open tasks. They are current invariants that future work must preserve.

- Browser, search, and recent-file opens must stay **relative-path-first** whenever the UI already knows the trusted workspace-relative path.
- The final file-system boundary must still validate access against the chosen workspace before opening, saving, renaming, or deleting.
- Redirected descendants must not quietly re-enter the browser or document pipeline.
- Refreshes and mutations must continue to reconcile under one explicit snapshot-winner policy.
- Read-side file work must remain cancellation-aware.
- Detached tasks should remain an explicit exception for write or mutation work that should outlive transient caller cancellation.
- The app still owns **one active live document session at a time**.
- Settings, recents, and browser polish must not grow by pushing unrelated logic into Views.

---

## Highest-priority work

## 1. Break up the giant smoke-test file without reducing coverage

**Problem**

`Tests/MarkdownWorkspaceAppSmokeTests.swift` is now extremely large and carries too many unrelated behaviors in one place.

**Why it matters**

The coverage is valuable, but one oversized suite becomes harder to navigate, slower to diagnose, and easier to avoid updating carefully.

**What success looks like**

- the current end-to-end style coverage is preserved,
- the suite is split into smaller feature-oriented files,
- the remaining smoke tests focus on true cross-feature flows,
- failures become easier to localize.

**Suggested split directions**

- restore and reconnect flows,
- browser/search/recent-file open flows,
- create/rename/delete reconciliation,
- editor load and route presentation,
- settings and workspace shell behavior.

**Likely affected areas/files**

- `Tests/MarkdownWorkspaceAppSmokeTests.swift`
- new focused test files in `Tests/`

---

## 2. Remove repeated whole-tree relative-path lookup from hot paths

**Problem**

Some current code still resolves relative paths by repeatedly walking the entire snapshot tree:

- `WorkspaceSearchEngine` traverses files, then asks `snapshot.relativePath(for:)` for each matching file,
- `RecentFilesStore.pruneInvalidItems(using:)` flattens file URLs, then asks the snapshot to re-resolve each path.

That is acceptable at current scale, but it is unnecessary repeated work and becomes the clearest near-term performance ceiling.

**Why it matters**

This is the most concrete technical limit visible in the current code. It is not a correctness bug today, but it is the next place where larger workspaces will start to feel expensive.

**What success looks like**

- traversal code carries the already-known relative path while walking the tree,
- search results no longer need a second lookup for every match,
- recent-file pruning can build its valid relative-path set in one pass,
- the behavior stays exactly the same from the user’s point of view.

**Likely affected areas/files**

- `Downward/Features/Workspace/WorkspaceSearchEngine.swift`
- `Downward/Domain/Persistence/RecentFilesStore.swift`
- `Downward/Domain/Workspace/WorkspaceSnapshotPathResolver.swift`
- maybe a small shared snapshot traversal helper if it stays narrow

---

## 3. Consolidate relative-path derivation seams before they drift again

**Problem**

The project now has the right identity model, but relative-path derivation still exists in several places with slightly different responsibilities:

- `WorkspaceTreeRows` builds paths structurally for browser presentation,
- `WorkspaceSnapshotPathResolver` resolves paths from the in-memory tree,
- `WorkspaceManager` and `DocumentManager` use the stricter file-system validation path,
- `AppCoordinator` still contains route/document helper logic around path and URL reconciliation.

**Why it matters**

The recent file-open regression was exactly the kind of bug that happens when several layers all “almost” agree on identity.

**What success looks like**

- the code documents which layer owns which kind of path derivation,
- duplicate logic is reduced where it is safe to reduce it,
- browser/search/recent-file flows remain obviously relative-path-first,
- future contributors have one clear place to start when touching file identity.

**Likely affected areas/files**

- `Downward/Domain/Workspace/WorkspaceSnapshotPathResolver.swift`
- `Downward/Features/Workspace/WorkspaceFolderScreen.swift`
- `Downward/Features/Workspace/WorkspaceViewModel.swift`
- `Downward/App/AppCoordinator.swift`
- `Downward/Domain/Document/DocumentManager.swift`

---

## 4. Keep `AppCoordinator` from re-accumulating feature logic

**Problem**

`AppCoordinator.swift` is still the main orchestration pressure point in the repo.

**Why it matters**

The file is workable now, but it is still the easiest place for future product work to add “just one more rule” until the coordinator becomes the architecture again.

**What success looks like**

- new navigation transforms continue to land in `WorkspaceNavigationPolicy`,
- new workspace-state application rules continue to land in `WorkspaceSessionPolicy`,
- editor-local behavior stays in `EditorViewModel` or the document layer,
- the coordinator remains an orchestrator rather than a catch-all implementation file.

**Likely affected areas/files**

- `Downward/App/AppCoordinator.swift`
- `Downward/App/WorkspaceNavigationPolicy.swift`
- `Downward/App/WorkspaceSessionPolicy.swift`

---

## 5. Protect `PlainTextDocumentSession` from feature creep

**Problem**

`PlainTextDocumentSession.swift` is still a dense and sensitive boundary.

**Why it matters**

This is one of the easiest places to accidentally destabilize autosave, external-change handling, or conflict presentation.

**What success looks like**

- new editor UX does not automatically land in the live file-session type,
- session code continues to focus on open/reload/revalidate/save/observation responsibilities,
- any future split happens only when a real seam is obvious,
- tests continue to pin the current save and revalidation contract.

**Likely affected areas/files**

- `Downward/Domain/Document/PlainTextDocumentSession.swift`
- `Downward/Domain/Document/DocumentManager.swift`
- `Downward/Features/Editor/EditorViewModel.swift`
- `Tests/EditorAutosaveTests.swift`
- `Tests/EditorConflictTests.swift`
- `Tests/DocumentManagerTests.swift`

---

## Product-ready next work after the above

## 6. Add editor polish on top of the existing save contract

**Problem**

The app is finally stable enough for more visible editor improvements, but the editor is still the part of the product most likely to regress quietly.

**Why it matters**

This is the best place to add user-visible value once the maintainability tasks above are handled.

**What success looks like**

- new editor polish stays above the existing document session model,
- autosave remains quiet,
- conflict UI remains exceptional,
- background/foreground and rapid file-switch behavior stay coherent.

**Good candidates**

- better save-state affordances,
- better empty-document / metadata presentation,
- keyboard and workflow polish,
- lightweight editing conveniences that do not require a new document architecture.

**Likely affected areas/files**

- `Downward/Features/Editor/EditorScreen.swift`
- `Downward/Features/Editor/EditorViewModel.swift`
- `Downward/Features/Editor/EditorOverlayChrome.swift`
- targeted tests in `Tests/`

---

## 7. Add browser polish without changing the identity model

**Problem**

The browser is structurally sound, but it is still a prime place for accidental identity regressions and over-eager UI logic.

**Why it matters**

The browser is one of the main product surfaces and should now get incremental polish rather than architectural churn.

**What success looks like**

- row and section polish remain presentation-only,
- search results, recents, and tree rows remain aligned around relative identity,
- no new URL-first shortcuts creep into browser-driven opens.

**Good candidates**

- improved metadata display,
- stronger duplicate-filename scanning affordances,
- better empty-state and recents ergonomics,
- lightweight workflow shortcuts that do not create a second navigation model.

**Likely affected areas/files**

- `Downward/Features/Workspace/WorkspaceFolderScreen.swift`
- `Downward/Features/Workspace/WorkspaceRowView.swift`
- `Downward/Features/Workspace/WorkspaceSearchRowView.swift`
- `Downward/Features/Workspace/RecentFilesSheet.swift`
- `Downward/Features/Workspace/WorkspaceViewModel.swift`

---

## Medium-priority cleanup

## 8. Keep settings truthful to the shipped feature set

**Problem**

Settings work is no longer “future work”; it is already part of the product. The docs and tests should treat it that way.

**Why it matters**

The current settings surface now includes font family, font size, and markdown display behavior. That should not drift into an under-documented side feature.

**What success looks like**

- docs stop describing editor appearance options as pending,
- tests stay current with normalization and persistence behavior,
- future settings additions remain isolated to the appearance store and settings surface.

**Likely affected areas/files**

- `Downward/Domain/Persistence/EditorAppearanceStore.swift`
- `Downward/Features/Settings/SettingsScreen.swift`
- `Tests/EditorAppearanceStoreTests.swift`
- `ARCHITECTURE.md`

---

## 9. Keep previews and sample data aligned with the real product model

**Problem**

Preview/sample support is useful here, but it can drift after navigation or identity changes.

**Why it matters**

The repo relies on previews to iterate on SwiftUI screens. Drift here makes visual regressions harder to spot early.

**What success looks like**

- preview/sample data still reflects current relative-path-first navigation assumptions,
- browser, editor, and settings previews continue to render believable states,
- preview-only shortcuts do not teach the wrong architecture.

**Likely affected areas/files**

- `Downward/Shared/PreviewSupport/PreviewSampleData.swift`
- feature `#Preview` blocks where needed

---

## Explicit non-goals right now

These are not the right next tasks for the current repo unless product direction changes.

- Do **not** reopen the old workspace-correctness rescue phase without a new concrete regression.
- Do **not** redesign the app around multiple simultaneous live documents yet.
- Do **not** add content search until there is an explicit indexing/design pass.
- Do **not** replace the current browser with a second folder-drill-down navigation model.
- Do **not** treat editor font settings, recent files, or pull-to-refresh as unfinished foundation work; they already exist and should now be maintained, not re-planned.
