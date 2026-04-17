# ARCHITECTURE.md

## Purpose

This document describes the **actual current architecture** of Downward as it exists in the repository today.
It also records the most important boundaries that future work must preserve.

Downward is a **workspace-based text editor** for iPhone and iPad.
The user chooses a real folder from Files, the app restores access to that folder later, browses supported text files inside it, and edits those files in place.

The app does **not** own a mirrored document database.
The chosen workspace remains the source of truth.

---

## Current product model

Today’s product model is:

- one active workspace at a time,
- one active open document and one active live document session at a time,
- inline expanding file tree in the browser,
- compact iPhone-style stack navigation,
- regular iPad split sidebar/detail navigation,
- quiet autosave to the real workspace file,
- explicit conflict UI only when the app can no longer proceed calmly.

That model is important because many current implementation choices depend on it.

---

## Top-level layers

The repo is still organized into four practical layers.

### 1. App composition and session orchestration

Main files:

- `Downward/App/AppContainer.swift`
- `Downward/App/AppSession.swift`
- `Downward/App/AppCoordinator.swift`
- `Downward/App/MarkdownWorkspaceApp.swift`
- `Downward/Features/Root/RootViewModel.swift`
- `Downward/Features/Root/RootScreen.swift`

Responsibilities:

- build live and preview dependencies,
- own root app/session state,
- bootstrap workspace restore,
- normalize compact vs regular navigation,
- coordinate workspace and document flows,
- bridge app lifecycle changes into workspace refresh and editor flush behavior.

### 2. Workspace boundary

Main files:

- `Downward/Domain/Workspace/WorkspaceManager.swift`
- `Downward/Infrastructure/WorkspaceEnumerator.swift`
- `Downward/Domain/Workspace/WorkspaceSnapshot.swift`
- `Downward/Domain/Workspace/WorkspaceNode.swift`
- `Downward/Domain/Workspace/WorkspaceRelativePath.swift`
- `Downward/Domain/Persistence/BookmarkStore.swift`
- `Downward/Domain/Persistence/RecentFilesStore.swift`
- `Downward/Domain/Persistence/SessionStore.swift`
- `Downward/Infrastructure/Platform/SecurityScopedAccess.swift`

Responsibilities:

- persist and restore workspace access,
- enumerate the current folder tree,
- refresh the browser snapshot,
- create/rename/delete files within the workspace,
- maintain canonical relative-path identity for files,
- persist recent files and last-open file metadata.

### 3. Document boundary

Main files:

- `Downward/Domain/Document/DocumentManager.swift`
- `Downward/Domain/Document/PlainTextDocumentSession.swift`
- `Downward/Domain/Document/OpenDocument.swift`
- `Downward/Domain/Document/DocumentVersion.swift`
- `Downward/Domain/Document/DocumentConflict*.swift`
- `Downward/Domain/Document/DocumentSaveState.swift`

Responsibilities:

- open documents from the active workspace,
- reload and revalidate against disk,
- save the in-memory editor buffer back to disk,
- observe external changes,
- preserve the editor buffer as authoritative during ordinary typing,
- map missing/changed files into explicit conflict state when needed.

### 4. SwiftUI feature surfaces

Main files:

- workspace: `Downward/Features/Workspace/*`
- editor: `Downward/Features/Editor/*`
- settings: `Downward/Features/Settings/SettingsScreen.swift`
- root/launch/reconnect: `Downward/Features/Root/*`

Responsibilities:

- render browser/search/editor/settings UI,
- adapt observable state to SwiftUI views,
- collect user intents and hand them to the coordinator/view models,
- avoid direct filesystem/persistence logic inside views.

---

## Current source-of-truth map

This is the most important section for future contributors.

### Workspace access

**Source of truth:** bookmark data + the currently loaded `WorkspaceSnapshot`

Owned by:

- `BookmarkStore`
- `WorkspaceManager`
- `SecurityScopedAccessHandling`

Notes:

- the app persists a bookmark for the chosen workspace,
- the live workspace browser is driven by a loaded `WorkspaceSnapshot`,
- reconnect/restore logic must respect both persisted access and current in-memory state.

### File identity inside a workspace

**Source of truth:** canonical workspace-relative path strings

Owned by:

- `WorkspaceRelativePath`
- `OpenDocument.relativePath`
- `RecentFileItem.relativePath`
- `RegularWorkspaceDetailSelection.editor(String)`

Rules:

- never derive file identity from `displayName`,
- UI labels can change; identity cannot,
- recent files, restore, rename reconciliation, and browser/open-document logic must agree on this representation.

### Browser tree contents

**Source of truth:** `WorkspaceSnapshot.rootNodes`

Owned by:

- `WorkspaceManager`
- `WorkspaceEnumerator`
- `AppSession.workspaceSnapshot`

Notes:

- the browser is snapshot-driven, not live-diff-driven,
- refresh/mutation flows replace the whole snapshot,
- `WorkspaceViewModel` derives expansion/search/prompt state around that snapshot.

Why this is still the right model today:

- it keeps workspace truth centralized in one accepted snapshot,
- refresh, restore, reconnect, and mutation reconciliation all reason about one coherent tree,
- the browser/search surface stays testable without introducing an incremental diff or index layer yet.

Current scaling limit:

- whole-snapshot replacement is a deliberate simplicity tradeoff, not a claim that very large workspaces are already solved,
- future work such as very large browser trees, incremental browser updates, richer search ranking, or content search should treat this as the boundary where a more scalable browser/search model would need to start.

### Current document contents

**Source of truth:** `AppSession.openDocument`

Owned by:

- `AppCoordinator`
- `EditorViewModel`
- `DocumentManager` / `PlainTextDocumentSession`

Notes:

- there is currently one active open document for the app,
- `LiveDocumentManager` also keeps one active `PlainTextDocumentSession` for that document,
- the editor buffer remains authoritative while the user types,
- save acknowledgements update the confirmed disk version without clobbering newer edits.

### Navigation and visible detail

**Source of truth:** split between compact path state and regular explicit detail state

Owned by:

- `AppSession.path`
- `AppSession.regularDetailSelection`
- `AppCoordinator.updateNavigationLayout(_:)`

Rules:

- compact layout uses `NavigationStack(path:)`,
- regular layout uses explicit detail selection,
- do not make regular detail depend on hidden compact history,
- folder browsing is now inline tree expansion, not folder-route navigation.

### Global app messaging / errors

**Current source of truth:** `AppSession.workspaceAlertError`, `AppSession.editorLoadError`, and `AppSession.editorAlertError`

This is a real current boundary, but it is a weak one.
Future work should treat it as a temporary compromise rather than a long-term design target.

---

## Current main flows

## 1. App bootstrap and restore

Flow:

1. `MarkdownWorkspaceApp` creates `AppContainer.live()`.
2. `RootScreen` triggers `RootViewModel.handleFirstAppear()`.
3. `AppCoordinator.bootstrapIfNeeded()` runs once.
4. `WorkspaceManager.restoreWorkspace()` loads bookmark state and tries to produce a fresh snapshot.
5. `AppCoordinator` applies the restore result into `AppSession`.
6. If restore succeeded, the coordinator optionally reopens the last document from `SessionStore`.

Important current behavior:

- restore is generation-guarded,
- invalid workspace access transitions into reconnect state,
- missing/unreadable last-open files are cleared without tearing down the workspace.

## 2. Browser refresh and reconciliation

Flow:

1. `WorkspaceViewModel` triggers `AppCoordinator.refreshWorkspace()`.
2. `WorkspaceManager.refreshCurrentWorkspace()` builds a new snapshot.
3. `AppCoordinator.runWorkspaceRefresh(...)` decides whether the refresh result is still allowed to apply.
4. If it wins, the coordinator applies the new snapshot and reconciles navigation/open-document state.

Important current behavior:

- refresh-vs-refresh winner logic exists,
- clean missing editors are removed when their file disappears from the snapshot,
- dirty/saving/conflicted editors are preserved.

