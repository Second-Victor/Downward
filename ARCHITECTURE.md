# ARCHITECTURE.md

## Overview

`MarkdownWorkspace` is a SwiftUI-only, folder-based markdown editor for iPhone and iPad.

The app works with **one user-selected workspace folder at a time**. The user chooses a folder from Files. The app stores bookmark data for that folder, restores access on later launches, recursively discovers nested markdown files, and opens one document at a time for plain-text editing.

The architecture is optimized for:

- reliable workspace restore
- safe access to user-selected folders outside the sandbox
- nested folder browsing without flattening the file tree
- predictable save behavior
- strict separation between UI, state, and file I/O
- SwiftUI previews with stable sample data
- testable logic in services and view models
- a native SwiftUI editor experience built on standard navigation

---

## Architectural goals

### Product goals

- represent the real folder hierarchy
- keep the editor minimal
- make save behavior trustworthy
- stay small enough to build and reason about

### Engineering goals

- isolate file system access from UI
- keep async work cancellable
- reject stale async results
- serialize save operations per document
- make preview and test data easy to reuse
- keep file responsibilities obvious from their names

---

## Core architecture rules

1. **One workspace root at a time**
2. **One authoritative workspace snapshot at a time**
3. **One open document at a time for MVP**
4. **One serialized save pipeline per open document**
5. **Views never touch `FileManager` directly**
6. **View models never perform raw disk I/O directly**
7. **Services own reads, writes, moves, deletes, and metadata checks**
8. **Successful autosave may remain visually quiet**
9. **Save failures and conflicts must always be visible**
10. **SwiftUI previews are required for every UI view**
11. **Sample data is centralized instead of scattered**
12. **Prefer standard SwiftUI navigation over custom editor chrome**

---

## High-level layers

### 1. App layer

Owns bootstrap, dependency assembly, and top-level state transitions.

Responsibilities:

- create services once
- restore workspace on launch
- decide which root screen to show
- coordinate transitions between picker, browser, editor, and reconnect states

### 2. Feature / presentation layer

Owns SwiftUI screens, view models, and feature-local state rendering.

Responsibilities:

- render UI
- accept user interactions
- call app or service actions
- expose loading, empty, error, save-failure, and conflict states
- provide previews for each UI file

### 3. Domain layer

Owns small app-specific models that describe the workspace and documents.

Responsibilities:

- define stable workspace tree types
- define document version and save-state types
- define error and recovery models
- keep feature logic readable and testable

### 4. Service layer

Owns business logic and all file-related side effects.

Responsibilities:

- select and restore workspace
- enumerate folders
- read file text
- save file text
- create/rename/delete items
- detect conflicts
- persist bookmark and lightweight session state

### 5. Preview and test support layer

Owns fake services and sample data shared by previews and tests.

Responsibilities:

- generate realistic nested folder trees
- generate realistic document states
- make UI previews independent from real file access

---

## Recommended folder structure

```text
MarkdownWorkspace/
  App/
    MarkdownWorkspaceApp.swift
    AppContainer.swift
    AppModel.swift
    RootScreen.swift

  Features/
    WorkspacePicker/
      WorkspacePickerScreen.swift
      ReconnectWorkspaceScreen.swift
      WorkspacePickerViewModel.swift

    Browser/
      WorkspaceBrowserScreen.swift
      FolderContentsScreen.swift
      WorkspaceNodeRow.swift
      WorkspaceEmptyStateView.swift
      WorkspaceBrowserViewModel.swift
      FileActionSheetModel.swift

    Editor/
      DocumentEditorScreen.swift
      ConflictResolutionView.swift
      DocumentEditorViewModel.swift

    Settings/
      SettingsScreen.swift

  Domain/
    Workspace/
      WorkspaceNode.swift
      WorkspaceFolder.swift
      WorkspaceFile.swift
      WorkspaceSnapshot.swift
      SupportedFileType.swift

    Document/
      OpenDocument.swift
      DocumentVersion.swift
      DocumentSaveState.swift
      DocumentConflictState.swift

    Common/
      AppError.swift
      UserFacingError.swift
      AsyncLoadState.swift

  Services/
    WorkspaceService.swift
    DocumentService.swift
    BookmarkStore.swift
    SessionStore.swift
    AutosaveScheduler.swift

  Infrastructure/
    SecurityScopedAccess.swift
    WorkspaceEnumerator.swift
    FileCoordinatorClient.swift
    FileMetadataReader.swift
    TextFileCodec.swift
    AtomicFileWriter.swift
    Logger.swift

  PreviewSupport/
    PreviewSampleData.swift
    PreviewServices.swift
    PreviewViewModels.swift

  MarkdownWorkspaceTests/
    BookmarkStoreTests.swift
    WorkspaceEnumeratorTests.swift
    WorkspaceServiceTests.swift
    DocumentServiceTests.swift
    AutosaveSchedulerTests.swift
    DocumentEditorViewModelTests.swift

  MarkdownWorkspaceUITests/
    AppLaunchUITests.swift
    WorkspaceFlowUITests.swift
    EditorFlowUITests.swift
```

