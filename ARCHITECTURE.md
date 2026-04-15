# ARCHITECTURE.md

## Overview

Downward is a SwiftUI-first, single-workspace markdown editor for iPhone and iPad.

The architecture is intentionally small:

- one shared `AppSession` holds UI-facing root state
- one `AppCoordinator` owns cross-feature orchestration
- one `WorkspaceManager` owns workspace restore, enumeration, and file mutations
- one `DocumentManager` owns open, save, reload, revalidate, and live observation for the active document
- feature view models adapt session and coordinator state into SwiftUI screens

The most important architectural rule is unchanged:

**the selected workspace folder is the source of truth, and the active editor saves directly back to that workspace file.**

---

## Current source tree

```text
Downward/
  App/
    AppContainer.swift
    AppCoordinator.swift
    AppSession.swift
    MarkdownWorkspaceApp.swift

  Domain/
    Document/
      DocumentConflict.swift
      DocumentConflictState.swift
      DocumentManager.swift
      DocumentSaveState.swift
      DocumentVersion.swift
      OpenDocument.swift
      PlainTextDocumentSession.swift
    Errors/
      AppError.swift
      ErrorReporter.swift
      UserFacingError.swift
    Persistence/
      BookmarkStore.swift
      SessionStore.swift
    Workspace/
      SupportedFileType.swift
      WorkspaceManager.swift
      WorkspaceNode.swift
      WorkspaceSnapshot.swift

  Features/
    Root/
      LaunchStateView.swift
      ReconnectWorkspaceView.swift
      RootScreen.swift
      RootViewModel.swift
    Workspace/
      WorkspaceFolderScreen.swift
      WorkspacePlaceholderDetailView.swift
      WorkspaceRowView.swift
      WorkspaceScreen.swift
      WorkspaceViewModel.swift
    Editor/
      ConflictResolutionView.swift
      EditorOverlayChrome.swift
      EditorScreen.swift
      EditorViewModel.swift
    Settings/
      SettingsScreen.swift

  Infrastructure/
    Logging/
      DebugLogger.swift
    Platform/
      FolderPickerBridge.swift
      LifecycleObserver.swift
      SecurityScopedAccess.swift
    WorkspaceEnumerator.swift

  Shared/
    Models/
      AppRoute.swift
      WorkspaceAccessState.swift
    PreviewSupport/
      PreviewSampleData.swift
```

---

## Composition root

### `AppContainer`

`AppContainer` is the composition root for the live app, previews, and most coordinator-level tests.

Responsibilities:

- create live infrastructure objects
- construct `AppSession`
- construct `AppCoordinator`
- construct feature view models
- provide preview wiring with lightweight stub managers

This is the only place the live dependency graph should be assembled.

---

## Root state and coordination

### `AppSession`

`AppSession` is the shared, main-actor state used by feature view models.

It currently owns:

- `launchState`
- `workspaceAccessState`
- `workspaceSnapshot`
- `openDocument`
- `editorLoadError`
- `path`
- `lastError`
- `hasBootstrapped`

`AppSession` is the single source of truth for what the UI should currently show.

### `AppCoordinator`

`AppCoordinator` owns app-wide behavior that spans multiple features.

Responsibilities:

- bootstrap workspace restore on launch
- restore the last open document when it is still safe
- coordinate folder-picker and reconnect flows
- refresh workspace snapshots and reconcile stale routes
- open, save, reload, revalidate, and observe the active document through `DocumentManager`
- persist and clear lightweight document-session state through `SessionStore`
- route create/rename/delete outcomes into coherent browser/editor/session state
- react to lifecycle changes such as foreground revalidation

Rules:

- views should not mutate workspace or document state directly
- managers should not own navigation or alert state
- stale async completions must be generation-guarded before they change `AppSession`

---

## Workspace domain

### `WorkspaceManager`

`WorkspaceManager` is the single boundary for workspace selection, restore, enumeration, and mutation.

Responsibilities:

- restore the selected workspace bookmark
- select a new workspace
- refresh the current workspace snapshot
- create, rename, and delete files within the workspace
- clear workspace selection

The live implementation is `LiveWorkspaceManager`, which depends on:

- `BookmarkStore`
- `SecurityScopedAccessHandling`
- `WorkspaceEnumerating`

### `WorkspaceSnapshot`

Immutable snapshot of the visible workspace tree.

Fields:

- `rootURL`
- `displayName`
- `rootNodes`
- `lastUpdated`

### `WorkspaceNode`

Canonical nested browser model for folders and files.

This is what workspace views render. The browser is intentionally not flattened.

### `SupportedFileType`

Single source of truth for supported editor file types.

Current support:

- `.md`
- `.markdown`
- `.txt`

### `WorkspaceEnumerator`

`LiveWorkspaceEnumerator` recursively walks the workspace and emits a filtered nested tree.

Current behavior:

- recurse into directories off the main actor
- keep only supported files
- keep ancestor folders that contain supported descendants
- sort folders before files
- sort names with localized standard comparison
- stay cancellable

---

## Document domain

### `OpenDocument`

`OpenDocument` is the in-memory representation of the current editor document.

Fields include:

- logical identity: `url`, `workspaceRootURL`, `relativePath`, `displayName`
- editor buffer: `text`
- last confirmed disk version: `loadedVersion`
- dirty state: `isDirty`
- save state: `saveState`
- conflict state: `conflictState`

