# TASKS.md

## How to use this file

This file is the execution plan for building the MVP defined in `PLANS.md` and structured in `ARCHITECTURE.md`.

Each task includes:

- the goal of the task
- the files to create or update
- what each file is responsible for in that task
- acceptance criteria
- notes about sequencing or risk

Keep statuses updated as work progresses.

---

## Status legend

- [ ] not started
- [-] in progress
- [x] done
- [!] blocked

---

## Global execution rules

- Follow `AGENTS.md` first, then `PLANS.md`, then `ARCHITECTURE.md`.
- Do not add scope beyond MVP unless the task explicitly says it is deferred.
- Do not introduce UIKit.
- Do not add third-party dependencies.
- Do not put file-system work in a View.
- Do not hide safety failures behind a visually quiet UI.
- Do not flatten the folder hierarchy.
- Do not merge a UI file without a preview and sample data.
- Run targeted tests after each meaningful phase.
- Prefer standard SwiftUI navigation over custom editor navigation chrome.
- Do not keep a persistent save-state indicator unless the product docs explicitly require it again.

---

## Phase 0 — Project setup and alignment

### Goal

Set up the blank Xcode app so the repository structure, naming, and dependency layout are clear before file access logic is added.

### Tasks

- [ ] Create source folders that match `ARCHITECTURE.md`
  - Files/folders to create:
    - `App/`
    - `Features/WorkspacePicker/`
    - `Features/Browser/`
    - `Features/Editor/`
    - `Features/Settings/`
    - `Domain/Workspace/`
    - `Domain/Document/`
    - `Domain/Common/`
    - `Services/`
    - `Infrastructure/`
    - `PreviewSupport/`
    - test targets and folders
  - Purpose:
    - gives the project one agreed shape from the beginning
    - avoids dumping everything into the default Xcode group

- [x] Confirm project settings for Swift 6 mode and supported Apple platforms
  - File(s):
    - Xcode project settings only
  - Purpose:
    - ensure language mode and deployment settings match the repo rules
    - prevent later refactors caused by wrong defaults

- [x] Create `App/MarkdownWorkspaceApp.swift`
  - Responsibility:
    - app entry point
    - create `AppContainer`
    - create `AppModel`
    - launch `RootScreen`

- [x] Create `App/AppContainer.swift`
  - Responsibility:
    - composition root
    - instantiate services once
    - make preview/test substitution possible later

- [ ] Create `App/AppModel.swift`
  - Responsibility:
    - root app state
    - app bootstrap
    - top-level navigation and error transitions

- [x] Create `App/RootScreen.swift`
  - Responsibility:
    - switch between no-workspace, restoring, reconnect, and ready UI

- [ ] Create `Domain/Common/AppError.swift`
  - Responsibility:
    - internal error categorization shared by services

- [ ] Create `Domain/Common/UserFacingError.swift`
  - Responsibility:
    - UI-safe error model

- [ ] Create `Domain/Common/AsyncLoadState.swift`
  - Responsibility:
    - small loading-state helper if it keeps view models cleaner

### Acceptance criteria

- [ ] The project has the target folder structure
- [x] The app compiles with a basic root shell
- [x] There is one obvious place where dependencies are created
- [x] App can launch into a placeholder root state without file access yet

---

## Phase 1 — Preview support foundation

### Goal

Create preview infrastructure early so every screen can be previewed from the beginning instead of adding previews as an afterthought.

### Tasks

- [x] Create `PreviewSupport/PreviewSampleData.swift`
  - Responsibility:
    - central sample workspace nodes
    - sample folders and files
    - sample document states
    - sample user-facing errors

- [ ] Create `PreviewSupport/PreviewServices.swift`
  - Responsibility:
    - fake workspace service
    - fake document service
    - no-op bookmark/session stores if useful for previews

- [ ] Create `PreviewSupport/PreviewViewModels.swift`
  - Responsibility:
    - helper factories that produce view models already loaded into sample states

- [x] Define baseline preview fixtures
  - Must include:
    - no workspace state
    - reconnect required state
    - populated nested workspace
    - empty workspace
    - clean document
    - failed save state
    - conflict state

### Acceptance criteria

- [x] Shared preview data exists before major UI screens are built
- [x] Preview-only code does not touch real file-system APIs
- [x] UI files can use centralized sample data rather than duplicating literals