This structure is deliberately small. It is enough for a clean MVP without turning the project into a framework zoo.

---

## File-by-file responsibilities

### App/

#### `MarkdownWorkspaceApp.swift`

**Responsibility:** App entry point.

This file should do only app-level setup:

- create the root `WindowGroup`
- create `AppContainer`
- create `AppModel`
- show `RootScreen`

It should not contain:

- bookmark logic
- workspace enumeration logic
- document save logic

#### `AppContainer.swift`

**Responsibility:** Dependency composition root.

This file builds the shared services used by the app:

- `BookmarkStore`
- `SessionStore`
- `WorkspaceService`
- `DocumentService`
- `Logger`

It keeps service creation in one place so the project has one obvious dependency graph.

#### `AppModel.swift`

**Responsibility:** Top-level observable app state.

This is the app’s primary state owner. It should be `@Observable` and `@MainActor`.

It owns:

- root screen state
- selected workspace identity
- selected file identity
- presentation of reconnect state
- cross-feature user-facing errors when needed

Typical responsibilities:

- bootstrap on launch
- restore workspace
- clear workspace
- transition into editor
- close editor
- request workspace refresh after file mutations

#### `RootScreen.swift`

**Responsibility:** Decide which top-level screen the user sees.

This screen switches between:

- workspace picker
- restoring view
- reconnect workspace screen
- browser screen
- editor screen if the navigation path presents it

This file should remain visually simple and delegate state to `AppModel`.

---

### Features/WorkspacePicker/

#### `WorkspacePickerScreen.swift`

**Responsibility:** First-run and no-workspace UI.

This view explains what the app does and provides the **Open Folder** action.

It owns only UI presentation:

- instructional text
- open-folder button
- optional small note about supported file types

It should use `.fileImporter` with folder selection configuration.

Required previews:

- first launch
- already has recoverable workspace disabled state if desired

#### `ReconnectWorkspaceScreen.swift`

**Responsibility:** Recovery UI when bookmark restore fails.

This screen explains that the previous folder is no longer accessible and offers clear actions:

- reconnect folder
- choose a different folder
- clear stored workspace

Required previews:

- stale bookmark state
- permission-lost copy
- generic restore failure copy

#### `WorkspacePickerViewModel.swift`

**Responsibility:** Handle folder selection result and recovery actions.

This view model should:

- present/import folder selection result handling
- call `WorkspaceService.selectWorkspace`
- report restore failures
- update `AppModel`

This file must not enumerate the workspace directly.

---

### Features/Browser/

#### `WorkspaceBrowserScreen.swift`

**Responsibility:** Host the workspace browser at the root folder level.

This screen should render:

- workspace name
- current top-level folder contents
- refresh affordance
- create-file action
- settings entry point

It reads state from `WorkspaceBrowserViewModel`.

Required previews:

- loading
- loaded workspace
- empty workspace
- error state

#### `FolderContentsScreen.swift`

**Responsibility:** Render one folder level.

This view takes a `WorkspaceFolder` or folder identifier and shows its children.

It should:

- list folders first
- push deeper folders with `NavigationLink`
- open files through a callback or selection action
- expose rename/delete/create actions for the current folder or child items

Required previews:

- populated folder
- empty folder
- mixed nested content

