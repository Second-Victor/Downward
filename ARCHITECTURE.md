# ARCHITECTURE.md

## Purpose

This document describes the **current architecture as it exists now**.
It is a map of the shipping shape, not a rewrite plan.

Downward is a SwiftUI iPhone/iPad app that edits real files inside one user-selected workspace folder from Files.

---

## Top-level layout

The codebase is organized into these layers:

- `App/`
  - app composition, session state, orchestration, navigation/session policy
- `Domain/`
  - workspace, document, persistence, and error rules
- `Infrastructure/`
  - bookmark, security-scope, enumeration, platform, and logging bridges
- `Features/`
  - SwiftUI screens, feature-specific presentation, and editor rendering
- `Shared/`
  - shared models and preview support
- `Tests/`
  - unit and smoke-style coverage for risky flows

This is a **SwiftUI-first app** with narrow UIKit boundaries where SwiftUI still does not provide the right behavior.

---

## Runtime model

### 1. One active workspace

The app works against one selected workspace folder at a time.

That state is represented by:

- `AppSession.launchState`
- `AppSession.workspaceAccessState`
- `AppSession.workspaceSnapshot`
- bookmark-backed restore data in `BookmarkStore`

`WorkspaceManager` owns selection, restore, refresh, and file mutations.
It is the boundary between UI orchestration and the real Files workspace.

### 2. One active live document session

The app currently assumes **one active live document session**.

`LiveDocumentManager` owns that policy and maps one active workspace-relative document key to one active `PlainTextDocumentSession`.

This matters because:

- save and revalidation logic assume one live session,
- change observation is wired around the currently open document,
- multi-pane or multi-window editing would require a design pass first.

### 3. Workspace-relative identity is canonical

The app uses **workspace-relative path identity** as the preferred identity for browser, search, restore, and recent-file flows.

Important types:

- `WorkspaceRelativePath`
- `WorkspaceSnapshot`
- `WorkspaceSnapshotPathResolver`
- `RecentFileItem`

Rules:

- if the UI already knows a trusted relative path, keep using it,
- final file access must still validate against the chosen workspace root,
- raw URL-only opens are fallback paths, not the preferred browser model.

---

## App layer

### `AppSession`

`AppSession` is the app-wide UI state container.
It holds:

- launch and access state,
- the current workspace snapshot,
- current route/navigation state,
- the open document,
- user-facing alerts and workspace alerts,
- recent-file and settings presentation state.

It should stay declarative and lightweight.
It is not the place for file-system rules.

### `AppCoordinator`

`AppCoordinator` is the main orchestrator.
It coordinates:

- bootstrap and restore,
- reconnect and workspace replacement,
- open/reopen flows,
- workspace refresh application,
- mutation reconciliation,
- handoff between workspace state and editor state,
- route changes for compact and regular navigation.

It is intentionally still the orchestration hub, but it should not become the architecture again.
Prefer extracting policy before adding new inline rules.

### Policy seams

The current policy seams are:

- `WorkspaceNavigationPolicy`
- `WorkspaceSessionPolicy`

Use them before expanding coordinator logic.

---

## Domain layer

### Workspace domain

Main ownership sits in:

- `WorkspaceManager`
- `WorkspaceSnapshot`
- `WorkspaceNode`
- `WorkspaceRelativePath`

Responsibilities:

- restore/select/refresh workspace,
- validate in-root access,
- enumerate files and folders,
- create/rename/delete files,
- keep browser-visible identity aligned with the chosen workspace.

### Document domain

Main ownership sits in:

- `DocumentManager`
- `PlainTextDocumentSession`
- `OpenDocument`
- `DocumentVersion`
- `DocumentConflictState`

Responsibilities:

- open text documents,
- reload and revalidate the active document,
- autosave and conflict handling,
- observe active-file changes,
- relocate the live session after in-app rename.

`PlainTextDocumentSession` is dense but important. Keep non-session editor features out of it.

### Persistence domain

Main ownership sits in:

- `BookmarkStore`
- `SessionStore`
- `RecentFilesStore`
- `EditorAppearanceStore`

Persisted state is intentionally lightweight:

- workspace bookmark data,
- last-open session metadata,
- recent files,
- editor appearance preferences.

The app does **not** persist a mirrored copy of workspace file contents as the primary editing model.

---

## Editor architecture

The current editor stack is:

- `EditorScreen`
- `EditorViewModel`
- `MarkdownEditorTextView`
- `MarkdownStyledTextRenderer`
- `MarkdownCodeBackgroundLayoutManager`

Important realities:

- the shipping editor is a SwiftUI-hosted `UITextView`,
- markdown syntax display is a presentation layer concern,
- editor appearance is driven by `EditorAppearanceStore`,
- the document session remains responsible for file truth, not rich editor UI.

The editor currently has a sensitive layout boundary around top chrome, safe areas, and the first visible line.
Treat that as real product behavior, not cosmetic trivia.
Any change there needs real-device verification on iPhone and iPad.

---

## Browser, search, and recents

### Browser

The workspace browser is snapshot-driven.
The UI renders from `WorkspaceSnapshot` and related presentation helpers.

### Search

Search filters the current in-memory snapshot.
It is intentionally simple:

- filename and path matching,
- no content indexing,
- no separate search database.

### Recents

Recents are stored by workspace identity plus workspace-relative path.
They should remain aligned with the same identity model as browser/search opens.

---

## Trust model

The chosen workspace root is the trust boundary.

Rules:

- final reads, writes, rename, and delete operations must validate access under the chosen workspace,
- redirected descendants must not quietly re-enter the editing pipeline,
- enumeration and mutation logic must agree on containment policy,
- route identity should not be allowed to bypass file-system validation.

---

## Concurrency model

### Main actor

UI-facing state and feature view models remain main-actor oriented.

### Background work

Enumeration, bookmark resolution, reads, writes, and version/digest work should not block the main actor.

### Generation-sensitive flows

Refresh, restore, file-open, and mutation application paths use explicit generation or winner policies where newer state could race older async completions.

---

## Current pressure points

These are the main code hotspots to protect:

- `AppCoordinator.swift`
- `PlainTextDocumentSession.swift`
- `MarkdownStyledTextRenderer.swift`
- `WorkspaceManager.swift`
- `MarkdownWorkspaceAppSmokeTests.swift`

Large files are acceptable when they still represent a real boundary.
They are not acceptable as a dumping ground for new unrelated work.

---

## Current scale limits

The app is intentionally still built around:

- one selected workspace,
- one whole `WorkspaceSnapshot`,
- one active live document session,
- simple filename/path search,
- whole-snapshot refresh and mutation reconciliation.

That model is valid today.
A real design pass should happen before adding:

- content search,
- very large workspace optimizations,
- multi-pane or multi-window editing,
- multiple concurrent live document sessions,
- background sync features.

---

## Contributor guidance

When adding new work:

- extend policy seams before growing `AppCoordinator`,
- keep file truth in the document/workspace layers,
- keep editor UI behavior in the editor feature layer,
- keep settings additions in `EditorAppearanceStore` and the settings feature,
- update tests and docs when the contract changes.
