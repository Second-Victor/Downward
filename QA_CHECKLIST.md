# QA_CHECKLIST.md

## Purpose

Use this checklist during the hardening pass so review findings are verified on real devices, not just in previews and unit tests.

This checklist is intentionally biased toward iPhone/iPad Files-provider behavior, navigation transitions, and editor trust.

---

## 1. Workspace restore and reconnect

### iCloud Drive

- choose a workspace from iCloud Drive
- kill and relaunch the app
- verify the workspace restores
- verify the last open document restores when it still exists
- rename or move the workspace externally and verify reconnect flow is sane

### Third-party Files provider

- repeat the same flow using at least one non-Apple Files provider if available
- verify restore, refresh, and file mutation behavior do not regress badly

---

## 2. Compact / regular navigation transitions

### iPhone

- open workspace
- open file
- navigate to settings and back
- search and open a search result
- verify back stack is sane throughout

### iPad

- launch in regular width
- verify sidebar + placeholder/editor detail are visible
- open settings from the browser
- open a file from the tree
- rotate to compact width if possible
- rotate back to regular
- verify destination state remains sane and no stale stack/history appears

### iPad split-screen / Stage Manager

- resize app between regular and compact-like layouts
- verify no blank detail state appears
- verify settings/editor transitions still work

---

## 3. Tree browser behavior

- expand deep folders inline
- collapse and re-expand them
- refresh the workspace
- verify surviving folders keep sensible expansion state
- verify removed folders collapse away cleanly
- verify folder taps expand/collapse and do not navigate to a separate folder screen

---

## 4. Recent files and canonical identity

- open several files in different folders
- rename one file in-app
- verify recent files still point to the renamed item
- delete one file in-app and verify the recent entry disappears
- relaunch and verify recent files still resolve correctly for surviving items

---

## 5. Editor host / inset behavior

### iPhone

- open a short file and a long file
- verify text has a small consistent horizontal inset
- verify the vertical scroll indicator stays near the right edge
- switch between files quickly and verify inset remains stable

### iPad

- repeat in portrait and landscape
- resize split view / Stage Manager width if available
- verify text inset remains stable during resize
- verify the placeholder alignment still matches the text inset

---

## 6. Autosave and conflict behavior

- type in a file and wait for autosave
- verify no noisy conflict UI appears during ordinary typing
- background the app during an unsaved edit and return
- verify local text survives and save state remains coherent
- modify the file externally if possible and verify calm revalidation behavior

---

## 7. Workspace refresh races

Manual QA cannot prove race correctness completely, but still check:

- pull to refresh repeatedly
- foreground the app during or just after refresh
- verify the tree does not visually jump backward to older contents
- verify the open editor is not cleared unexpectedly

---

## 8. Enumeration resilience

Use a mixed-content folder if available:

- hidden folders
- unsupported file types
- unreadable or provider-owned nested directories

Verify:

- the workspace still loads as much as possible
- one bad descendant does not obviously blank the whole workspace
- unsupported files are filtered without removing valid folders unnecessarily

---

## 9. File mutation behavior

- create a file at the root
- create a file in an expanded folder
- rename a file that is not open
- rename the currently open file after it is saved and conflict-free
- delete a non-open file
- delete an open clean file
- verify browser, recent files, and editor state all reconcile correctly

---

## 10. Save durability spot checks

Downward currently uses a coordinated direct-write strategy for the active document.
That means the app writes the UTF-8 editor buffer straight to the coordinated workspace file URL and
does not add an extra temp-file replacement step on top. Real-device QA must confirm that this remains
calm and trustworthy on provider-backed folders.

Minimum spot checks:

- rapid repeated autosaves
- long file save
- background/foreground around save completion
- save, kill, and reopen on `On My iPhone` / `On My iPad`
- save, kill, and reopen on iCloud Drive
- save against at least one third-party Files provider if available
- verify no obvious truncation/corruption after reopen
- verify no duplicate/noisy replace behavior shows up in observation or conflict flows
- verify rename/move/delete recovery still behaves sanely after recent saves

---

## Exit criteria for the hardening pass

Do not move on to bigger features until these are all true:

- no blank/invalid state on iPad launch or rotation
- no stale navigation history leaks across compact/regular transitions
- editor inset is stable on iPhone and iPad
- newest refresh wins under stress
- observation no longer feels chatty during idle viewing
- workspace enumeration is resilient enough for messy real folders
- save behavior remains trustworthy on device
