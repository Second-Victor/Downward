# QA_CHECKLIST.md

## Purpose

This checklist is for the **current post-hardening codebase**.

It is no longer focused on proving whether the trust/cancellation/navigation fixes exist at all.
It is focused on making sure future feature work does not regress the boundaries that now matter most.

---

## 1. Browser/search/editor open identity

### Tree rows

- Launch into a valid workspace.
- Open a top-level file from the tree.
- Open a nested file from the tree.
- Open several files in quick succession.

Verify:

- the tap reliably opens the intended file,
- no random no-op taps occur,
- no false “Document Unavailable” error appears for visible valid files.

### Search results

- Search for a filename that exists once.
- Search for a filename that exists in multiple folders.
- Open each result.

Verify:

- duplicate filenames are visually disambiguated,
- the correct file opens every time,
- returning to the browser keeps state coherent.

---

## 2. Compact vs regular navigation

### iPhone / compact

- browser → editor → settings → browser,
- search → editor,
- recent file → editor,
- rapid file switching.

Verify:

- route changes remain coherent,
- no stale editor title/text appears,
- no old editor route reappears unexpectedly.

### iPad / regular split view

- launch with no file selected,
- open file from tree,
- open file from search,
- open settings and return,
- rotate and resize split-screen / Stage Manager.

Verify:

- no blank detail view,
- regular detail follows the intended file,
- route URL differences do not break trusted relative-path loading,
- returning from settings leaves the browser/editor coherent.

---

## 3. Restore, reconnect, and workspace replacement

- choose a workspace,
- relaunch and confirm restore,
- move/rename the workspace externally if you can reproduce it,
- reconnect when prompted,
- replace a working workspace with another folder.

Verify:

- restore stays calm,
- reconnect does not destroy working state unexpectedly,
- recent files remain sensible,
- a failed replacement does not poison restore state.

---

## 4. Autosave and external change behavior

- type normally for a while,
- pause and let autosave complete,
- switch files during and after autosave,
- background/foreground the app,
- modify the file externally if possible.

Verify:

- autosave stays quiet,
- newer edits survive late save completion,
- clean external changes refresh calmly,
- conflict UI appears only for real exceptional cases.

---

## 5. Browser mutation coherence

- create a file,
- rename a file,
- delete a file,
- repeat while a refresh is likely or while the UI is busy.

Verify:

- the browser does not jump backward,
- the open editor remains coherent after rename/delete,
- recent files update sensibly,
- refresh and mutation results do not fight visually.

---

## 6. Workspace trust checks

If practical, test with a workspace containing redirected descendants prepared elsewhere.

Verify:

- redirected descendants are not surfaced unexpectedly,
- visible in-workspace files still open normally,
- save/rename/delete cannot escape the chosen workspace.

---

## 7. Real-device provider coverage

Minimum useful spread:

- `On My iPhone` / `On My iPad`
- iCloud Drive
- at least one third-party Files provider if available

Verify across all three when possible:

- restore,
- open from browser,
- search open,
- autosave,
- rename/delete/create,
- reopen after relaunch.
