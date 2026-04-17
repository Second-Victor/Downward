# QA_CHECKLIST.md

## Purpose

This checklist is tuned to the current hardening priorities for Downward.
It focuses on device behavior that unit tests cannot fully prove.

Use it during and after the next hardening passes.

---

## 1. Workspace boundary safety

### Redirected descendants / symlink policy

Prepare a workspace that contains at least one redirected descendant if practical.
If device setup is hard, prepare it on macOS first and then open the folder on device.

Verify:

- redirected descendants do not appear unexpectedly in the browser if the policy is to skip them,
- or they are explicitly rejected if the policy is to reject them,
- document open/save/rename/delete cannot escape the chosen workspace through redirected paths.

---

## 2. Refresh vs mutation correctness

### Manual stress checks

- start a workspace refresh,
- while refresh is active, attempt create/rename/delete from the browser if the UI allows it,
- repeat on a larger folder and on iPad.

Verify:

- the browser does not jump backward after mutation,
- the open editor does not reconcile against stale tree state,
- recent files remain coherent,
- no deleted/renamed file visually reappears because an older refresh won late.

---

## 3. Cancellation and navigation churn

### Document load / rapid switching

- open file A,
- quickly open file B,
- go back,
- open settings,
- return to the browser,
- repeat on compact and regular layouts.

Verify:

- the late result from an old load never becomes the visible editor,
- hidden old work does not reopen stale documents,
- editor load errors remain scoped to the document that failed.

### Refresh cancellation

- trigger pull to refresh repeatedly,
- navigate away mid-refresh if possible,
- background/foreground during refresh.

Verify:

- loading indicators reset,
- the tree does not flash back to older contents,
- no obvious stale refresh application occurs.

---

## 4. Workspace restore / reconnect / selection failure

### Restore and reconnect

- choose a workspace from iCloud Drive,
- kill and relaunch the app,
- verify restore,
- reconnect after external move/rename if possible,
- confirm last-open document behavior still matches expectations.

### Failed selection recovery

- attempt to choose a workspace that fails initial loading if you can reproduce one,
- then relaunch.

Verify:

- a failed new selection does not become a confusing persisted restore target,
- replacing an active workspace with a bad selection does not destroy the existing good workspace state.

---

## 5. Editor trust behavior

### Autosave

- type continuously,
- pause and let autosave run,
- switch files quickly,
- background and foreground around a pending save.

Verify:

- no noisy conflict UI for ordinary typing,
- newer edits survive late save acknowledgements,
- no stale save result clobbers later text.

### Observation

- leave a clean file open,
- modify it externally if possible,
- leave it idle for a while.

Verify:

- external changes are still detected,
- the app does not feel chatty or constantly revalidating without reason,
- fallback mode (if active) behaves calmly.

---

## 6. Search and browser clarity

- search for common names like `README`, `Notes`, `Inbox`,
- use a workspace with duplicate filenames in different folders if possible.

Verify:

- search results clearly show enough path context to disambiguate duplicates,
- opening a search result still opens the correct file,
- returning from search leaves browser/editor state coherent.

---

## 7. Recent files and restore identity

- open several files,
- rename one in-app,
- delete one in-app,
- restore/reconnect the workspace if possible.

Verify:

- renamed items update cleanly in recents,
- deleted items disappear,
- restore/reconnect does not unexpectedly wipe usable recents,
- the chosen workspace identity model behaves predictably.

---

## 8. iPhone / iPad layout correctness

### iPhone

- browser → editor → settings → browser,
- search → open file,
- rapid file switching.

### iPad

- regular-width launch with sidebar + detail,
- placeholder detail with no file selected,
- open file from tree,
- open settings and return,
- rotate and resize split-screen / Stage Manager if available.

Verify:

- no blank detail view,
- compact/regular transitions stay sane,
- browser/editor state remains coherent across layout changes.

---

## 9. Save durability spot checks

The app currently uses a coordinated direct-write strategy for the active document.
That strategy should stay under real-device scrutiny.

Minimum checks:

- repeated autosaves,
- larger text files,
- background/foreground during save,
- iCloud Drive,
- `On My iPhone` / `On My iPad`,
- at least one third-party Files provider if available.

Verify:

- reopened files contain the expected text,
- no obvious truncation/corruption,
- no duplicated/noisy replace behavior,
- no new conflict churn after ordinary saves.
