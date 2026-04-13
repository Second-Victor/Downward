# PLANS.md

## Product name

**MarkdownWorkspace**

Use this as the working app name in code, previews, and documentation unless the product is renamed later.

---

## One-sentence product goal

Build a small, reliable SwiftUI app for iPhone and iPad that lets the user choose one folder from Files, browse nested markdown files inside that folder, edit them as plain text, and save safely.

---

## What “robust MVP” means for this app

A robust MVP is not just “I can type into a text field.” It must do the following well:

- restore workspace access after relaunch
- browse the real folder hierarchy instead of a fake flat list
- open markdown files reliably
- save without losing edits
- handle cloud or Files-provider latency gracefully
- detect conflicts before overwriting newer disk content
- show clear empty and error states
- keep the UI intentionally minimal
- make the editor feel calm, native, and predictable

If any one of those is missing, the app is not yet a solid MVP.

---

## Primary user story

> I keep markdown files in a folder in Files or iCloud Drive. I want a small iPhone/iPad app that opens that folder, lets me move through subfolders, tap a note, edit it quickly, and trust that the file on disk is saved correctly.

---

## Core user journeys

### Journey 1 — First launch

1. User opens the app.
2. App shows a simple explanation that it edits markdown files inside a chosen folder.
3. User taps **Open Folder**.
4. User chooses a folder from Files.
5. App stores access to that folder.
6. App loads the folder contents.
7. App shows the workspace browser.

### Journey 2 — Relaunch

1. User closes the app.
2. User opens it again later.
3. App restores the saved bookmark.
4. App resolves the folder URL.
5. App loads the workspace automatically.
6. User returns directly to browsing without re-picking the folder.

### Journey 3 — Browse and open

1. User sees folders first and files second.
2. User taps a subfolder and moves deeper into the hierarchy.
3. User taps a markdown file.
4. App loads the file text and editor state.
5. Editor opens using standard SwiftUI navigation.

### Journey 4 — Edit and autosave

1. User edits the text.
2. App marks the document as needing save internally.
3. A short debounce window starts.
4. App saves in the background.
5. The UI stays quiet when save succeeds quickly.
6. User only sees extra save UI if something is slow or failed.

### Journey 5 — Conflict handling

1. User opens a file.
2. The same file changes outside the app.
3. User keeps editing and triggers a save.
4. App detects the on-disk version changed.
5. App presents explicit choices.
6. User decides whether to reload or overwrite.

### Journey 6 — File management

1. User is browsing a folder.
2. User creates a new markdown file, renames a file, or deletes a file.
3. App performs the mutation safely inside the selected workspace.
4. The browser refreshes without flattening the folder structure.
5. If the edited file was renamed or deleted, the editor state updates safely.

### Journey 7 — Return to the app

1. User backgrounds the app while browsing or editing.
2. User returns later.
3. App validates workspace access again.
4. App restores the last open file only if it is still safe to do so.
5. Unsaved work is not silently discarded.

---

## Strict MVP scope

### Included

#### Workspace

- choose one folder using Files
- persist workspace bookmark
- restore bookmark on app launch
- clear workspace and choose a different folder
- reconnect workspace if bookmark becomes stale or invalid

#### Browser

- recursively scan the chosen folder
- preserve the nested folder structure
- show folders before files
- show supported markdown files only
- refresh the workspace manually
- show empty state when no supported files exist
- show error state when access fails

#### Supported file types

- `.md`
- `.markdown`
- `.txt` is optional but recommended for practicality

#### Editor

- plain text editing with `TextEditor`
- open one document at a time
- dirty-state tracking
- autosave with debounce
- back navigation that does not silently discard unsaved data
- no persistent save-state indicator during normal successful editing
- clear visible failure state when save fails
- clear visible conflict state when overwrite safety requires user action
- standard SwiftUI navigation bar and system back button
- standard SwiftUI navigation title behavior
- no custom floating back control
- no simulated Notes-style overlay chrome
- no fake header spacing or fade overlay

#### File operations

- create file in current folder
- rename file
- delete file
- optional create folder if it does not destabilize the rest of the MVP

#### Settings

A very small settings or app info screen is allowed. It should contain only things that directly help the MVP, such as:

- current workspace name
- reconnect workspace
- clear workspace
- app version or build information in debug if desired

### Excluded

- markdown rendering preview
- syntax highlighting
- document tabs
- split editing
- rich text
- image attachments
- search across file contents
- custom themes
- font customization
- shortcuts database
- Git operations
- iCloud sync logic beyond what Files providers already give
- export/import beyond editing files in place
- custom floating editor controls that replace standard navigation
- persistent unsaved-dot style chrome during normal editing