---

## Phase 2 — Workspace picker and restore flow

### Goal

Let the user select a folder, store access to it, and restore that access on launch.

### Tasks

- [x] Create `Services/BookmarkStore.swift`
  - Responsibility:
    - save bookmark data
    - load bookmark data
    - clear bookmark data

- [x] Create `Infrastructure/SecurityScopedAccess.swift`
  - Responsibility:
    - central helper for starting/stopping security-scoped access around operations

- [ ] Create `Features/WorkspacePicker/WorkspacePickerViewModel.swift`
  - Responsibility:
    - handle folder picker results
    - trigger workspace selection
    - surface selection/restore errors to the app model

- [ ] Create `Features/WorkspacePicker/WorkspacePickerScreen.swift`
  - Responsibility:
    - first-run UI
    - open-folder action
    - folder picker presentation
  - Required previews:
    - first launch
    - optional loading/disabled state

- [x] Create `Features/WorkspacePicker/ReconnectWorkspaceScreen.swift`
  - Responsibility:
    - explain why the workspace must be reconnected
    - offer reconnect, choose different folder, or clear workspace
  - Required previews:
    - stale bookmark
    - access lost

- [x] Create `Services/WorkspaceService.swift` initial version
  - Responsibility in this phase:
    - accept selected workspace URL
    - create bookmark data
    - persist bookmark
    - restore bookmark data on launch
    - resolve restored URL
    - surface stale restore state cleanly
  - Do not add enumeration yet beyond what is needed for validation

- [ ] Add bootstrap logic to `AppModel`
  - Responsibility in this phase:
    - try restore on launch
    - set root state to no workspace / reconnect / ready placeholder

### Acceptance criteria

- [x] User can choose a folder once
- [x] App remembers that folder across relaunch
- [x] Stale or invalid bookmark state is detectable
- [x] Reconnect UI exists and is reachable
- [x] Picker and reconnect screens have previews

### Tests

- [x] Add `MarkdownWorkspaceTests/BookmarkStoreTests.swift`
  - Test:
    - save bookmark
    - load bookmark
    - clear bookmark
    - missing bookmark result

- [ ] Add initial `MarkdownWorkspaceTests/WorkspaceServiceTests.swift`
  - Test:
    - successful workspace select
    - restore without bookmark
    - stale restore handling mapping

---

## Phase 3 — Workspace domain models

### Goal

Create the immutable models the browser will render.

### Tasks

- [x] Create `Domain/Workspace/SupportedFileType.swift`
  - Responsibility:
    - central supported-extension policy
    - helper methods for extension matching

- [ ] Create `Domain/Workspace/WorkspaceFile.swift`
  - Responsibility:
    - metadata for visible file items

- [ ] Create `Domain/Workspace/WorkspaceFolder.swift`
  - Responsibility:
    - metadata and children for visible folder items

- [x] Create `Domain/Workspace/WorkspaceNode.swift`
  - Responsibility:
    - canonical enum representing folder or file

- [x] Create `Domain/Workspace/WorkspaceSnapshot.swift`
  - Responsibility:
    - immutable snapshot of the workspace tree

### Acceptance criteria

- [x] The workspace tree types compile
- [x] Supported file policy exists in one place
- [x] Models are preview- and test-friendly
- [x] Nothing in these files performs I/O

---

## Phase 4 — Workspace enumeration

### Goal

Scan the chosen folder recursively and produce a stable snapshot for the browser.

### Tasks

- [ ] Create `Infrastructure/FileMetadataReader.swift`
  - Responsibility:
    - read resource values needed by the enumerator
    - determine hidden/file/directory flags
    - gather modification date and size

- [x] Create `Infrastructure/WorkspaceEnumerator.swift`
  - Responsibility:
    - recursively walk the workspace
    - filter supported files
    - keep relevant ancestor folders
    - sort folders before files
    - build `WorkspaceSnapshot`

- [x] Expand `Services/WorkspaceService.swift`
  - Responsibility added in this phase:
    - call the enumerator
    - return workspace snapshot
    - refresh workspace on demand

- [ ] Wire snapshot loading into `AppModel`
  - Responsibility in this phase:
    - after restore or workspace selection, load initial snapshot
    - surface loading vs error vs ready

### Acceptance criteria

