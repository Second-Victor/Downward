# TASKS.md

## Purpose

This file is the actionable backlog for the current Downward codebase.
It is organized by priority and written so each task can be turned into a focused coding pass later.

The project does **not** need a rewrite.
It needs targeted hardening in a deliberate order.

---

## Release blockers

## [x] 1. Close the redirected-descendant workspace boundary hole

**Problem**

Workspace containment is currently based mostly on lexical path logic (`WorkspaceRelativePath`, descendant URL reconstruction, path-prefix assumptions).
That is not enough to guarantee that every surfaced/mutated descendant truly lives inside the chosen workspace if symbolic links or equivalent redirected descendants are present.

**Why it matters**

This is the highest-trust issue in the app.
The product promise is that Downward edits files in one chosen folder.
The current code can violate that promise in edge cases.

**What success looks like**

- the app defines an explicit policy for symbolic links / redirected descendants,
- enumeration, document access, and file mutations all enforce that policy,
- the browser never surfaces items that escape the true workspace root,
- save/rename/delete cannot target content outside the workspace,
- tests cover symlinked file and symlinked folder cases.

**Likely affected areas/files**

- `Downward/Domain/Workspace/WorkspaceRelativePath.swift`
- `Downward/Domain/Workspace/WorkspaceManager.swift`
- `Downward/Infrastructure/WorkspaceEnumerator.swift`
- `Downward/Domain/Document/PlainTextDocumentSession.swift`
- `Downward/Infrastructure/Platform/SecurityScopedAccess.swift`
- new tests in `Tests/WorkspaceEnumeratorTests.swift` and document/workspace manager tests

---

## [ ] 2. Unify workspace snapshot winner policy across refreshes and mutations

**Problem**

The code now prevents stale refreshes from overwriting newer refreshes, but it does not yet fully prevent an older in-flight refresh from overwriting a newer post-mutation snapshot.

**Why it matters**

The browser and reconciliation logic can still jump backward after create/rename/delete if refresh and mutation timing interleave badly.

**What success looks like**

- one explicit winning policy governs every `workspaceSnapshot` replacement,
- refresh-vs-mutation races cannot reapply stale tree state,
- recent-file pruning and open-document reconciliation always run against the winning snapshot,
- the UI no longer allows unsafe refresh/mutation interleaving without a defined policy,
- tests cover refresh racing with rename/delete/create.

**Likely affected areas/files**

- `Downward/App/AppCoordinator.swift`
- `Downward/Features/Workspace/WorkspaceViewModel.swift`
- `Downward/Features/Workspace/WorkspaceFolderScreen.swift`
- `Downward/Domain/Workspace/WorkspaceManager.swift`
- `Tests/MarkdownWorkspaceAppSmokeTests.swift`

---

## [ ] 3. Remove `Task.detached` from cancelable read-side I/O

**Problem**

Document open/revalidate/save and workspace snapshot reads are offloaded with `Task.detached`, which drops parent-task cancellation semantics.

**Why it matters**

State guards stop many stale applies, but canceled work can still continue doing file/provider I/O after the user no longer needs it.
That is fragile for future async work and provider-backed folders.

**What success looks like**

- canceling a refresh or document load cancels the expensive read-side work cleanly enough,
- background work still stays off the main actor,
- generation guards remain in place but are no longer the only protection,
- tests cover cancellation where practical.

**Likely affected areas/files**

- `Downward/Domain/Document/PlainTextDocumentSession.swift`
- `Downward/Domain/Workspace/WorkspaceManager.swift`
- tests with delayed/cancelable enumerator and document fixtures

---

## High-priority robustness work

## [ ] 4. Reduce coordinator pressure by extracting smaller policy seams

**Problem**

`AppCoordinator` owns too many cross-domain rules at once.
That makes future features and bug fixes converge on one large file.

**Why it matters**

The architecture is still understandable today, but it is already close to “every non-trivial behavior change touches the coordinator.”
That is the next maintainability risk.

**What success looks like**

- `AppCoordinator` remains the top-level orchestrator, but not the implementation home for all policy logic,
- workspace state application and reconciliation are easier to reason about in isolation,
- document presentation/restore rules are easier to test independently,
- future feature work can land in smaller files.

