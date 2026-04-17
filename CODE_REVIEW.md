# CODE_REVIEW.md

## Scope and caveat

This review is based on static inspection of the current repository, its tests, and the existing markdown docs.
I did **not** run the Xcode test suite in this environment, so findings about runtime behavior are grounded in source/test inspection rather than device execution.

Status note:

- this document is now primarily a historical review snapshot,
- the hardening pass that followed addressed the major safety/state findings that originally drove the backlog,
- keep the sections below as rationale and context, not as the current live list of unresolved issues.

## Executive summary

Downward is in **meaningfully better shape than an average iterative SwiftUI app**.
It has real boundaries (`WorkspaceManager`, `DocumentManager`, `PlainTextDocumentSession`), a useful amount of test coverage, and the hardening work since this review was written closed most of the major trust/state issues it originally called out.

The codebase is **not a rewrite candidate**.
It was a **hardening candidate**, and that hardening work is now largely complete.

The main risks are no longer “basic architecture is missing.” The current remaining pressures are:

1. an increasingly overloaded **`AppCoordinator` + `AppSession` control plane**,
2. a still-pragmatic **global-ish error ownership model**,
3. the explicitly temporary **single-document constraint**,
4. the intentionally simple **whole-snapshot browser/search model**, and
5. a few remaining **preview/docs/product-model drift risks** that should stay visible.

Those are no longer “fix the safety model first” issues.
They are “be explicit before scaling or feature expansion” issues.

## What is already working well

### 1. The core layers are visible

The repository still has a legible split between:

- app/session orchestration,
- workspace persistence + enumeration + mutations,
- document open/save/revalidate/observe behavior,
- SwiftUI feature surfaces.

That is a strong base. The app does not need a ground-up architectural reset.

### 2. Canonical file identity is much improved

Relative-path identity is now used consistently in the main browser/recent/restore flows.
That is a big improvement over earlier “display name reconstructed path” behavior.

### 3. Tests cover non-trivial behavior

The test suite goes beyond superficial store tests. It exercises:

- save/revalidate/conflict rules,
- delayed load races,
- compact/regular navigation transitions,
- restore/reconnect flows,
- refresh winner logic,
- coordinated rename/delete behavior,
- fallback observation behavior,
- the editor inset bridge.

That is real engineering value, not ceremonial coverage.

### 4. The `TextEditor` inset workaround is now isolated

The bridge moved out of the screen into `EditorTextViewHostBridge.swift`, which is a much better ownership boundary than sprinkling UIKit view probing inside `EditorScreen`.

### 5. Recent docs are directionally useful

The current markdown docs are not wildly detached from the codebase. They already describe many of the right concerns.
The next rewrite should make them more current, more specific, and more future-feature-oriented.

---

## Findings by severity

Most of the specific findings below are now resolved in the implementation.
They remain useful as historical context for why the hardening roadmap took the shape it did.

## Critical

### [Resolved] C1. Workspace containment is enforced lexically, not by real filesystem containment

**Affected files**

- `Downward/Domain/Workspace/WorkspaceRelativePath.swift`
- `Downward/Domain/Workspace/WorkspaceManager.swift`
- `Downward/Infrastructure/WorkspaceEnumerator.swift`
- `Downward/Domain/Document/PlainTextDocumentSession.swift`
- `Downward/Infrastructure/Platform/SecurityScopedAccess.swift`
- tests currently missing for this case

**What is wrong**

The app’s workspace boundary is mostly enforced by:

- comparing standardized path components,
- building descendant URLs from stored relative-path strings,
- assuming that “path lives under root path” means “file is truly inside workspace.”

That is not a sufficient trust boundary if the workspace contains **symbolic links or other redirected descendants**.
A path can look like it sits under the chosen workspace while resolving to content outside that workspace.

The current code does not define or enforce a symlink policy during:

- enumeration,
- relative-path generation,
- document open/save/revalidate,
- workspace file mutations.

**Why it matters**

This breaks one of the app’s core product promises: “I picked one folder, and the app edits files in that folder.”

If redirected descendants are followed implicitly, the app can:

- show files that are not truly part of the chosen workspace,
- save through a path that actually resolves outside the workspace,
- rename/delete content outside the intended root,
- build misleading restore/recent identity for content that is not really inside the workspace.

**Likely impact**

High trust risk. Even if symlink-heavy workspaces are uncommon on iPad/iPhone, this is exactly the kind of edge case that causes “I thought this app only touched one folder” bugs.

**Recommended fix**

Define an explicit redirected-descendant policy and implement it everywhere the workspace boundary matters.

Preferred policy for the current product:

- **skip symbolic links entirely** in the browser and snapshot model, unless/until the app has a fully realpath-resolved containment model,
- enforce that any URL used for document/mutation operations still resolves inside the real workspace root after resolution,
- add tests for symlinked files and symlinked folders.

**Future-feature impact**

This is a blocker for any claim of robust workspace safety.

---

## High

### [Resolved] H1. Refresh winner logic does not yet fully cover refresh-vs-mutation races

**Affected files**

- `Downward/App/AppCoordinator.swift`
- `Downward/Features/Workspace/WorkspaceViewModel.swift`
- `Downward/Domain/Workspace/WorkspaceManager.swift`
- `Downward/Features/Workspace/WorkspaceFolderScreen.swift`
- tests currently strong for refresh-vs-refresh, weak for refresh-vs-mutation

**What is wrong**

The app now prevents **older refreshes from overwriting newer refreshes**.
That is good.

But the current winner policy is still centered on refresh contexts.
It does **not** fully solve the case where:

1. a refresh starts,
2. a file mutation runs before that refresh finishes,
3. the mutation applies a fresh post-mutation snapshot,
4. the older refresh result then arrives and is still considered “the latest refresh,”
5. the browser/session state is overwritten by a snapshot that predates the mutation.

This is especially relevant because the UI still allows row-level rename/delete affordances while refresh is in progress.

**Why it matters**

This can make the browser jump backward after the user already renamed/deleted/created a file.
It also means reconciliation logic (recents pruning, open-document presence checks, selection cleanup) can run against the wrong snapshot.

**Likely impact**

State incoherence rather than immediate data loss, but it undermines trust in the browser and makes future features much riskier.

**Recommended fix**

Move to one explicit **workspace snapshot application winner policy** that covers:

- refreshes,
- mutations,
- restore/reconnect replacements.

A good next step is a single coordinator-owned “workspace state application generation” or serial workspace operation boundary.
Also either:

- block file mutations while refresh is active, or
- queue mutations and refreshes explicitly.

**Future-feature impact**

Blocks more advanced browser features and any future optimistic UI.

---

### [Resolved] H2. Read-side I/O uses `Task.detached`, so cancellation does not propagate cleanly

**Affected files**

- `Downward/Domain/Document/PlainTextDocumentSession.swift`
- `Downward/Domain/Workspace/WorkspaceManager.swift`

**What is wrong**

Open/revalidate/save/snapshot work is offloaded with `Task.detached`.
That keeps blocking file work off the main actor, but it also breaks parent-task cancellation propagation.

So when the caller cancels:

- a document load,
- a refresh,
- a revalidation,

the result may be ignored correctly by generation checks, but the detached work can keep running anyway.

**Why it matters**

The state guards are good enough to avoid many stale-apply bugs, but the underlying work still happens.
On provider-backed folders that means unnecessary reads, enumerations, and churn after the user has already navigated away.

**Likely impact**

- wasted file/provider work,
- harder-to-reason-about cancellation semantics,
- weaker foundation for future async features,
- tests that prove “stale result does not apply” but not “work cancels when no longer needed.”

**Recommended fix**

Keep the off-main work, but move it behind cancellation-aware child tasks or a small dedicated worker boundary that preserves cancellation semantics.
Do not rely on `Task.detached` for ordinary cancelable read work.

**Future-feature impact**

High. The more async surfaces the app gains, the more this becomes a scalability problem.

---

### H3. `AppCoordinator` and `AppSession` are becoming a single overloaded control plane

**Affected files**

- `Downward/App/AppCoordinator.swift`
- `Downward/App/AppSession.swift`
- `Downward/Features/Root/RootViewModel.swift`
- indirectly most feature view models

**What is wrong**