- [x] Enumerating a folder produces a nested snapshot
- [x] Unsupported files are omitted
- [x] Folders containing supported descendants remain visible
- [x] Sorting is stable and user-friendly
- [x] Refresh can be requested again without rebuilding the app state design

### Tests

- [x] Add `MarkdownWorkspaceTests/WorkspaceEnumeratorTests.swift`
  - Test:
    - filtering rules
    - sort order
    - hidden-file skipping
    - descendant-retention behavior
    - nested snapshot shape

- [ ] Expand `MarkdownWorkspaceTests/WorkspaceServiceTests.swift`
  - Test:
    - refresh workspace returns snapshot
    - refresh after missing access returns mapped error

---

## Phase 5 — Browser UI

### Goal

Render the workspace snapshot as a usable nested browser.

### Tasks

- [ ] Create `Features/Browser/WorkspaceNodeRow.swift`
  - Responsibility:
    - render one folder row or file row
    - apply iconography and accessibility labels
  - Required previews:
    - folder
    - file
    - long filename

- [ ] Create `Features/Browser/WorkspaceEmptyStateView.swift`
  - Responsibility:
    - shared empty-state UI for workspace/folder cases
  - Required previews:
    - empty workspace
    - empty folder

- [ ] Create `Features/Browser/FolderContentsScreen.swift`
  - Responsibility:
    - show one folder level
    - navigate into subfolders
    - open files
    - expose file actions via menus or confirmation UI
  - Required previews:
    - populated folder
    - empty folder
    - mixed nested content

- [ ] Create `Features/Browser/WorkspaceBrowserViewModel.swift`
  - Responsibility:
    - own snapshot load state
    - refresh workspace
    - route file taps to the app model
    - manage presented browser errors
    - manage create/rename/delete action state later

- [ ] Create `Features/Browser/WorkspaceBrowserScreen.swift`
  - Responsibility:
    - host root folder browser
    - show refresh action
    - show settings entry
    - show root empty/error states
  - Required previews:
    - loading
    - loaded
    - empty
    - error

- [ ] Create `Features/Browser/FileActionSheetModel.swift` if needed
  - Responsibility:
    - lightweight UI action state for file operations
    - only keep this file if it genuinely clarifies browser state

### Acceptance criteria

- [x] User can browse nested folders using `NavigationStack`
- [x] User can tell folders from files
- [x] Browser can show loading, empty, and error states
- [x] Browser UI compiles with previews for all major states

### Tests

- [ ] Add view model tests if useful for browser state transitions
- [ ] Add or plan `MarkdownWorkspaceUITests/WorkspaceFlowUITests.swift`
  - Test:
    - open app
    - browse nested folder
    - tap file row

---

## Phase 6 — Document domain models and file codec

### Goal

Define the editor’s core state and the text encoding/metadata pieces needed to open and save documents safely.

### Tasks

- [x] Create `Domain/Document/DocumentVersion.swift`
  - Responsibility:
    - store file version metadata used for conflict detection

- [x] Create `Domain/Document/DocumentSaveState.swift`
  - Responsibility:
    - describe unsaved/saving/saved/failed status used internally by the save pipeline

- [x] Create `Domain/Document/DocumentConflictState.swift`
  - Responsibility:
    - describe save conflict details in a UI-friendly way

- [x] Create `Domain/Document/OpenDocument.swift`
  - Responsibility:
    - model the currently open document in memory

- [ ] Create `Infrastructure/TextFileCodec.swift`
  - Responsibility:
    - decode text file contents
    - encode text for saving
    - centralize encoding policy

- [ ] Create `Infrastructure/FileCoordinatorClient.swift`
  - Responsibility:
    - coordinate read/write access
    - keep coordination code out of services

- [ ] Create `Infrastructure/AtomicFileWriter.swift`
  - Responsibility:
    - write text data safely and consistently

### Acceptance criteria

- [x] Document state types are defined and readable
- [ ] Text encoding policy lives in one file
- [ ] Write strategy lives in one file
- [ ] Services can now depend on focused infrastructure instead of ad hoc helpers

---

## Phase 7 — Document opening

### Goal

Open a markdown file from the browser into a real editor model.

### Tasks

- [x] Create `Services/DocumentService.swift`
  - Responsibility in this phase:
    - open file text
    - read current metadata
    - create `OpenDocument`
    - map open errors to user-facing errors