#### `WorkspaceNodeRow.swift`

**Responsibility:** Render one file-system row.

This row distinguishes:

- folder rows
- markdown file rows

It should show:

- name
- optional metadata such as modified date for files if used
- folder/file icon
- accessible labels

Required previews:

- folder row
- markdown file row
- long-name row

#### `WorkspaceEmptyStateView.swift`

**Responsibility:** Shared empty-state UI for the browser.

This view is used when:

- workspace has no supported files
- current folder has no visible children after filtering

It should stay focused and reusable.

Required previews:

- empty workspace copy
- empty folder copy

#### `WorkspaceBrowserViewModel.swift`

**Responsibility:** Own browser state and browser actions.

This view model should be `@Observable` and `@MainActor`.

It owns:

- current workspace snapshot
- loading state
- error state
- refresh task identity
- file action presentation state
- create/rename/delete operation state if presented from the browser

It calls `WorkspaceService` for all mutations and refreshes.

Important behavior:

- cancels or supersedes old refresh tasks
- never traverses the file system directly
- never mutates the snapshot from a stale task result

#### `FileActionSheetModel.swift`

**Responsibility:** Small domain helper for browser actions.

This file can define a lightweight model for file actions shown in menus, dialogs, or confirmation prompts.

Keep it small. It exists only if it keeps browser presentation state clearer.

---

### Features/Editor/

#### `DocumentEditorScreen.swift`

**Responsibility:** Host the editor experience for one open document.

This screen should contain:

- `TextEditor`
- standard navigation title
- standard system back behavior from the surrounding navigation stack
- conflict prompt presentation
- save failure presentation

It should not perform save logic itself.

Required previews:

- clean document
- loading document
- failed save document
- conflict document

#### `ConflictResolutionView.swift`

**Responsibility:** Explain save conflict choices.

This can be a small reusable view for the content of a sheet or dialog.

It should present the options clearly:

- reload from disk
- overwrite with current edits
- cancel and keep editing

Required previews:

- generic conflict
- file deleted conflict if supported

#### `DocumentEditorViewModel.swift`

**Responsibility:** Own document lifecycle, editing state, and save actions.

This view model should be `@Observable` and `@MainActor`.

It owns:

- open document
- text buffer
- dirty state
- save state
- conflict state
- pending back-navigation intent if unresolved
- immediate UI actions such as retry save or resolve conflict

It collaborates with `DocumentService` and `AutosaveScheduler`.

Important behavior:

- marks unsaved internally on edit
- schedules debounced save
- may keep successful saves visually quiet
- does not silently dismiss on failed save or conflict

---

### Features/Settings/

#### `SettingsScreen.swift`

**Responsibility:** Tiny settings/info surface.

This screen should stay small during MVP.

It may include:

- current workspace path summary
- reconnect workspace
- clear workspace
- app version
- supported file types info

Required previews:

- workspace loaded
- no workspace

---

### Domain/Workspace/

#### `WorkspaceNode.swift`

**Responsibility:** Canonical tree node type.

This file defines the enum for browser tree rendering, for example:

- `.folder(WorkspaceFolder)`
- `.file(WorkspaceFile)`

This is the core type that lets the UI represent the workspace hierarchy without live file traversal.

#### `WorkspaceFolder.swift`

**Responsibility:** Folder model used by the browser.

Recommended fields:

- stable `id`
- folder `url`
- `name`
- `children`
- optional `relativePath` from workspace root

This model should be immutable inside a snapshot.

#### `WorkspaceFile.swift`

**Responsibility:** File model used by the browser and editor launch.

Recommended fields:

- stable `id`
- file `url`
- `name`
- `fileExtension`
- `relativePath`
- `modifiedAt`
- `size`

This model should contain enough metadata for display and selection.

#### `WorkspaceSnapshot.swift`

**Responsibility:** Immutable browser snapshot.

Recommended fields:

- workspace root URL
- workspace display name
- root folder model
- timestamp of generation

The browser renders from this value instead of from ongoing live file traversal.

#### `SupportedFileType.swift`

**Responsibility:** Central file filter policy.

This file defines:

- allowed extensions
- file-type display names if needed
- helper methods like `isSupportedMarkdownFile(url:)`