`AppCoordinator` now owns too many responsibilities at once:

- bootstrap / restore,
- reconnect / clear workspace,
- refresh winner logic,
- mutation reconciliation,
- recent-file pruning,
- restorable session persistence,
- document loading and activation,
- regular/compact navigation normalization,
- editor presentation,
- error mapping.

`AppSession` likewise holds launch state, workspace state, navigation state, open document state, and global error state.

This is still understandable today, but it is no longer a “small app coordinator.”
It is now the main cross-domain policy engine.

**Why it matters**

Future changes will keep landing in the same giant file.
That increases regression risk and makes local reasoning harder.

**Likely impact**

Not an immediate product bug, but a major future-feature drag.

**Recommended fix**

Do not rewrite everything.
Extract smaller seams first:

- a workspace-state application/reconciliation helper,
- a document presentation/navigation helper,
- scoped error channels or error presenters,
- possibly a `WorkspaceSessionController` boundary around restore/refresh/mutation application.

**Future-feature impact**

High. This is the main maintainability bottleneck.

---

### [Improved] H4. Error state is still global and cross-surface

**Affected files**

- `Downward/App/AppSession.swift`
- `Downward/Features/Root/RootViewModel.swift`
- `Downward/Features/Editor/EditorViewModel.swift`
- `Downward/App/AppCoordinator.swift`

**What is wrong**

The app previously used a small number of global error slots:

- `lastError`
- `editorLoadError`

Those are written by launch flows, workspace flows, editor flows, revalidation flows, and reconnect flows.

**Why it matters**

The current app is simple enough that this still mostly works.
But it makes error lifecycle fragile:

- one success path can clear another surface’s error,
- editor-specific failures can become root alerts,
- browser alerts and hidden-editor alerts share the same channel.

**Likely impact**

Moderate today, but this will get worse as settings, search, and richer editor flows grow.

**Recommended fix**

Introduce scoped error ownership:

- launch/reconnect errors,
- workspace/browser alerts,
- editor-local failures,
- passive/background warnings.

Do not keep expanding the current global error sink.

**Future-feature impact**

High for maintainability; medium for current user-facing correctness.

---

## Medium

### [Resolved] M1. Fallback observation is still always-on background polling, not a truly degraded mode

**Affected files**

- `Downward/Domain/Document/PlainTextDocumentSession.swift`
- `Downward/Features/Editor/EditorViewModel.swift`
- `Tests/DocumentManagerTests.swift`
- `Tests/EditorConflictTests.swift`

**What is wrong**

The fallback observer now backs off and only emits when cheap metadata changes.
That is better than constant synthetic churn.

But fallback still starts unconditionally for every observed file stream.
So the code still treats fallback polling as part of normal steady-state observation instead of a contingency path.

**Why it matters**

It keeps extra moving parts alive even when `NSFilePresenter` may already be sufficient.
That adds background work and complexity to the editor trust model.

**Likely impact**

Mostly efficiency and long-term maintainability rather than immediate correctness.

**Recommended fix**

Make fallback explicit degraded mode:

- gate it behind a capability/provider policy,
- or start it only after presenter behavior proves insufficient,
- or give it a stronger idle/off transition.

Add lightweight diagnostics so the app can tell which path is active.

**Future-feature impact**

Medium. Important for calm editor behavior on bigger future feature sets.

---

### [Resolved] M2. Search results lost their visual path disambiguation

**Affected files**

- `Downward/Features/Workspace/WorkspaceRowView.swift`
- `Downward/Features/Workspace/WorkspaceSearchResultsView.swift`
- `Downward/Features/Workspace/WorkspaceSearchResult.swift`
- previews/sample data

**What is wrong**

`WorkspaceSearchResult` still carries canonical relative-path information.
`WorkspaceNode.File.subtitle` still exists.
But the current row view no longer renders the subtitle visually.

That means search results show only the filename + date metadata.
Two files with the same name in different folders will be visually ambiguous.

**Why it matters**

This is a correctness problem in search UX, not just a cosmetic issue.
The model still knows the right path; the UI is failing to expose it.

**Likely impact**

User confusion in real workspaces with repeated names like `README.md`, `index.md`, `Notes.md`, etc.

