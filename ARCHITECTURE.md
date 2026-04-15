# ARCHITECTURE.md

## Overview

Downward is a SwiftUI-first, single-workspace markdown editor. The architecture is intentionally small:

- one app session holds root UI state
- one coordinator orchestrates workspace, editor, and restore flows
- one workspace manager owns workspace selection, restore, enumeration, and file mutations
- one document manager owns open/reload/revalidate/save for text files
- feature view models adapt session/coordinator state into SwiftUI screens

The most important architectural rule is that **the active editor writes back to the real workspace file while preserving the calm autosave experience**.

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
    Errors/
      AppError.swift
      ErrorReporter.swift
      UserFacingError.swift
    Persistence/
      BookmarkStore.swift
      EditorAppearanceStore.swift
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
      WorkspaceScreen.swift
      WorkspaceFolderScreen.swift
      WorkspaceRowView.swift
      WorkspacePlaceholderDetailView.swift
      WorkspaceViewModel.swift
    Editor/
      ConflictResolutionView.swift
      EditorAppearancePreferences.swift
      EditorFontChoice.swift
      EditorFontResolver.swift
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

`AppContainer` is the composition root.

Responsibilities:

- create live services and platform adapters
- create the shared `AppSession`
- build `AppCoordinator`
- build feature view models
- provide preview wiring with stub services

This is the only obvious place where the live graph is assembled.

---

## Root state and coordination

### `AppSession`

`AppSession` is the shared in-memory state observed by feature view models.

It currently owns:

- `launchState`
- `workspaceAccessState`
- `workspaceSnapshot`
- `openDocument`
- `editorLoadError`
- `path`
- `lastError`
- `hasBootstrapped`

This object is UI-facing and stays on the main actor.

### `AppCoordinator`

`AppCoordinator` is the orchestration layer.

Responsibilities:

- bootstrap workspace restore on launch
- handle folder picker results
- refresh workspace snapshots
- load, save, reload, and revalidate the active document through `DocumentManager`
- update the open document text in session state
- persist the restorable document session
- route rename/delete/create results into coherent workspace and editor state
- handle foreground revalidation
- manage navigation-related side effects

Rules:

- Views should not call managers directly when the work affects app-wide state
- Cross-feature state transitions belong here, not in screens

---

## Workspace domain

### `WorkspaceManager`

`WorkspaceManager` is the single boundary for workspace selection and mutation.

Responsibilities:

- restore workspace bookmark access
- select a new workspace
- refresh the current workspace snapshot
- create, rename, and delete files within the workspace
- clear the workspace selection

The live implementation is `LiveWorkspaceManager`, which uses:

- `BookmarkStore`
- `SecurityScopedAccessHandling`
- `WorkspaceEnumerating`

### `WorkspaceSnapshot`

Immutable snapshot of the visible workspace tree.

Contains:

- `rootURL`
- `displayName`
- `rootNodes`
- `lastUpdated`

### `WorkspaceNode`

Canonical browser model for folders and files. This is what workspace screens render.

### `SupportedFileType`

Single source of truth for which file extensions the browser treats as editable.

### `WorkspaceEnumerator`

`LiveWorkspaceEnumerator` recursively walks the workspace and emits a filtered nested tree.

Current behavior:

- recurse into directories
- keep all real folders, including empty folders
- keep only supported files
- sort folders before files
- sort names using localized standard comparison

---

## Document domain

### `OpenDocument`

`OpenDocument` is the in-memory representation of the currently opened file.

Fields include:

- current file identity: `url`, `workspaceRootURL`, `relativePath`, `displayName`
- editor text: `text`
- last confirmed on-disk version: `loadedVersion`
- editor dirtiness: `isDirty`
- save UI state: `saveState`
- conflict UI state: `conflictState`

### `DocumentVersion`

Represents the last confirmed on-disk state of a document.

Current implementation tracks:

- `contentModificationDate`
- `fileSize`
- `contentDigest`

This is used for revalidation and conflict detection.

### `DocumentSaveState`

Current save-state enum:

- `idle`
- `unsaved`
- `saving`
- `saved(Date)`
- `failed(UserFacingError)`

### `DocumentConflictState`

Represents whether the current document is conflicted.

States:

- `none`
- `needsResolution(DocumentConflict)`
- `preservingEdits(DocumentConflict)`

### `DocumentManager`

`DocumentManager` is the persistence boundary for text files.

Responsibilities:

- open a document from a workspace-relative path
- reload the document from disk
- revalidate the on-disk version against the in-memory document
- save the current document back to disk
- map file-system issues into domain errors or conflict states

The live implementation is `LiveDocumentManager`.

### `PlainTextDocumentSession`

`PlainTextDocumentSession` is the coordinated live-document boundary for the currently open file.

Responsibilities:

- perform coordinated reads and writes against the real workspace file
- keep the current editor buffer authoritative during routine autosave
- observe external same-document changes with `NSFilePresenter`
- provide a low-frequency fallback revalidation signal for providers that do not emit reliable presenter callbacks

That fallback is intentionally best-effort and low-noise; it exists to improve real-device behavior with Files providers, not to create hard realtime background sync.

#### Important contract

Any future refactor of `DocumentManager` must preserve these invariants:

- the confirmed disk version is updated after successful saves
- revalidation must not self-conflict after the app's own saves
- save and reload must preserve logical document identity inside the workspace
- true external changes and missing-file cases must still surface clearly

---

## Persistence helpers

### `BookmarkStore`

Stores the selected workspace bookmark and lightweight metadata.

Live implementation:

- `UserDefaultsBookmarkStore`

### `SessionStore`

Stores the minimal identity of the last open document.

Current stored payload:

- `relativePath`

Live implementation:

- `UserDefaultsSessionStore`

This is deliberately lightweight. The app restores a document by identity, not by caching file contents.

### `EditorAppearanceStore`

Stores the editor font-family and font-size preferences in one owned place.

Responsibilities:

- load persisted editor appearance preferences
- normalize unavailable named fonts back to a safe default choice
- clamp font size into the supported editor range
- expose one current preferences value to settings and editor UI

The live implementation uses `UserDefaults` intentionally and keeps raw persistence out of views.

---

## Platform and infrastructure

### `SecurityScopedAccessHandling`

Central helper for:

- creating bookmarks
- resolving bookmarks
- validating access
- running operations against the workspace or descendants with scoped access

### `FolderPickerBridge`

Small platform adapter for folder-picking results. This keeps picker-specific handling out of the coordinator and views.

### `LifecycleObserver`

Tracks the latest `ScenePhase` so root features can react to active/background changes.

### `DebugLogger`

Small logging utility used for development and diagnostics.

---

## Feature layer

### Root feature

#### `RootViewModel`

Responsibilities:

- expose launch state to the root UI
- present the folder picker
- pass scene-phase changes to the coordinator/editor
- surface top-level alert state

#### `RootScreen`, `LaunchStateView`, `ReconnectWorkspaceView`

Render:

- first-run / no-workspace state
- restore-in-progress state
- reconnect-invalid-workspace state
- the ready workspace shell

### Workspace feature

#### `WorkspaceViewModel`

Responsibilities:

- expose the current snapshot to SwiftUI screens
- drive refresh state
- manage create/rename/delete prompts
- route file and settings actions through the coordinator
- preserve selection state based on app navigation

#### `WorkspaceScreen`, `WorkspaceFolderScreen`, `WorkspaceRowView`, `WorkspacePlaceholderDetailView`

Render the nested browser and empty/detail states.

### Editor feature

#### `EditorViewModel`

This is the most important feature-level state machine.

Responsibilities:

- load the selected document when an editor route appears
- bind `TextEditor` text into `AppSession.openDocument`
- mark edits dirty
- debounce autosave
- serialize saves so only one save is in flight at a time
- queue a follow-up save when the user types during a save
- merge save acknowledgements back into the current editor document without losing newer edits
- present conflict UI only when necessary
- flush pending saves on disappear/background

#### `EditorScreen`, `EditorOverlayChrome`, `ConflictResolutionView`

Render the editor, lightweight save/error chrome, and explicit conflict resolution UI.

### Settings feature

`SettingsScreen` is currently lightweight and scoped to app/workspace settings behavior.

---

## Navigation model

Navigation is represented by `[AppRoute]` in `AppSession`.

Current route roles include:

- workspace browsing
- editor routes keyed by file URL
- settings

The root view model forwards path changes back to the coordinator so app-wide cleanup can happen when routes disappear.

---

## Save and revalidation flow

This flow is the most sensitive part of the app.

### 1. Typing

- `EditorViewModel.handleTextChange(_:)` updates the open document text through `AppCoordinator.updateDocumentText(_:)`
- the document becomes dirty and save state becomes `.unsaved`
- autosave is scheduled with a debounce

### 2. Autosave request

- if no save is in flight, `EditorViewModel.startSave(for:)` snapshots the current `OpenDocument`
- save state is set to `.saving`
- the snapshot is sent to `AppCoordinator.saveDocument(_:)`

### 3. Document save

- `AppCoordinator` forwards the request to `DocumentManager`
- on success, the coordinator persists the restorable document session
- the result comes back to `EditorViewModel`

### 4. Save acknowledgement merge

`EditorViewModel.applySaveResult(...)` must merge a save result into the current editor state.

Key rule:

- if the user typed again while a save was in flight, the save acknowledgement must still refresh `loadedVersion` and file identity metadata without clobbering the newer text

This is what prevents the app from treating its own earlier save as a later external modification.

### 5. Foreground revalidation

- when the app becomes active, `AppCoordinator.handleSceneDidBecomeActive()` refreshes the workspace snapshot
- if a document is open and not actively saving, `DocumentManager.revalidateDocument(_:)` checks the current on-disk version
- if the document is still consistent, session state is quietly updated
- if the document is missing or truly changed externally, conflict state is set

---

## Conflict model

The product requirement is now:

- **routine typing should not trigger repeated conflict UI**
- conflict UI is for exceptional cases

Current conflict kinds:

- `modifiedOnDisk`
- `missingOnDisk`

Resolution actions currently supported by the editor feature:

- reload from disk
- overwrite disk
- preserve local edits in memory for now

Future work must keep these paths coherent without making the normal autosave path noisy.

---

## Workspace mutation coherence

File mutations can affect both the browser and the open editor.

Any create/rename/delete flow must keep these three things in sync:

1. `workspaceSnapshot`
2. `openDocument`
3. restorable document session metadata

Examples:

- rename the open file: update the open document identity and stored restorable session
- delete the open file: clear or conflict the editor state intentionally
- create a file: refresh the snapshot and optionally route into the new editor later if designed

---

## Preview and test strategy

### Preview support

Use `Shared/PreviewSupport/PreviewSampleData.swift` as the central sample-data source for UI previews.

### Tests

The repo already includes coverage for key persistence behavior, including:

- bookmark store
- session store
- workspace enumeration
- workspace restore/mutation behavior
- autosave sequencing
- conflict handling
- smoke-level app coordinator flows

When changing save or conflict behavior, prefer adding targeted regression tests instead of relying only on manual testing.

---

## Rules for future changes

When making changes, do not:

- reintroduce older `WorkspaceService` / `DocumentService` naming
- move file-system work into Views
- bypass the coordinator for app-wide transitions
- regress autosave into repeated self-conflict prompts
- replace the user-selected workspace with an app-owned mirror
- broaden the architecture without updating this document

When adding a new subsystem, update this file in the same change.