Important current behavior:

- refreshes, mutations, restore, and reconnect now compete through one coordinator-owned snapshot-application winner policy.

## 3. Browser mutations

Flow:

1. browser UI asks `WorkspaceViewModel` to create/rename/delete,
2. `WorkspaceViewModel` forwards to `AppCoordinator`,
3. `WorkspaceManager` performs coordinated filesystem mutation,
4. `WorkspaceManager` returns a refreshed post-mutation snapshot,
5. `AppCoordinator` updates session state, recents, restore state, navigation, and open-document state.

Important current behavior:

- mutations are coordinated through `NSFileCoordinator`,
- open-document rename/delete reconciliation exists,
- recent files are updated for rename/delete.

Important current behavior:

- mutation results apply through the same snapshot winner policy as refreshes and restore/reconnect flows.

## 4. Editor load, save, and observation

Flow:

1. user chooses a file from the browser/search/recent files,
2. navigation state points to the editor destination,
3. `EditorScreen` appears for a document URL,
4. `EditorViewModel` asks the coordinator to load the file,
5. `DocumentManager` opens the document via `PlainTextDocumentSession`,
6. `AppCoordinator.activateLoadedDocument(...)` makes it the active `openDocument`,
7. `EditorViewModel` starts observation for external changes.

Save / revalidate behavior:

- typing updates `session.openDocument` immediately,
- autosave is debounced,
- save acknowledgements merge back into the current document so newer local edits survive late completions,
- revalidation keeps clean buffers in sync and keeps dirty buffers authoritative,
- conflict UI is reserved for true missing/divergent cases.

Important current compromise:

- `TextEditor` layout behavior still requires a UIKit bridge (`EditorTextViewHostBridge`).

Single-document ownership inside this flow:

- `AppSession.openDocument` is the one app-wide editor source of truth,
- `LiveDocumentManager` owns one active `PlainTextDocumentSession`,
- `EditorViewModel` save/reload/observe behavior assumes that one routed editor is talking to that one shared live document.

---

## Current strengths

### The app is already testing the right hard things

The project has meaningful coverage around:

- save ordering,
- conflict behavior,
- restore/reconnect,
- navigation transitions,
- refresh races,
- bookmark refresh behavior,
- enumeration policy,
- the editor inset bridge.

That should be preserved as the architecture evolves.

### Canonical identity is now a real cross-cutting rule

Relative-path identity is no longer an incidental detail.
It is part of the app’s true contract.

### The document boundary is conceptually sound

`DocumentManager` + `PlainTextDocumentSession` is the right place for the app’s file-editing trust model.
The next work here is incremental editor capability, not replacement of the boundary itself.

---

## Known weak spots / current compromises

These are part of the real current architecture and must be acknowledged explicitly.

### 1. `AppCoordinator` is still the main policy sink

The coordinator is still where most cross-domain decisions accumulate.
That is manageable today, but it is the main maintainability pressure point.

### 2. Error ownership is still pragmatic rather than ideal

`workspaceAlertError`, `editorLoadError`, and `editorAlertError` are still broader than ideal for the app’s long-term shape.
That is acceptable for the current product size, but not a good long-term target.

### 3. The editor host boundary is still a deliberate workaround

`EditorTextViewHostBridge` is the correct current place for the workaround, but it remains a bridge over `TextEditor` implementation details.
This is an owned compromise, not a solved platform abstraction.

### 4. The app is intentionally single-document

Current state:

- `AppSession.openDocument` is one shared document slot for the whole app,
- `LiveDocumentManager` keeps one active `PlainTextDocumentSession`,
- `EditorViewModel` owns one autosave / observation pipeline for the currently visible editor route,
- restore, reopen-last-document, rename/delete reconciliation, and recent-file activation all converge on making that one document current.

Why this is useful today:

- save ordering stays simpler because there is one authoritative editor buffer,
- live observation and fallback observation have one clear owner,
- restore/navigation logic only has to reconcile one visible editor target,
- conflict presentation stays tied to one active editing surface.