**Recommended fix**

Give search results a row variant that renders relative path clearly.
Do not overload the tree-browser row if that hurts the main sidebar layout.

**Future-feature impact**

Medium. Search will only get more important as the app grows.

---

### [Resolved] M3. Recent files are keyed by absolute workspace path, so moved/restored workspaces lose history

**Affected files**

- `Downward/Domain/Persistence/RecentFilesStore.swift`
- `Downward/Domain/Persistence/RecentFileItem.swift`
- restore/reconnect flows in `AppCoordinator.swift`

**What is wrong**

Recent items are tied to `workspaceRootPath` (a standardized absolute path string).
If the same logical workspace is restored through a bookmark at a different path, the recent files no longer match.

**Why it matters**

The app already supports bookmark-based workspace restore and reconnect.
Absolute-path-based recent matching does not survive those flows well.

**Likely impact**

Recents can look flaky after workspace rename/move/reconnect.

**Recommended fix**

Introduce a more stable workspace identity for recents.
That could be a persisted workspace identifier derived from bookmark/session state rather than raw path alone.

**Future-feature impact**

Medium. Especially important if the app ever supports multiple remembered workspaces.

---

### [Resolved] M4. A failed new workspace selection can still persist an unusable bookmark

**Affected files**

- `Downward/Domain/Workspace/WorkspaceManager.swift`
- `Tests/WorkspaceManagerRestoreTests.swift` (missing coverage)

**What is wrong**

`selectWorkspace(at:)` saves the bookmark before the first usable snapshot is confirmed.
If snapshot loading fails after that point, the newly saved bookmark is already persisted.

**Why it matters**

A selection that failed to become a usable workspace can still become the next restore target.

**Likely impact**

Confusing restore behavior after a bad selection or provider issue.

**Recommended fix**

Make workspace selection persistence transactional:

- validate access,
- build first snapshot,
- only then persist the bookmark,
- or roll back saved bookmark state if the first snapshot fails.

**Future-feature impact**

Medium. This becomes more important as restore/reconnect behavior gets richer.

---

### [Resolved] M5. Search and tree performance are still “whole snapshot on main actor” oriented

**Affected files**

- `Downward/Features/Workspace/WorkspaceViewModel.swift`
- `Downward/Features/Workspace/WorkspaceSearchEngine.swift`
- `Downward/Domain/Workspace/WorkspaceSnapshot.swift`
- `Downward/Domain/Workspace/WorkspaceNode.swift`

**What is wrong**

The app’s current browser model is simple and testable, but it is still fully snapshot/value-tree based.
Search is recomputed synchronously over the full snapshot whenever the computed property is read.

**Why it matters**

This is fine for small-to-moderate workspaces.
It is not a scalable base for:

- larger trees,
- richer search,
- content search,
- more reactive sidebar features.

**Likely impact**

Main-thread cost and sluggish search as workspace size grows.

**Recommended fix**

Not a release blocker.
But the next architecture docs should explicitly call this out as future groundwork:

- cache/debounce search results in the view model,
- keep filename/path search lightweight for now,
- plan an index/incremental model before content search or very large trees.

**Future-feature impact**

Medium.

---

### [Resolved] M6. The single-document assumption is real but still under-documented

**Affected files**

- `Downward/App/AppSession.swift`
- `Downward/Domain/Document/DocumentManager.swift`
- `Downward/Features/Editor/EditorViewModel.swift`
- `Downward/Features/Root/RootScreen.swift`

**What is wrong**

The current app owns exactly one live open document at a time.
That is a valid current product decision.

But the code increasingly uses patterns (`visibleEditorURL`, regular/compact detail mapping, one active document session) that future contributors could accidentally treat as a stepping stone to multi-pane or multi-window support when it is not ready for that.

**Why it matters**

Unstated product limits lead to accidental architectural drift.

**Likely impact**

Future feature proposals can land on the wrong abstractions.

**Recommended fix**

Document the single-document assumption explicitly in `ARCHITECTURE.md` and keep it visible in future planning.

**Future-feature impact**

Medium.

---

### [Resolved] M7. Partial enumeration failure is intentionally tolerant, but too silent