- [ ] Extend `Services/SessionStore.swift`
  - Responsibility:
    - store last opened file path or identifier relative to workspace root
    - keep session state lightweight

- [x] Create `Features/Editor/DocumentEditorViewModel.swift` initial version
  - Responsibility in this phase:
    - load document
    - expose text and save state
    - own editor-specific error state

- [x] Create `Features/Editor/DocumentEditorScreen.swift`
  - Responsibility in this phase:
    - render `TextEditor`
    - bind text to the view model
    - show loading/error states while file opens
  - Required previews:
    - loading
    - clean document
    - open error

### Acceptance criteria

- [x] Tapping a file opens its contents in a SwiftUI `TextEditor`
- [x] Open errors are visible and readable
- [x] Editor screen has meaningful previews

### Tests

- [x] Add `MarkdownWorkspaceTests/DocumentServiceTests.swift`
  - Test:
    - open document success
    - open missing file failure
    - metadata is captured on open

- [ ] Add initial `MarkdownWorkspaceUITests/EditorFlowUITests.swift`
  - Test:
    - open file from browser
    - editor appears

---

## Phase 8 — Native editor presentation

### Goal

Refactor the editor to feel truly native by using standard SwiftUI navigation and removing custom editor chrome used as a navigation replacement.

### Tasks

- [x] Simplify `Features/Editor/DocumentEditorScreen.swift`
  - Responsibility:
    - use standard navigation title behavior
    - keep the standard navigation bar visible
    - remove custom overlay navigation treatment
    - keep load, failure, and conflict presentation intact

- [x] Remove or repurpose `Features/Editor/EditorChromeView.swift`
  - Responsibility:
    - if it exists only to replace system navigation, remove it
    - if any part remains, it must not duplicate the standard back button

- [x] Remove or repurpose `Features/Editor/SaveIndicatorView.swift`
  - Responsibility:
    - remove persistent save-state chrome from normal editing
    - preserve only user-attention UI if still needed for error states

- [x] Update `DocumentEditorViewModel`
  - Responsibility:
    - stop exposing persistent UI state solely for a floating save indicator
    - continue exposing failure and conflict state clearly

### Acceptance criteria

- [x] The editor uses the standard navigation bar
- [x] The editor uses the standard system back button
- [x] There is no custom floating back button
- [x] There is no persistent save-state indicator during normal editing
- [x] The editor feels like a native SwiftUI detail screen

### Notes and risk

This phase intentionally changes direction away from custom overlay editor chrome. Preserve save correctness and conflict handling, but remove the UI that tries to simulate a custom Notes-style editor.

---

## Phase 9 — Dirty state and autosave

### Goal

Track local edits and save them automatically with debounce.

### Tasks

- [ ] Create `Services/AutosaveScheduler.swift`
  - Responsibility:
    - debounce repeated text changes
    - cancel pending saves when newer edits arrive
    - request immediate flush when required

- [x] Extend `DocumentEditorViewModel`
  - Responsibility added in this phase:
    - mark document unsaved on edit
    - schedule autosave
    - update save-state transitions correctly
    - request flush on disappear or back action when appropriate

- [x] Extend `DocumentService`
  - Responsibility added in this phase:
    - perform actual save
    - return updated `DocumentVersion` on success
    - map save errors cleanly

### Acceptance criteria

- [x] Typing marks the document unsaved internally immediately
- [x] Repeated typing coalesces into fewer saves
- [x] Save success can remain visually quiet
- [x] The user is still clearly informed when save fails

### Tests

- [ ] Add `MarkdownWorkspaceTests/AutosaveSchedulerTests.swift`
  - Test:
    - debounce coalescing
    - cancellation behavior
    - flush behavior

- [ ] Add `MarkdownWorkspaceTests/DocumentEditorViewModelTests.swift`
  - Test:
    - dirty-state transitions
    - save-state transitions
    - editor text updates schedule save

---

## Phase 10 — Conflict detection and editor dismissal safety

### Goal

Prevent silent overwrite of newer disk content and make leaving the editor safe.

### Tasks

- [x] Extend `DocumentService`
  - Responsibility added in this phase:
    - re-read current disk metadata before save
    - compare against `loadedVersion`
    - return conflict state instead of overwriting automatically