Known limitations:

- adding another visible editor route would not create another live document session,
- two panes would compete over `session.openDocument`, editor-local error state, autosave scheduling, and observation ownership,
- document restore and navigation currently target “the active editor,” not an arbitrary set of editor presentations.

What future contributors must not assume:

- adding tabs, split panes, or multi-window scenes on top of the current `openDocument` slot is not a safe incremental change,
- making `path` or detail selection hold more editor routes does not by itself create multi-document support,
- the current `DocumentManager`/`EditorViewModel` pairing is not a shared pool of independent live editor controllers.

Future escape hatch:

Before multi-pane or multi-window work is safe, the architecture would need to revisit at least:

- `AppSession.openDocument` as the single app-wide document source of truth,
- `LiveDocumentManager`’s one-active-session ownership model,
- `EditorViewModel`’s single autosave / observation / conflict pipeline,
- restore and navigation policy that currently resolves one active editor destination,
- any UI-facing error ownership that still assumes one active editor surface.

Until that redesign happens, contributors should treat the app as intentionally single-document and keep new editor work inside that boundary.

### 5. Search and browser state still assume moderate workspace size

The snapshot/tree/search model is simple and testable, but not yet optimized for very large trees or richer search.
That is acceptable for the current product: whole-snapshot replacement keeps workspace application and reconciliation honest.
It is not the right permanent base for:

- very large workspaces where every refresh/search wants to touch the whole tree,
- incremental browser mutation UI that should avoid replacing the accepted snapshot wholesale,
- richer search behavior that would benefit from a derived index rather than repeated full-tree traversal.

Until that future work is intentionally designed, contributors should preserve the current snapshot model instead of layering ad hoc large-workspace optimizations into views.

---

## Contributor guardrails

These are the rules that future work should follow.

### Identity and filesystem safety

- Never derive file identity from `displayName`.
- Treat workspace-relative paths as the app’s canonical file identity.
- Do not assume lexical path prefix checks are enough for true workspace containment.
- Do not introduce new code paths that can follow redirected descendants without an explicit policy.

### Snapshot application

- Do not let random callers replace `session.workspaceSnapshot` without going through a clear winner policy.
- Refreshes, mutations, restore, and reconnect all need coherent application rules.

### Async work and cancellation

- Avoid new `Task.detached` usage for cancelable read-side work.
- The remaining detached write-side work is intentional and should stay narrowly documented rather than copied casually.
- If background work can outlive the user’s intent, it needs a clearly justified boundary and generation/cancellation behavior.

### UI boundaries

- Keep filesystem and persistence semantics out of views.
- View models may adapt state, but coordinator/manager boundaries should own cross-feature policy.

### Editor behavior

- Keep the in-memory editor buffer authoritative while the user types.
- Do not reintroduce noisy save conflicts for ordinary autosave.
- Keep save/revalidate behavior covered by tests whenever it changes.

### Product limits

- Assume one active workspace, one active document, and one active live document session unless the architecture docs are intentionally changed.
- Do not accidentally introduce folder-route navigation again; folder browsing is inline tree expansion now.

---

## Recommended target direction

This is not a rewrite plan.
It is the likely next evolution if the codebase keeps growing.

### Near-term target

Keep the current layer shape, but harden these seams:

- workspace containment,
- snapshot winner policy,
- cancellation-aware read I/O,
- scoped error ownership.

### Medium-term target

Extract smaller policy boundaries from `AppCoordinator`, likely around:

- workspace session/application rules,
- document presentation + restore rules,
- error routing.

### Longer-term target

Before major new features such as content search, multi-pane editing, or multiple remembered workspaces, the app will likely need:

- a more explicit workspace identity model,
- a more scalable browser/search state model than whole-snapshot replacement alone,
- a better search/indexing strategy,
- clearer document-presentation ownership than one global `openDocument`,
- a document-session ownership model that can support more than one live editor at a time.

Until then, the current architecture is good enough **if** its weak spots are made explicit and hardened.