**Affected files**

- `Downward/Infrastructure/WorkspaceEnumerator.swift`
- `Tests/WorkspaceEnumeratorTests.swift`

**What is wrong**

The app now skips unreadable descendants and keeps readable siblings.
That is a reasonable product choice.

But the implementation currently skips descendant failures with almost no diagnostics.
It also treats nearly every non-cancellation descendant failure as skippable.

**Why it matters**

This makes provider bugs, permission quirks, and user reports harder to diagnose.

**Likely impact**

Debuggability and support cost rather than direct user-facing breakage.

**Recommended fix**

Add lightweight diagnostics around skipped descendants and make the skip policy more explicit in code/docs.

**Future-feature impact**

Medium/low.

---

## Low

### [Resolved] L1. Dead or half-migrated APIs remain after recent navigation/browser changes

**Affected files**

- `Downward/Infrastructure/Platform/LifecycleObserver.swift`
- `Downward/Features/Workspace/WorkspaceViewModel.swift`
- `Downward/Features/Workspace/WorkspaceFolderScreen.swift`
- `Downward/Domain/Persistence/RecentFileItem.swift`

**Examples**

- `LifecycleObserver` is written but not meaningfully consumed.
- `WorkspaceViewModel.title(for:)`, `nodes(in:)`, `folderNode`, and `findFolder` are now mostly dead or test-only.
- `WorkspaceFolderScreen.expandedFolderURL` exists, but live call sites always pass `nil`.
- `RecentFileItem.node(in:)` appears unused.

**Why it matters**

Small dead APIs are not urgent, but they make future changes noisier.

**Recommended fix**

Do a cleanup pass after higher-priority hardening work.

---

### L2. Preview/sample data realism drifted from the live browser UI

**Affected files**

- `Downward/Shared/PreviewSupport/PreviewSampleData.swift`
- several previews in workspace/editor views

**What is wrong**

Preview fixtures still contain subtitle-rich browser samples and navigation assumptions that no longer fully match the live tree-browser UI.

**Why it matters**

Previews should help contributors see the product as it currently is, not as it used to be.

**Recommended fix**

Align preview fixtures with the current browser row model and search-row behavior.

---

## Test assessment

### What the suite does well

The tests are strongest where many apps are weakest:

- save acknowledgement merge semantics,
- autosave ordering,
- conflict behavior,
- delayed editor load races,
- compact/regular navigation normalization,
- restore/reconnect flows,
- refresh winner behavior,
- bookmark refresh semantics,
- enumerator partial-failure behavior,
- editor inset bridge behavior.

### Gaps that mattered most for the hardening pass

These were the highest-value gaps when this review was written, and they directly informed the later hardening work:

1. symlink / redirected-descendant containment tests
2. refresh-vs-mutation stale snapshot tests
3. transactional new-workspace selection persistence tests
4. cancellation-propagation tests for snapshot/document reads
5. search result row disambiguation tests
6. moved-workspace recent-files persistence behavior tests

---

## Strongest themes / root problems

### Theme 1. The filesystem trust model is still the most important risk

The app edits real files in user-selected folders.
That means path/boundary semantics matter more than in an app-owned data model.

### Theme 2. State application rules needed explicit ownership

This theme largely drove the later snapshot-winner, error-ownership, and restore/reconciliation work.

### Theme 3. Cancellation and async boundaries needed a final read-side hardening pass

This theme drove the later structured-cancellation work in the document/workspace read paths.

### Theme 4. The project needs smaller policy seams, not a new architecture

The next step is not “replace everything.”
It is “extract the overloaded control-plane responsibilities into clearer, testable boundaries.”

---

## Recommended implementation order

This sequence is now mostly historical.
It was the right order for the hardening backlog that followed:

1. close the workspace containment hole around redirected descendants
2. unify snapshot winner policy across refreshes and mutations
3. remove `Task.detached` from cancelable read-side I/O
4. scope error ownership and reduce `AppCoordinator` pressure
5. make fallback observation truly degraded mode
6. make workspace selection persistence transactional
7. improve recent-files workspace identity
8. clean up dead/half-migrated APIs and preview drift
9. only then invest heavily in richer browser/search/editor features