**Likely affected areas/files**

- `Downward/App/AppCoordinator.swift`
- `Downward/App/AppSession.swift`
- `Downward/Features/Root/RootViewModel.swift`
- supporting extracted types/helpers

---

## [ ] 5. Scope error ownership by surface instead of using global error slots

**Problem**

`lastError` and `editorLoadError` currently serve too many unrelated flows.

**Why it matters**

As the app grows, this will cause overwritten alerts, confusing error lifetime, and brittle presentation rules.

**What success looks like**

- launch/reconnect errors are owned separately from editor/browser alerts,
- editor-local failures do not need to travel through root alert state unless explicitly intended,
- success in one surface does not casually clear another surface’s pending error.

**Likely affected areas/files**

- `Downward/App/AppSession.swift`
- `Downward/App/AppCoordinator.swift`
- `Downward/Features/Root/RootViewModel.swift`
- `Downward/Features/Editor/EditorViewModel.swift`
- possibly root/browser/editor view surfaces

---

## [ ] 6. Make fallback observation truly degraded mode

**Problem**

Fallback polling still starts as part of ordinary observation instead of only when it is genuinely needed.

**Why it matters**

This keeps extra background work and complexity alive in the normal editor path.

**What success looks like**

- fallback mode has an explicit trigger or policy,
- no-change editors do not pay permanent polling cost unless necessary,
- diagnostics make it visible which observation mode is active,
- external changes are still detected reliably enough.

**Likely affected areas/files**

- `Downward/Domain/Document/PlainTextDocumentSession.swift`
- `Downward/Features/Editor/EditorViewModel.swift`
- `Tests/DocumentManagerTests.swift`
- `Tests/EditorConflictTests.swift`

---

## [ ] 7. Make new-workspace selection persistence transactional

**Problem**

A bookmark for a newly selected folder is saved before the first usable snapshot is confirmed.

**Why it matters**

A failed selection can become the next restore target even though it never became a usable workspace.

**What success looks like**

- new workspace selection only becomes persisted state after first successful snapshot,
- or failed selection rolls back persisted bookmark state,
- replacing an active workspace still preserves the current workspace if the new selection fails,
- tests cover first-snapshot failure after selection.

**Likely affected areas/files**

- `Downward/Domain/Workspace/WorkspaceManager.swift`
- `Tests/WorkspaceManagerRestoreTests.swift`
- possibly reconnect/replace flow tests in `Tests/MarkdownWorkspaceAppSmokeTests.swift`

---

## Medium-priority architecture cleanup

## [ ] 8. Introduce a stable workspace identity for recent files

**Problem**

Recent files are keyed by absolute workspace path, so moved/restored workspaces lose history.

**Why it matters**

Bookmark-based restore/reconnect is already part of the product.
Recent-file persistence should not feel less stable than workspace restore.

**What success looks like**

- recent files survive workspace restore/reconnect more predictably,
- the chosen identity is documented,
- migration behavior for existing stored recents is defined.

**Likely affected areas/files**

- `Downward/Domain/Persistence/RecentFilesStore.swift`
- `Downward/Domain/Persistence/RecentFileItem.swift`
- `Downward/App/AppCoordinator.swift`
- docs/tests covering moved-workspace behavior

---

## [ ] 9. Separate search result presentation from tree-row presentation

**Problem**

The tree row is now optimized for the sidebar browser, but search results still reuse it even though they need visible path disambiguation.

**Why it matters**

Search correctness suffers when different files share the same name.

**What success looks like**

- search rows render filename + clear relative-path context,
- the tree browser keeps its current focused layout,
- previews/tests reflect the difference,
- no ambiguity remains for duplicate filenames in search results.

**Likely affected areas/files**

- `Downward/Features/Workspace/WorkspaceRowView.swift`
- `Downward/Features/Workspace/WorkspaceSearchResultsView.swift`
- `Downward/Features/Workspace/WorkspaceSearchResult.swift`
- previews/tests around search rows

---

## 10. Move search computation out of the hot render path

**Problem**