Do not scatter file-extension rules across multiple views and services.

---

### Domain/Document/

#### `OpenDocument.swift`

**Responsibility:** The in-memory state of the currently open document.

Recommended fields:

- file URL
- display name
- text
- loaded version
- save state
- conflict state
- last successful save date if useful

This is the editor’s authoritative model, owned by the editor view model.

#### `DocumentVersion.swift`

**Responsibility:** Metadata used for conflict detection.

Recommended fields:

- modification date
- file size
- optional content hash
- optional existence flag or file identifier if useful

This should stay practical. It does not need to model every possible file-system detail.

#### `DocumentSaveState.swift`

**Responsibility:** Internal save pipeline state.

Recommended cases:

- idle
- unsaved
- saving
- saved(Date)
- failed(UserFacingError)

This type exists to drive logic and selective user-facing messaging. It does not require a persistent visual indicator in normal successful editing.

#### `DocumentConflictState.swift`

**Responsibility:** Describe why a conflict happened and what should be shown.

Recommended information:

- current disk version
- originally loaded version
- whether the file was deleted or modified
- user-facing message

This type should be UI-ready enough that the conflict screen can render it directly.

---

### Domain/Common/

#### `AppError.swift`

**Responsibility:** Internal error categorization.

This enum can describe lower-level failures such as:

- bookmark restore failed
- workspace access lost
- file not found
- permission denied
- provider unavailable
- conflict detected
- save failed

It is primarily for services and mapping logic.

#### `UserFacingError.swift`

**Responsibility:** Small UI-safe error model.

Recommended fields:

- title
- message
- recovery suggestion
- optional debug identifier in debug builds only

Views present this model instead of raw system errors.

#### `AsyncLoadState.swift`

**Responsibility:** Shared loading-state utility.

This file can define a small generic enum for:

- idle
- loading
- loaded
- failed

Use it only if it keeps multiple feature view models simpler. Do not over-generalize.

---

### Services/

#### `WorkspaceService.swift`

**Responsibility:** High-level workspace operations.

This is one of the most important files in the app.

It should own:

- selecting a workspace from a URL
- creating bookmark data
- restoring a saved workspace
- refreshing the workspace snapshot
- creating files
- renaming items
- deleting items

It should collaborate with:

- `BookmarkStore`
- `WorkspaceEnumerator`
- `SecurityScopedAccess`
- `FileCoordinatorClient`
- `FileMetadataReader`

Typical methods:

- `selectWorkspace(at:)`
- `restoreWorkspace()`
- `refreshWorkspace()`
- `createMarkdownFile(named:in:)`
- `renameItem(at:to:)`
- `deleteItem(at:)`
- `clearWorkspace()`

This service should hide the complexity of security-scoped access from the rest of the app.

#### `DocumentService.swift`

**Responsibility:** High-level document open/save logic.

This is the second most important file in the app.

It should own:

- open file text
- create `OpenDocument`
- read current disk metadata
- save with conflict check
- reload from disk
- overwrite when explicitly allowed

It should collaborate with:

- `SecurityScopedAccess`
- `FileCoordinatorClient`
- `TextFileCodec`
- `AtomicFileWriter`
- `FileMetadataReader`

Typical methods:

- `openDocument(at:)`
- `saveDocument(text:for:loadedVersion:overwriteIfConflicted:)`
- `reloadDocument(at:)`
- `readCurrentVersion(at:)`

This service must serialize writes for a document and keep save behavior authoritative.

#### `BookmarkStore.swift`

**Responsibility:** Persist and restore bookmark data only.

This file should stay very focused.

Recommended responsibilities:

- save bookmark `Data`
- load bookmark `Data`
- clear bookmark `Data`

It should not perform enumeration or editor logic.

A `UserDefaults`-backed implementation is enough for MVP.

#### `SessionStore.swift`

**Responsibility:** Persist tiny session state.

This can hold:

- last opened file relative path
- maybe last selected folder relative path if useful
- maybe last successful workspace name cache for display

Do not use it as a second persistence system for documents.

#### `AutosaveScheduler.swift`

**Responsibility:** Debounce edit events and request saves.