### `DocumentVersion`

Represents the last confirmed on-disk state of a document.

Current fields:

- `contentModificationDate`
- `fileSize`
- `contentDigest`

This is used to distinguish real external changes from the app's own successful saves.

### `DocumentSaveState`

Current save-state enum:

- `idle`
- `unsaved`
- `saving`
- `saved(Date)`
- `failed(UserFacingError)`

### `DocumentConflictState`

Represents whether the current document needs explicit recovery.

States:

- `none`
- `needsResolution(DocumentConflict)`
- `preservingEdits(DocumentConflict)`

### `DocumentManager`

`DocumentManager` is the persistence boundary for active-document behavior.

Responsibilities:

- open a document from a workspace-relative path
- save the current document back to disk
- reload from disk when explicitly requested
- revalidate the on-disk state of the current document
- expose live change observation for the active document
- map file/provider issues into domain errors or recoverable conflict states

The live implementation is `LiveDocumentManager`.

### `PlainTextDocumentSession`

`PlainTextDocumentSession` is the coordinated live-session object used by `LiveDocumentManager` for the active document.

Responsibilities:

- perform coordinated open, save, reload, and revalidate work against the real workspace file
- keep the current editor buffer authoritative during ordinary autosave
- observe same-document external changes for the active editor session
- update confirmed on-disk version metadata after successful saves
- preserve UTF-8 plain-text semantics without silently normalizing line endings

Current external-change policy:

- matching disk metadata: keep the current document as-is
- disk now matches the current editor text: silently advance `loadedVersion`
- clean buffer plus safe external change: reload silently from disk
- dirty buffer plus external drift: keep the local buffer authoritative
- missing path or unrecoverable coordinated failure: move into explicit recovery UI

This policy is shared by live observation and foreground revalidation.

---

## Persistence model

### `BookmarkStore`

Stores the selected workspace bookmark and lightweight metadata.

Live implementation:

- `UserDefaultsBookmarkStore`

### `SessionStore`

Stores the minimal identity of the last open document.

Current payload:

- `relativePath`

Live implementation:

- `UserDefaultsSessionStore`

Important rule:

The app restores document identity, not document contents.

---

## Navigation and feature ownership

### Root feature

`RootViewModel` adapts `AppSession` into root launch and shell state.

`RootScreen` owns:

- no-workspace state
- restore-in-progress state
- reconnect-invalid-workspace state
- the ready workspace shell

Current navigation model:

- compact layouts use `NavigationStack`
- regular layouts use `NavigationSplitView`
- routes are stored as `[AppRoute]` in `AppSession`

### Workspace feature

`WorkspaceViewModel` owns browser-facing UI state such as refresh, prompts, and file-operation actions.

Workspace screens render:

- nested folder navigation
- file rows
- empty states
- folder-level create/rename/delete prompts

### Editor feature

`EditorViewModel` is the editor state machine.

Responsibilities:

- load the selected document when an editor route appears
- bind `TextEditor` into `AppSession.openDocument`
- mark edits dirty
- debounce autosave
- serialize saves
- merge save acknowledgements without clobbering newer edits
- drive conflict presentation and resolution actions
- flush pending saves on lifecycle boundaries

`EditorScreen` is intentionally minimal and uses standard SwiftUI navigation.

`EditorOverlayChrome` is failure-only chrome. Routine autosave remains visually quiet.

---

## Restore and mutation coherence

### Restore

Cold-launch restore happens in this order:

1. restore workspace bookmark
2. refresh workspace snapshot
3. restore last open document only if its saved relative path still resolves safely

If the document path is stale:

- keep the workspace open
- clear the stale restorable document session
- do not open a ghost editor

If the saved file still exists but can no longer be reopened safely, such as an unreadable non-UTF-8 file:

- keep the workspace open
- clear the stale restorable document session
- fall back to the browser calmly instead of retrying the broken editor restore forever

### Workspace mutation coherence

Create, rename, and delete flows must keep these in sync:

1. `workspaceSnapshot`
2. `openDocument`
3. `SessionStore`
4. `AppSession.path`

Examples:

- rename the open file: update document URL, relative path, display name, route, and restorable session
- delete the open file: clear editor state intentionally and remove stale editor routes
- nested-folder refresh: trim missing folder routes without flattening the tree

---

## Testing strategy

The repo currently relies on focused unit and smoke tests for the highest-risk behaviors.

Critical coverage areas:

- bookmark storage and restore failure handling
- session-store restore behavior
- workspace enumeration, filtering, and sorting
- workspace create/rename/delete behavior
- document open/save/revalidate semantics
- autosave debouncing and queued-save ordering
- true conflict/delete recovery paths
- restore/reconnect behavior
- browser/editor coherence under async races

When changing persistence or coordination logic, add targeted regression coverage first.

---

## Current known limitations

These are the main intentional limits of the current architecture:

- one workspace is active at a time
- one live document session is active at a time
- files are expected to be UTF-8 plain text
- in-app mutations cover files, not folder rename/move
- same-document external refresh is focused on the active editor session
- the app does not attempt to silently resolve every external move/rename; it falls back to explicit recovery when the saved relative path is no longer valid

When these limits change, update this document in the same change.