---

## Product principles

### 1. Workspace-first

The app edits files in a real user-selected folder. It is not the owner of those files.

### 2. Minimal UI, strong state clarity

The UI should stay simple, but the app still needs to communicate:

- which workspace is open
- which file is open
- whether save failed
- whether the file changed elsewhere
- whether the user needs to make a recovery decision

### 3. Safety beats convenience

The app may sometimes ask the user to resolve a conflict. That is acceptable. Silent data loss is not.

### 4. One clear mental model

The app should teach the user one thing:

> Pick a folder, browse it, edit files inside it.

No extra storage model should compete with that.

### 5. No fake hierarchy

If files are nested in subfolders, the browser should represent that truthfully.

### 6. Native SwiftUI first

The app should feel as native as possible by leaning on standard SwiftUI navigation and system controls before introducing custom visual behaviors.

---

## Recommended MVP experience

### Root states

The app has four root-level states:

1. **No workspace selected**
2. **Restoring workspace**
3. **Workspace ready**
4. **Workspace needs reconnect**

The root screen should choose between these states explicitly.

### Browser experience

The browser should feel like a small focused file browser:

- clear workspace title
- simple list rows
- folders visibly distinct from files
- navigation driven by taps
- refresh action
- file actions in menus or swipe/context interactions
- no cluttered toolbar

### Editor experience

The editor should feel like a high-quality native detail screen:

- plain text content area
- standard system back button
- standard navigation bar
- standard navigation title
- no permanent formatting toolbar
- no persistent save badge during normal editing
- errors and conflicts shown only when something needs user attention
- optional transient “Saving…” feedback only if saves become noticeably slow

---

## Recommended MVP navigation

### Baseline

Use one navigation system for the first stable version:

- `NavigationStack`
- folder drill-in
- push editor from file selection

This keeps the first version simple and reliable.

### Editor navigation rule

The editor should remain inside the same standard navigation model as the browser. It should use the system-provided back affordance and standard navigation bar presentation.

### iPad adaptation

After the baseline flow works well, add an iPad adaptation. That can be:

- the same `NavigationStack` with a wider layout, or
- a later `NavigationSplitView`

Do not let iPad layout needs destabilize the first pass of the save pipeline or folder browser.

If `NavigationSplitView` is used later, the editor pane should still preserve the same native direction:

- no custom floating navigation controls
- no hidden system bar just to simulate a custom editor
- use standard SwiftUI navigation behaviors first

---

## Robustness requirements

### Bookmark restore

The app must survive relaunches. Workspace restore is a core feature, not polish.

Success means:

- bookmark data is stored when the folder is selected
- bookmark data can be resolved later
- stale bookmark state is detected
- reconnect flow is clear

### Security-scoped access

The app must correctly manage access to the chosen folder and files beneath it. This is essential for editing files outside the sandbox.

### Save pipeline

The save pipeline must be trustworthy:

- no overlapping saves for one document
- successful saves may remain visually quiet
- save failure must be visible
- conflict detection happens before overwrite
- writes are coordinated and as crash-safe as practical

### File-provider resilience

The app should assume:

- files may be slow to materialize
- metadata may update between open and save
- directory contents may change externally
- iCloud-backed folders may behave differently from local storage

### Cancellation

If the user quickly switches folders or opens another file:

- old tasks must not overwrite new UI state
- enumeration and loading tasks must be cancellable

---

## UX requirements

### Empty states

Need dedicated UI for:

- no workspace selected
- workspace contains no supported files
- folder exists but cannot be read
- editor file no longer exists

### Errors

Errors must be readable and actionable:

- explain what failed
- avoid raw system jargon
- give a recovery step when possible

### Save-state communication

The app should not show a persistent save-state indicator during normal editing if autosave is reliable.

Required behavior:

- save failures must always be visible
- conflicts must always be visible
- the user must never be misled into thinking data is safe when it is not
- optional transient saving feedback is allowed only when saves are noticeably slow
- color alone must not be the only signal for a failure state

### Accessibility

The MVP must support:

- Dynamic Type
- VoiceOver labels
- clear button labels
- save failure not communicated by color alone
- large tap targets for important controls

---

## Data and state requirements

### Browser data

The browser renders from an immutable snapshot model, not live `FileManager` traversal during view rendering.

### Editor data

The editor owns:

- current text
- loaded file version
- dirty state
- save state
- conflict state
- load failure state if applicable

### Session data

The app may store lightweight session details such as:

- current workspace bookmark
- last opened file path relative to workspace root

Do not store an alternative canonical copy of all user files.

---

## Preview and sample-data plan