This file should:

- receive “document changed” signals
- cancel prior pending save tasks
- wait for the debounce interval
- ask `DocumentEditorViewModel` or `DocumentService` to save the latest snapshot
- support immediate flush on disappear or background

Keep it tiny and deterministic so it is easy to unit test.

---

### Infrastructure/

#### `SecurityScopedAccess.swift`

**Responsibility:** Centralize security-scoped access handling.

This file should expose a helper like:

- start access
- run operation
- stop access in `defer`

It prevents duplicated access code from spreading across services.

#### `WorkspaceEnumerator.swift`

**Responsibility:** Recursively walk the workspace and build a snapshot tree.

This file should:

- enumerate descendants
- collect folders and supported files
- exclude hidden/system noise
- keep folders that contain supported descendants
- sort folders before files
- build the immutable tree models

This is a pure or near-pure file-system mapping file and should be heavily unit tested.

#### `FileCoordinatorClient.swift`

**Responsibility:** Small wrapper around coordinated file access.

This wrapper makes it easier to:

- coordinate reads
- coordinate writes
- fake coordination in tests if needed

Keep the wrapper narrow. It exists for safety and test seams, not for abstraction theater.

#### `FileMetadataReader.swift`

**Responsibility:** Read file resource values needed by the app.

This file should centralize metadata reads such as:

- modification date
- file size
- directory flag
- hidden flag
- existence check if needed

This prevents metadata logic from spreading.

#### `TextFileCodec.swift`

**Responsibility:** Decode and encode file text.

Recommended behavior:

- default to UTF-8
- fail with a clear error if decoding is unsupported
- keep encoding logic consistent across open/save

This file keeps text conversion decisions in one place.

#### `AtomicFileWriter.swift`

**Responsibility:** Write text data safely.

This file should implement the actual write strategy used by `DocumentService`.

Responsibilities:

- write new data atomically or through a temp-and-replace strategy
- surface useful errors
- avoid partial writes where practical

#### `Logger.swift`

**Responsibility:** Lightweight debug logging.

This file can be extremely small.

Use it to log:

- workspace restore attempts
- enumeration failures
- save attempts and save failures
- conflict detection events

Do not let logging become a dependency-heavy subsystem.

---

### PreviewSupport/

#### `PreviewSampleData.swift`

**Responsibility:** Central source of realistic preview models.

This file should provide:

- sample workspace snapshot
- sample folders
- sample files
- sample clean document
- sample failed-save document
- sample conflict state
- sample user-facing errors

This file is critical because it keeps previews consistent across the whole app.

#### `PreviewServices.swift`

**Responsibility:** Fake service implementations for previews.

This file should provide in-memory or no-op versions of:

- workspace service
- document service
- bookmark store if needed

These fakes should make previews compile without real file access.

#### `PreviewViewModels.swift`

**Responsibility:** Convenience factories for preview-ready view models.

This file can create view models already loaded into interesting states, such as:

- browser loading
- browser loaded
- browser error
- editor clean
- editor failed save
- editor conflict

This keeps preview code inside UI files short and readable.

---

### Tests/

#### `BookmarkStoreTests.swift`

**Responsibility:** Verify bookmark persistence behavior.

Test:

- save bookmark
- load bookmark
- clear bookmark
- missing bookmark behavior

#### `WorkspaceEnumeratorTests.swift`

**Responsibility:** Verify directory tree mapping and filtering.

Test:

- supported file filtering
- hidden-file skipping
- folders retained only when needed
- sort order
- nested tree shape

#### `WorkspaceServiceTests.swift`

**Responsibility:** Verify workspace-level operations.

Test:

- select workspace
- restore workspace
- refresh workspace
- create file
- rename item
- delete item
- restore failure mapping

#### `DocumentServiceTests.swift`

**Responsibility:** Verify document open/save/conflict behavior.

Test:

- open file
- save clean edit
- save dirty edit
- conflict detection
- file deleted while open
- overwrite flow when explicitly allowed

#### `AutosaveSchedulerTests.swift`

**Responsibility:** Verify debounce and flush semantics.

Test:

- repeated edits coalesce
- pending save cancels when replaced
- flush triggers immediate save
- no save after cancellation unless rescheduled

