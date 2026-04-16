# PLANS.md

## Product name

**Downward**

The Xcode app entry point is still `MarkdownWorkspaceApp`, but the product and repository name are **Downward**.

---

## One-sentence product goal

Build a calm, trustworthy SwiftUI editor for iPhone and iPad that lets the user choose one real workspace folder from Files, browse nested markdown/text files inside it, edit them as plain text, and trust that the app is talking to the real files safely.

---

## What the next release actually needs to prove

Downward is no longer at the “can it edit text at all?” stage.

The next release needs to prove a tighter trust contract:

- the chosen workspace really restores after relaunch using the correct access model
- file identity stays stable across restore, rename, delete, recent-files, and search surfaces
- only the current visible editor owns live observation
- create / rename / delete use the same file-safety model as editor reads and writes
- refreshes and delayed async work cannot resurrect stale UI state
- autosave stays calm while still being honest about real failure cases

If those are not true, the app still feels fragile even if the UI looks polished.

---

## Product trust contract

These are the behaviors the app should be able to claim without hesitation.

### 1. The workspace folder is the source of truth

Downward edits the user’s chosen folder directly. It is not a notes database and it is not a shadow copy system.

### 2. File access survives relaunch for the same workspace

A restored workspace is only trustworthy if bookmark creation, resolution, and access are handled correctly for the chosen folder.

### 3. File identity is canonical

A file should be identified by one canonical workspace-relative path across:

- restore
- recent files
- mutation reconciliation
- editor routing
- search metadata

Display names are for UI, not identity.

### 4. The active editor feels normal

Typing should feel like a real text editor:

- quiet autosave
- no repeated self-conflict
- newer edits survive older save acknowledgements
- disappearing or backgrounding should not silently lose pending text

### 5. Observation belongs only to the active editor

Live revalidation is useful only while the matching editor is actually on screen. The app should not keep long-lived observation around for a document the user already left.

### 6. Browser mutations should be as trustworthy as editor saves

Create, rename, and delete are not “secondary” operations. They touch the same real workspace and must follow the same safety expectations.

---

## Revised robust-MVP definition

A robust MVP is not just “open a file and type.” It must do all of the following well:

- restore the chosen workspace after relaunch
- browse the real nested folder hierarchy
- keep real folders visible even when they are empty
- open markdown/text files reliably
- autosave without interrupting ordinary typing
- preserve local edits while save acknowledgements arrive asynchronously
- keep file identity coherent across restore, recents, rename, and delete
- ensure the visible editor owns the current document session
- refresh browser and editor state safely when the file system changes
- keep the UI minimal, native, and predictable

If any of those fail, the app stops feeling trustworthy.

---

## Primary user story

> I keep markdown files in iCloud Drive or another Files location. I want a small iPhone/iPad app that opens one folder, lets me move through subfolders, tap a note, edit it quickly, and trust that the real file on disk is being updated safely.

---

## Core user journeys

### Journey 1 — First launch

1. User opens the app.
2. App explains that it edits files inside a chosen folder.
3. User taps **Open Folder**.
4. User chooses a folder from Files.
5. App stores restorable access to that folder correctly.
6. App loads the folder contents.
7. App shows the workspace browser.

### Journey 2 — Relaunch

1. User closes the app.
2. User opens it later.
3. App restores the workspace bookmark.
4. App resolves the folder URL correctly.
5. App loads the workspace automatically.
6. App restores the last open file when it is still safe to do so.

### Journey 3 — Browse and open

1. User sees folders first and files second.
2. User taps into subfolders.
3. User taps a markdown/text file.
4. App loads the file text and editor session.
5. Editor opens using standard SwiftUI navigation.
6. If the user backs out before loading finishes, the app must not resurrect that editor later.

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
3. If the editor buffer is clean and the file can be refreshed safely, the editor updates calmly.
4. If the file disappeared or moved away from the expected path, the app shows explicit recovery UI.
5. If the buffer is dirty while the file also changed externally, the current release keeps the local buffer authoritative and does not attempt a merge. That is an explicit limitation to revisit later, not an undefined behavior.

### Journey 6 — File management

1. User creates, renames, or deletes a file in the workspace.
2. App performs the mutation safely inside the selected workspace.
3. Browser refreshes without flattening the hierarchy.
4. If the edited file changed identity, editor/session state updates safely.
5. Recent-files and restore metadata stay coherent after the mutation.

### Journey 7 — Return to the app

1. User backgrounds the app while browsing or editing.
2. User returns later.
3. App revalidates workspace access and the open file.
4. The editor must not self-conflict because of the app’s own previous saves.
5. Unsaved work is never silently discarded.

---

## Product principles

### 1. Calm behavior beats noisy cleverness

The editor should not nag during normal typing.

### 2. Trust beats feature count

The next release should prioritize file-boundary correctness over bigger features.

### 3. Canonical identity beats convenience strings

A display title and a stable file identity are different things. The architecture should treat them differently.

### 4. One consistent file-safety model

Workspace mutations and editor saves should not live on unrelated coordination models.

### 5. Minimal UI, strong behavior

The product wins by being calm, native, and dependable.

---

## Strict scope for the next release

### Included

#### Workspace

- choose one folder from Files
- persist workspace bookmark access correctly
- restore workspace automatically on relaunch when possible
- reconnect or clear when access becomes invalid
- refresh workspace contents safely

#### Browser

- recursive nested folder browsing
- keep real folders visible even when they contain no supported files
- folders listed before files
- supported markdown/text files only
- create file
- rename file
- delete file
- recent-files reopen surface

#### Editor

- open plain-text markdown/text files
- edit with `TextEditor`
- debounce autosave
- preserve newer edits when earlier save acknowledgements arrive
- save directly back to the workspace file
- reload from disk when requested
- detect missing-file conditions explicitly
- best-effort same-document external refresh while the editor is active
- persisted font family and size preferences

#### Session restore

- persist the last-open document identity using a canonical relative path
- restore that document only when it is still valid in the workspace

### Explicitly not in scope for this release

- markdown preview
- syntax highlighting
- custom text engine
- Git integration
- multi-tab editing
- plugin system
- backlinks/wiki-link systems
- app-owned mirrored storage model
- rich formatting toolbars
- advanced merge UI for dirty external divergence

---

## Near-term priorities

1. correct security-scoped bookmark handling
2. unify canonical relative-path identity across the app
3. harden delayed editor load and observation lifecycle
4. coordinate browser mutations with the same rigor as editor saves
5. prevent stale refresh results from reapplying older workspace state
6. document and harden write-durability tradeoffs
7. reduce no-change churn from fallback live observation
8. make workspace enumeration more resilient in messy real folders

---

## Current known limitations

These are explicit limits, not accidental mysteries:

- one workspace is active at a time
- one live document session is active at a time
- documents are treated as UTF-8 plain text
- in-app mutations cover files, not folder rename/move
- dirty-buffer external divergence is currently local-wins rather than merged
- live same-document refresh is best-effort and may rely on fallback polling when provider notifications are weak

---

## Success criteria for the next milestone

The next milestone is successful when all of the following are true:

- workspace restore works reliably on real devices
- canonical file identity is consistent across restore, recents, rename, and delete
- delayed loads cannot resurrect a document the user already left
- active-document autosave is still calm during ordinary typing
- newer local edits still survive asynchronous save completions
- browser mutations and editor saves feel equally trustworthy
- tests cover the highest-risk restore, mutation, and async lifecycle paths

If any of those are false, do not treat the milestone as done.