Every UI view in the project must compile with previews.

### Required preview states

#### Workspace picker

- first launch
- reconnect required

#### Browser

- loading
- empty workspace
- populated workspace
- file operation error

#### Folder contents

- root folder with child folders and files
- subfolder with only files
- folder with no supported children

#### Editor

- clean document
- failed save
- conflict state
- loading state
- native navigation title behavior represented where practical
- no preview that depends on custom floating chrome

#### Settings

- workspace loaded
- no workspace

### Sample data ownership

Shared sample data belongs in dedicated preview-support files so previews stay consistent.

---

## Success criteria for MVP

The MVP is successful when a user can do all of this in one uninterrupted flow:

1. open the app
2. choose a folder
3. relaunch and return to the same folder
4. browse into a nested subfolder
5. open a markdown file
6. edit text
7. wait for autosave
8. close and reopen the app
9. verify the file content on disk is correct
10. switch to another file without state corruption
11. create, rename, and delete files without breaking the browser state
12. return from the editor and see navigation remain stable
13. only see save UI when something actually needs attention

---

## Release criteria

Do not call the app MVP-ready until all of these are true:

- workspace selection and restore are stable
- nested browsing is correct
- editor load/save works on local storage
- editor load/save works on iCloud Drive
- conflict handling works
- create/rename/delete work safely
- previews are present for every UI file
- sample data exists and stays up to date
- unit tests cover the critical services
- the editor feels like a standard native SwiftUI detail screen
- the UI remains minimal and calm

---

## Suggested phased plan

### Phase 0 — Project setup and alignment

Deliver:

- app entry
- dependency container
- root state model
- shared error types
- repo structure aligned with architecture

### Phase 1 — Preview support foundation

Deliver:

- preview sample data
- preview service fakes
- preview view model factories
- baseline screen state fixtures

### Phase 2 — Workspace picker and restore flow

Deliver:

- folder selection
- bookmark persistence
- restore on launch
- reconnect flow

### Phase 3 — Workspace domain models

Deliver:

- supported file policy
- workspace node, file, folder, and snapshot models

### Phase 4 — Workspace enumeration

Deliver:

- recursive enumeration
- nested workspace tree
- folder retention for supported descendants
- refresh support

### Phase 5 — Browser UI

Deliver:

- folder drill-in
- nested browser UI
- empty and error states
- refresh affordance

### Phase 6 — Document domain models and file codec

Deliver:

- document version
- save state
- conflict state
- open document
- file codec
- coordinated writer infrastructure

### Phase 7 — Document opening

Deliver:

- open file
- plain text editing shell
- visible load state
- editor previews

### Phase 8 — Native editor presentation

Deliver:

- standard navigation bar in the editor
- standard back button
- standard title behavior
- removal of custom overlay editor chrome
- removal of persistent save-state indicator in normal editing

### Phase 9 — Dirty state and autosave

Deliver:

- dirty-state tracking
- autosave debounce
- quiet save behavior during normal success
- confirmed save semantics

### Phase 10 — Conflict detection and editor dismissal safety

Deliver:

- save serialization
- conflict detection
- back-navigation safeguard
- external change handling
- stronger tests

### Phase 11 — File operations in the browser

Deliver:

- create, rename, delete
- browser refresh after mutation
- safe handling when current file is renamed or deleted

### Phase 12 — Settings and workspace management

Deliver:

- settings screen
- reconnect workspace action
- clear workspace action
- concise app info

### Phase 13 — Launch restoration and lifecycle resilience

Deliver:

- restore last open file when safe
- validate workspace and editor state on foreground
- preserve safe session state

### Phase 14 — Accessibility, polish, and iPad refinement

Deliver:

- Dynamic Type pass
- VoiceOver pass
- native editor spacing and toolbar polish
- iPad layout refinement without destabilizing the core flow

### Phase 15 — Full preview pass

Deliver:

- preview coverage for every UI file
- centralized sample data cleanup
- edge-state previews verified

### Phase 16 — Final test sweep

Deliver:

- unit test sweep
- high-value UI tests
- manual device verification on local files and iCloud Drive

---

## Nice-to-have after MVP

These are intentionally deferred:

- markdown preview
- syntax highlighting
- quick formatting actions
- recent files
- search within file contents
- multiple open documents
- better iPad multi-column layout beyond the MVP needs
- share and export actions
- custom editor font settings

---

## Final scope statement

The correct first version is a **safe single-workspace text editor**.

Do not let the app drift into being:

- a knowledge manager
- a note sync service
- a rich markdown renderer
- a document database
- a custom file manager

A narrow, trustworthy tool is the right MVP.