#### `DocumentEditorViewModelTests.swift`

**Responsibility:** Verify editor state transitions.

Test:

- dirty flag changes
- save state transitions
- back-navigation safeguard
- conflict presentation
- retry after save failure

#### `AppLaunchUITests.swift`

**Responsibility:** Verify first-run and restore entry flows.

#### `WorkspaceFlowUITests.swift`

**Responsibility:** Verify folder browsing and file actions.

#### `EditorFlowUITests.swift`

**Responsibility:** Verify open/edit/save/conflict UI behavior.

---

## App state design

## Root app state

Use a small root state model, for example:

```swift
enum RootState: Equatable {
    case launching
    case noWorkspace
    case reconnectRequired(UserFacingError)
    case workspaceReady
}
```

`AppModel` owns this state.

Why this matters:

- root UI becomes predictable
- launch behavior is easy to test
- reconnect is explicit rather than hidden in a generic error path

---

## Browser state design

`WorkspaceBrowserViewModel` should own something close to:

```swift
struct WorkspaceBrowserState {
    var loadState: AsyncLoadState<WorkspaceSnapshot>
    var isRefreshing: Bool
    var pendingActionURL: URL?
    var presentedError: UserFacingError?
}
```

Use whatever shape reads best in code. The important part is that the browser renders from a snapshot, not a mutable live traversal.

---

## Editor state design

Recommended `OpenDocument` shape:

```swift
struct OpenDocument: Equatable {
    let url: URL
    let displayName: String
    var text: String
    var loadedVersion: DocumentVersion
    var saveState: DocumentSaveState
    var conflictState: DocumentConflictState?
}
```

Derived values can be computed by the view model:

- `isDirty`
- `canDismissSafely`

Recommended save-state semantics:

- `.idle` — loaded and clean, no unsaved edits
- `.unsaved` — local buffer differs from disk
- `.saving` — save in progress
- `.saved(Date)` — last save succeeded
- `.failed(UserFacingError)` — save failed

Important rule:

**Successful saves do not require a persistent visual indicator. Failures and conflicts do.**

---

## Data flow

### Folder selection flow

1. `WorkspacePickerScreen` presents folder importer.
2. User selects folder URL.
3. `WorkspacePickerViewModel` forwards URL to `AppModel`.
4. `AppModel` asks `WorkspaceService.selectWorkspace`.
5. `WorkspaceService`:
   - validates access
   - creates bookmark data
   - stores bookmark
   - enumerates workspace
   - returns snapshot
6. `AppModel` updates root state to workspace ready.
7. `WorkspaceBrowserViewModel` renders the snapshot.

### Document open flow

1. User taps file row.
2. `WorkspaceBrowserViewModel` informs `AppModel`.
3. `AppModel` creates `DocumentEditorViewModel`.
4. `DocumentEditorViewModel` asks `DocumentService.openDocument`.
5. `DocumentService` reads text and metadata.
6. `DocumentEditorViewModel` stores `OpenDocument`.
7. `DocumentEditorScreen` renders editor state.

### Edit and save flow

1. User types in `TextEditor`.
2. `DocumentEditorViewModel.updateText(_:)` runs.
3. View model updates in-memory text.
4. View model marks save state as unsaved internally.
5. `AutosaveScheduler` schedules a save.
6. Debounce fires.
7. `DocumentService.saveDocument` runs.
8. Service re-reads current disk version.
9. If version changed, service returns conflict.
10. If version did not change, service coordinates write.
11. On success, view model updates loaded version and save state.
12. On failure, view model stores a user-facing error in save state and the UI surfaces it clearly.

---

## Workspace enumeration design

### Enumeration rules

The enumerator should:

- start from the workspace root
- recursively walk descendants
- gather folder structure and supported files
- skip hidden files and folders
- skip unsupported files
- preserve folder nodes that lead to supported descendants
- sort folders before files
- sort visible names predictably

### Why a snapshot model is important

A snapshot model gives the UI:

- stable identity for lists
- easy diffing and refresh behavior
- simpler previews
- easier test fixtures
- less risk of unexpected file access during rendering

### Recommended sort policy