- [x] Create `Features/Editor/ConflictResolutionView.swift`
  - Responsibility:
    - explain conflict
    - present reload, overwrite, and cancel choices
  - Required previews:
    - modified-on-disk conflict
    - deleted file conflict if supported

- [x] Extend `DocumentEditorViewModel`
  - Responsibility added in this phase:
    - store conflict state
    - handle reload action
    - handle explicit overwrite action
    - prevent silent back-navigation when save failed or conflict exists

- [x] Update `DocumentEditorScreen`
  - Responsibility added in this phase:
    - present conflict UI
    - handle failed-save navigation edge cases

### Acceptance criteria

- [x] External modification is detected before overwrite
- [x] User sees explicit recovery choices
- [x] Back navigation does not silently discard unsaved work after failure or conflict

### Tests

- [x] Expand `MarkdownWorkspaceTests/DocumentServiceTests.swift`
  - Test:
    - conflict when metadata changed
    - overwrite only succeeds when explicitly requested
    - deleted-file behavior

- [x] Expand `MarkdownWorkspaceTests/DocumentEditorViewModelTests.swift`
  - Test:
    - conflict state presentation
    - back-navigation safeguard
    - retry save after failure

- [ ] Expand `MarkdownWorkspaceUITests/EditorFlowUITests.swift`
  - Test:
    - conflict dialog appears when expected

---

## Phase 11 — File operations in the browser

### Goal

Support basic file management inside the workspace.

### Tasks

- [x] Extend `WorkspaceManager`
  - Responsibility added in this phase:
    - create markdown file in a folder
    - rename file
    - delete file
    - return refreshed snapshot after each mutation

- [x] Extend `WorkspaceViewModel`
  - Responsibility added in this phase:
    - present create, rename, and delete state
    - call workspace manager through the app coordinator
    - refresh snapshot after mutations
    - preserve reasonable selection and navigation state
    - keep the editor stable when the active file is renamed or deleted

- [x] Update `WorkspaceFolderScreen`
  - Responsibility added in this phase:
    - present create file action
    - present rename and delete actions for rows
    - show confirmation UI for destructive actions

### Acceptance criteria

- [x] User can create a new markdown file
- [x] User can rename a file
- [x] User can delete a file
- [x] Browser refreshes after each mutation
- [x] Errors are surfaced clearly
- [x] Renaming or deleting the active file does not corrupt editor state

### Tests

- [x] Expand mutation coverage in unit tests
  - Test:
    - create file
    - rename file
    - delete file
    - refresh after each mutation
    - active file rename and delete safety
    - error mapping on failed operations

- [ ] Expand `MarkdownWorkspaceUITests/WorkspaceFlowUITests.swift`
  - Test:
    - create file flow
    - rename file flow
    - delete file flow

---

## Phase 12 — Settings and workspace management

### Goal

Add a very small settings or info area for workspace management without bloating the app.

### Tasks

- [x] Create `Features/Settings/SettingsScreen.swift`
  - Responsibility:
    - show workspace information
    - reconnect workspace
    - clear workspace
    - show concise app info
  - Required previews:
    - workspace loaded
    - no workspace

- [x] Extend app-level workspace coordination
  - Responsibility added in this phase:
    - clear workspace
    - return to picker state
    - reconnect workflow hooks

### Acceptance criteria

- [x] User can clear or reconnect the workspace from settings
- [x] Settings screen stays small and MVP-focused
- [x] Settings screen has previews

---

## Phase 13 — Launch restoration and lifecycle resilience

### Goal

Make relaunch and scene changes feel safe and predictable.

### Tasks

- [x] Extend `AppModel`
  - Responsibility added in this phase:
    - restore last open file path if safe
    - bootstrap workspace refresh on relaunch
    - clear invalid file selection when the file no longer exists

- [x] Extend `Services/SessionStore.swift`
  - Responsibility added in this phase:
    - persist lightweight last-file information

- [x] Extend `DocumentEditorViewModel`
  - Responsibility added in this phase:
    - flush pending save on disappear and lifecycle transitions where appropriate

- [x] Add lifecycle hooks where needed
  - Responsibility:
    - revalidate workspace and editor state when returning to foreground
    - avoid stale restore paths after provider-side changes

### Acceptance criteria