Search is recomputed synchronously over the full snapshot during normal view rendering.

**Why it matters**

That is acceptable now, but it is not a good base for larger workspaces or richer search.

**What success looks like**

- search results are cached or debounced in the view model,
- basic filename/path search stays simple,
- the app remains responsive as the tree grows,
- architecture docs explain when a true index becomes necessary.

**Likely affected areas/files**

- `Downward/Features/Workspace/WorkspaceViewModel.swift`
- `Downward/Features/Workspace/WorkspaceSearchEngine.swift`
- docs/tests if behavior changes

---

## 11. Document the single-document model and its future escape hatch

**Problem**

The app currently assumes one active document and one active live document session, but this is easy to miss if future work starts pushing toward multi-pane behavior.

**Why it matters**

Hidden product limits turn into accidental architectural drift.

**What success looks like**

- `ARCHITECTURE.md` explicitly states the single-document assumption,
- future multi-pane/multi-window work is blocked on an intentional ownership redesign rather than incidental changes,
- no new code quietly assumes the current global `openDocument` model scales further than it does.

**Likely affected areas/files**

- `ARCHITECTURE.md`
- possibly comments in `AppSession.swift`, `DocumentManager.swift`, `EditorViewModel.swift`

---

## Future feature groundwork

## 12. Add diagnostics for partial enumeration skips and observation mode

**Problem**

The app now tolerates partial enumeration failure and fallback observation, but both can fail quietly in ways that are hard to diagnose.

**Why it matters**

Future provider-related bugs will be much harder to debug without lightweight diagnostics.

**What success looks like**

- skipped descendant enumeration is visible in debug logs or diagnostics,
- fallback observation mode is visible in debug logs or diagnostics,
- these diagnostics do not pollute user-facing UI.

**Likely affected areas/files**

- `Downward/Infrastructure/WorkspaceEnumerator.swift`
- `Downward/Domain/Document/PlainTextDocumentSession.swift`
- `Downward/Infrastructure/Logging/DebugLogger.swift`

---

## 13. Plan the eventual move from whole-snapshot replacement to more scalable browser/search infrastructure

**Problem**

The current whole-tree value snapshot is clean and testable, but it is not the likely final shape for very large workspaces, richer search, or more dynamic browser behavior.

**Why it matters**

This is not urgent today, but it will matter before content search or highly dynamic sidebar features are added.

**What success looks like**

- the current docs describe the limit clearly,
- future proposals for content search or very large workspaces start from an explicit scaling discussion,
- no accidental complexity is added on top of the current simple snapshot model without acknowledging the tradeoff.

**Likely affected areas/files**

- `ARCHITECTURE.md`
- `PLANS.md`
- later: workspace/search infrastructure files

---

## Polish / nice-to-have

## 14. Remove dead or half-migrated APIs after the hardening work lands

**Problem**

There are still small leftovers from earlier browser/navigation iterations and preview scaffolding.

**Why it matters**

This is not a blocker, but it makes the codebase noisier than it needs to be.

**What success looks like**

- unused lifecycle/browser helpers are removed or clearly quarantined,
- previews match the current product model,
- row/model helpers that no longer serve live UI are trimmed.

**Likely affected areas/files**

- `Downward/Infrastructure/Platform/LifecycleObserver.swift`
- `Downward/Features/Workspace/WorkspaceViewModel.swift`
- `Downward/Features/Workspace/WorkspaceFolderScreen.swift`
- `Downward/Domain/Persistence/RecentFileItem.swift`
- preview/sample data files

---

## 15. Unify editor placeholder alignment with the editor inset bridge

**Problem**

The editor text inset now has a good ownership boundary, but the empty-file placeholder still depends on a duplicated magic inset value in `EditorScreen`.

**Why it matters**

Small now, but it is the kind of drift that accumulates around platform workarounds.

**What success looks like**

- placeholder alignment and text inset come from one shared configuration source,
- resize/rotation/document switching do not create visible mismatch.

**Likely affected areas/files**

- `Downward/Features/Editor/EditorScreen.swift`
- `Downward/Features/Editor/EditorTextViewHostBridge.swift`
- related previews/tests if needed