For user-visible names:

1. folders first
2. files second
3. within each group, localized standard comparison by name

### Recommended support policy

Support by extension for MVP:

- `md`
- `markdown`
- `txt` if enabled

Keep this policy centralized in `SupportedFileType.swift`.

---

## Save and conflict design

### Save pipeline steps

When saving, `DocumentService` should:

1. capture the latest text snapshot provided by the editor view model
2. read current metadata for the file on disk
3. compare current disk metadata to `loadedVersion`
4. if changed, return conflict instead of writing
5. if unchanged, encode text to data
6. perform coordinated write
7. refresh metadata after write
8. return the new `DocumentVersion`

### Conflict triggers

A conflict should be raised when:

- modification date changed since load
- file size changed since load in a way that indicates external edit
- optional content hash changed if using hash checks
- file was deleted or moved
- the save target is no longer reachable

### Conflict actions

The UI should offer:

- **Reload from Disk** — discard local buffer and load current file contents
- **Overwrite** — only after explicit user confirmation
- **Cancel** — keep editing without dismissing the editor

### Back navigation rule

When the user leaves the editor:

- if clean, dismiss immediately
- if save is in flight, wait or finish when practical
- if conflict exists, present resolution
- if save failed, do not silently leave unless the user confirms

---

## Preview architecture

### Why previews are part of architecture

Previews are not cosmetic. They are part of how this project stays maintainable.

Good previews provide:

- fast UI iteration
- regression visibility
- confidence for edge states
- reusable sample data for screenshots and tests

### Preview rules

- every UI file must compile with at least one preview
- stateful screens should have multiple previews
- previews should not touch real file-system APIs
- previews should use centralized sample data

### Preview sample states to create early

Create these sample states before building most UI:

- no workspace
- reconnect required
- populated workspace with nested folders
- empty workspace
- clean document
- failed save
- conflict detected

---

## Concurrency design

### Main actor ownership

Use `@MainActor` for:

- `AppModel`
- `WorkspacePickerViewModel`
- `WorkspaceBrowserViewModel`
- `DocumentEditorViewModel`

These types own UI-observable state.

### Background / isolated ownership

Do file work outside the main actor.

Good places for isolated behavior:

- `WorkspaceService`
- `DocumentService`
- file infrastructure helpers

### Cancellable work

The following work should be cancellable:

- workspace refresh
- document open
- debounced autosave
- optional file create/rename/delete refresh chain if the view disappears

### Stale result protection

When two async operations overlap, older results must not overwrite newer state.

Examples:

- refresh A starts
- refresh B starts later
- refresh A finishes last

The browser must keep the result from refresh B, not refresh A.

Use task identifiers or store active `Task` references to prevent stale state application.

---

## Error handling model

### Internal vs user-facing errors

Keep two layers:

#### Internal

`AppError` is for services and infrastructure.

#### User-facing

`UserFacingError` is for Views.

This keeps UI copy consistent and avoids leaking raw system details.

### Important user-facing failure categories

Prepare clear messages for:

- folder access lost
- workspace restore failed
- folder no longer available
- file not found
- file save failed
- save conflict detected
- rename failed
- delete failed
- create file failed

---

## Why this architecture is the right size

This architecture is deliberately not a giant layered enterprise system.

It is the right size for this app because it gives:

- isolated file safety logic
- clear test seams
- predictable previews
- small view files
- small service files
- room to add iPad improvements later

without introducing:

- unnecessary repositories/use-cases/interactors for every button press
- duplicated state owners
- framework-like ceremony

---

## Implementation priorities

Build in this order:

1. app shell and workspace restore
2. workspace enumeration and browser snapshot
3. browser UI
4. document opening and plain-text editor
5. native editor presentation and quiet autosave behavior
6. conflict handling
7. create/rename/delete
8. polish, previews, tests, and iPad improvements

Do not build beyond that order unless a later task is completely isolated and low risk.

---

## Final architectural summary

The shape of the app should stay simple:

- one app model
- one workspace service
- one document service
- one browser snapshot
- one open document
- one autosave scheduler
- one preview-support package of sample data and fake services

That is enough to build a reliable SwiftUI markdown editor without overbuilding the project.