- [x] Relaunch returns to the workspace when bookmark restore succeeds
- [x] Last file can be reopened safely if the app chooses to support it in MVP
- [x] Lifecycle transitions do not cause silent data loss
- [x] Foregrounding does not leave the editor showing stale state blindly

### Tests

- [x] Add or expand launch-flow tests
- [x] Add tests for session restore edge cases if implemented
- [x] Add tests for background and foreground save behavior if lifecycle hooks are added

---

## Phase 14 — Accessibility, polish, and iPad refinement

### Goal

Finish the app with usability and platform polish without changing core architecture.

### Tasks

- [ ] Audit all buttons and controls for clear accessibility labels
  - Affects:
    - picker
    - browser rows
    - editor screens
    - settings actions
    - conflict presentation

- [x] Verify any save failure messaging is not color-only
  - Affects:
    - failed save UI
    - conflict UI
    - error alerts

- [x] Verify Dynamic Type behavior across screens
  - Affects all UI files

- [x] Finalize native editor behavior
  - Affects:
    - `DocumentEditorScreen`
    - navigation ownership
    - toolbar usage if any
  - Requirements:
    - remove any remaining custom floating back button
    - remove hidden-nav-bar editor treatment
    - remove fake header spacing
    - ensure editor spacing feels natural under the standard bar
    - keep the overall presentation calm and native

- [x] Verify iPad layout readability and navigation usability
  - Affects:
    - `RootScreen`
    - `WorkspaceBrowserScreen`
    - `FolderContentsScreen`
    - `DocumentEditorScreen`

- [x] Improve calm visual styling using native SwiftUI materials and spacing only where useful
  - Do not add decorative complexity

### Acceptance criteria

- [x] The app remains minimal
- [x] Important controls are accessible
- [x] The app is comfortable on iPhone and iPad
- [x] No polish work weakens data-safety behavior
- [x] The editor visually behaves like a standard native detail screen

---

## Phase 15 — Full preview pass

### Goal

Ensure every UI file has complete previews and shared sample data.

### Tasks

- [ ] Review every SwiftUI view file
- [ ] Add missing `#Preview` blocks
- [ ] Replace duplicated inline sample data with shared preview data
- [ ] Ensure edge-state previews compile:
  - loading
  - empty
  - error
  - failed save
  - conflict
  - native editor state without custom chrome

### Acceptance criteria

- [x] No UI file lacks previews
- [x] Preview data is centralized and reusable
- [x] Previews demonstrate real states rather than placeholder text only

---

## Phase 16 — Final test sweep

### Goal

Verify the MVP is stable enough to use on real files.

### Tasks

- [x] Run all relevant unit tests
- [ ] Run all high-value UI tests
- [ ] Manually verify on-device behavior with:
  - local On My iPhone or iPad storage
  - iCloud Drive
  - nested folders
  - renamed files
  - deleted files
  - fast repeated edits
  - app relaunch
  - background and foreground transitions

- [ ] Verify manual scenarios:
  - pick folder
  - restore folder
  - browse nested folder
  - open file
  - edit file
  - autosave file
  - detect conflict
  - create file
  - rename file
  - delete file
  - clear workspace
  - reconnect workspace
  - verify the editor feels like standard SwiftUI navigation

### Acceptance criteria

- [ ] Critical flows are verified
- [ ] No major data-loss path is known
- [ ] App is ready for private real-world testing

---

## Ongoing audit checklist

Review this list often during implementation:

- [x] No view performs direct file I/O
- [x] No view model performs raw `FileManager` work
- [x] No save path runs concurrently for the same document
- [x] No stale async refresh overwrites a newer snapshot
- [x] No browser path flattens nested folders
- [x] No editor state hides save failures or conflicts
- [x] No UI file is missing previews
- [x] No sample data is duplicated across many view files
- [x] No UIKit bridge has been introduced
- [x] No deferred feature has slipped into MVP unnoticed
- [x] No custom editor navigation chrome remains where standard navigation should be used

---

## Final delivery standard

The MVP is done when the app can reliably do the following on a real device:

- open a user-selected folder
- restore that folder later
- browse nested markdown files
- edit a file in a minimal SwiftUI editor
- autosave without lying about safety
- detect and resolve conflicts
- manage basic file operations safely
- feel like a standard native SwiftUI file editor rather than a simulated custom note editor

If those are solid, the app is a successful first release.
