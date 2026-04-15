# PLANS.md

## Product name

**Downward**

The Xcode app entry point is still `MarkdownWorkspaceApp`, but the product and repository name are **Downward**. New documentation and product-facing language should use that name.

---

## One-sentence product goal

Build a calm, reliable SwiftUI editor for iPhone and iPad that lets the user choose one workspace folder from Files, browse nested markdown files inside it, edit them as plain text, and trust that saves happen quietly and correctly.

---

## What “robust MVP” means now

A robust MVP is not just “open a file and type.” It must do all of the following well:

- restore workspace access after relaunch
- browse the real nested folder hierarchy
- keep real folders visible even when they are empty
- open markdown files reliably
- autosave without interrupting ordinary typing
- preserve local edits while save acknowledgements arrive asynchronously
- keep the active editor pointed at the real workspace file
- detect real external change, delete, or move cases without losing edits
- refresh browser and editor state safely when the file system changes
- keep the UI minimal, native, and predictable

If any of those fail, the app stops feeling trustworthy.

---

## Primary user story

> I keep markdown files in iCloud Drive or another Files location. I want a small iPhone/iPad app that opens one folder, lets me move through subfolders, tap a note, edit it quickly, and trust that the file on disk is being updated like a normal text editor.

---

## Core user journeys

### Journey 1 — First launch

1. User opens the app.
2. App explains that it edits files inside a chosen folder.
3. User taps **Open Folder**.
4. User chooses a folder from Files.
5. App stores persistent access to that folder.
6. App loads the folder contents.
7. App shows the workspace browser.

### Journey 2 — Relaunch

1. User closes the app.
2. User opens it later.
3. App restores the workspace bookmark.
4. App resolves the folder URL.
5. App loads the workspace automatically.
6. App restores the last open file when it is still safe to do so.

### Journey 3 — Browse and open

1. User sees folders first and files second.
2. User taps into subfolders.
3. User taps a markdown file.
4. App loads the file text and editor session.
5. Editor opens using standard SwiftUI navigation.

### Journey 4 — Edit and silent autosave

1. User edits the text.
2. App marks the document dirty internally.
3. A short debounce window starts.
4. The app saves in the background.
5. Save success is quiet.
6. The editor remains responsive and keeps newer edits even if an older save acknowledgement finishes later.

### Journey 5 — External change while open

1. The file changes outside the app, or on another device/provider path that becomes visible.
2. The app revalidates the open document.
3. If the change can be reflected safely, the editor state updates calmly.
4. If the change creates a real divergence or recovery case, the app surfaces explicit conflict UI.

### Journey 6 — File management

1. User creates, renames, or deletes a file in the workspace.
2. App performs the mutation safely inside the selected workspace.
3. Browser refreshes without flattening the hierarchy.
4. If the edited file changed identity, editor/session state updates safely.

### Journey 7 — Return to the app

1. User backgrounds the app while browsing or editing.
2. User returns later.
3. App revalidates workspace access and the open file.
4. The editor must not self-conflict because of the app's own previous saves.
5. Unsaved work is never silently discarded.

---

## Product principles

### 1. The workspace folder is the source of truth

The app edits files where the user chose them. It does not become a separate storage system.

### 2. The active editor should feel normal

Users should not have to repeatedly press **Overwrite Disk** during routine typing. Silent autosave is the expected default.

### 3. Conflict UI is rare by design

Conflicts should appear for real exceptional cases only, such as delete/move or a genuine divergent external change that cannot be handled quietly.

### 4. Minimal UI, strong behavior

The product wins by being calm, native, and dependable, not by shipping a large surface area.

---

## Strict scope

### Included

#### Workspace

- choose one folder from Files
- persist workspace bookmark access
- restore workspace automatically on relaunch when possible
- reconnect or clear when access becomes invalid
- refresh workspace contents

#### Browser

- recursive nested folder browsing
- show real folders even when they currently contain no supported files
- folders listed before files
- supported markdown/text files only
- empty states and error states
- create file
- rename file
- delete file

#### Editor

- open plain text markdown files
- edit with `TextEditor`
- persist editor font family and size preferences
- debounce autosave
- preserve newer edits when earlier save acknowledgements arrive
- save directly back to the workspace file
- reload from disk when requested
- detect real external modification or missing-file conditions
- calm save-state behavior

#### Session restore

- persist the last open document identity
- restore that document only when it is still valid within the workspace

#### Quality

- previews with sample data
- unit tests around restore, enumeration, autosave, and conflict behavior
- clear user-facing recovery messaging

### Explicitly out of scope for now

- live markdown preview
- syntax highlighting
- custom text engine
- Git integration
- multi-tab editing
- plugin system
- backlinks or wiki-link systems
- app-owned mirrored storage model
- rich formatting toolbars

---

## UX quality bar

The app should feel like this:

- choose folder once
- open files quickly
- type freely
- autosave happens quietly
- a real issue is explained clearly when it occurs
- returning to the app feels stable

The app should not feel like this:

- every few edits trigger a scary conflict popup
- the browser and editor drift out of sync
- file operations feel fragile or mysterious
- the user has to babysit autosave

---

## Success criteria

The MVP-plus build is successful when all of the following are true:

- opening a workspace and relaunching is reliable
- nested browsing is stable and easy to understand
- active-document autosave is quiet during ordinary typing
- newer local edits survive asynchronous save completions
- foreground revalidation does not self-conflict after the app's own saves
- true delete/move/external-change cases remain recoverable
- tests cover the important persistence and conflict paths

---

## Near-term product priorities

1. keep the save model calm and trustworthy
2. keep workspace and editor state coherent during file mutations
3. harden external-change handling and regression tests
4. improve polish around recovery, restore, and empty/error states
5. only then expand features beyond the MVP surface

---

## Future roadmap

### Near-term polish

The next sensible work after stabilization is still small in scope:

- add highest-risk UI tests
- profile larger workspaces and document-load paths
- keep accessibility and recovery copy polished where it improves real use
- keep release validation and provider-backed diagnostics lightweight but repeatable

### Next feature wave

The first real feature wave should improve everyday use without changing the app's core philosophy:

- lightweight workspace search or filter
- recent-file convenience that remains workspace-relative
- iPad / hardware-keyboard productivity improvements
- a minimal document info surface for the active file

These should all preserve the current model: one workspace, direct file editing, calm autosave, and minimal UI.

### Later optional expansions

Larger ideas should stay clearly deferred until the product earns them:

- markdown preview
- syntax highlighting
- tabs or multi-document editing
- multi-window workflow improvements
- Git or plugin-style integrations
- broader import support beyond UTF-8 plain text

---

## Current known limitations

- real-device Files and iCloud provider timing can vary, so live same-document refresh is best-effort rather than a hard realtime guarantee
- in-app mutations currently cover files only, not folder rename/move
- the app supports one active workspace and one live editor session at a time
