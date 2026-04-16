# ARCHITECTURE.md

## Overview

Downward is still best understood as four core layers:

1. **app/session orchestration**
2. **workspace boundary**
3. **document boundary**
4. **SwiftUI feature surfaces**

That overall structure is still good.

The repo does **not** need an architecture rewrite.
It needs clearer ownership at a few boundaries that recently became more complex.

---

## Current source-of-truth map

### App layer

- `AppContainer` wires concrete live and preview dependencies
- `AppSession` holds root UI state
- `AppCoordinator` orchestrates restore, refresh, selection, mutation, and document/session transitions
- `RootViewModel` adapts app/session state into launch/root UI

### Workspace layer

- `WorkspaceManager` owns restore, selection, refresh, and browser-side file mutations
- `WorkspaceEnumerator` builds snapshots
- `RecentFilesStore` persists workspace-relative recent file identity
- `WorkspaceViewModel` turns snapshot state into browser/search/tree UI state

### Document layer

- `DocumentManager` owns open / reload / revalidate / save / observe
- `PlainTextDocumentSession` is the live file-boundary worker for one active document session
- `EditorViewModel` owns text changes, autosave, conflict presentation, and observation response

### UI layer

- `RootScreen` chooses launch / compact / regular shells
- `WorkspaceScreen` and `WorkspaceFolderScreen` render the inline tree browser
- `EditorScreen` renders the active text editor
- `SettingsScreen` owns workspace and appearance settings UI

---

## What is currently right

These are the architecture choices to keep:

### 1. Coordinator + managers + focused view models

The coordinator/manager split is readable and gives you real seams for tests.
Do not collapse file-system behavior back into views.

### 2. Canonical workspace-relative identity

The code is on the right path when it treats relative path identity as canonical and display names as presentation-only.
Keep building on that.

### 3. One active document pipeline

The current app is still effectively a one-open-document editor.
That constraint is useful because it keeps autosave and observation logic tractable.

### 4. Browser tree state is view-model state, not route state

Folder expansion is now inline and keyed by canonical folder-relative paths.
That is the right long-term model for a file browser.

---

## Current architectural fault lines

## 1. Navigation ownership is not clean enough yet

### Current shape

- compact mode uses `session.path` as actual `NavigationStack` state
- regular mode does not truly use a bound path stack, but still derives detail state partly from `session.path`
- old route concepts still exist even though folder browsing is now inline

### Desired shape

- compact stack state is compact-only
- regular detail selection is regular-only
- folder browsing does not rely on route history at all

### Why this matters

This is now the main structural risk for future features.

If not cleaned up, every new feature touching navigation will have to understand both:

- real path history
- hidden “detail selection by inspecting path” behavior

That increases bug surface area around iPad, rotation, search, settings, and future multi-document ideas.

---

## 2. The editor host is still a soft boundary

### Current shape

`EditorScreen` owns:

- the SwiftUI editor view
- placeholder behavior
- the current UIKit inset workaround

### Desired shape

The editor host boundary should explicitly own:

- content inset behavior
- scroll-indicator expectations
- focus/update lifecycle
- any future editor bridge behavior

### Why this matters

The editor is now central enough that its UIKit/SwiftUI integration details should not live as tactical logic inside the screen file forever.

---

## 3. Refresh ownership stops too low in the stack

### Current shape

`LiveWorkspaceManager` protects `currentSnapshot` from stale writes, but stale snapshots can still be returned to the caller and applied in app/session state.

### Desired shape

The “newest refresh wins” rule should be enforced at the full application boundary, not just the manager cache boundary.

### Why this matters

Snapshot authority drives:

- browser tree contents
- recent-files pruning
- active-document reconciliation
- reconnect/error flows

---

## 4. Observation fallback is still implementation-first rather than policy-first

### Current shape

The fallback emits synthetic changes on a fixed cadence and relies on the editor view model to decide when to revalidate.

### Desired shape

Observation should expose a clearer policy:

- normal mode: presenter-driven
- degraded mode: metadata-gated and cheap
- no-change steady state: quiet

### Why this matters

This is a classic place where “it works” can still be too noisy for real devices.

---

## 5. File-boundary policy is still partially implicit

Two important policies are not yet owned clearly enough:

- what to do with unreadable / hidden / provider-generated descendants during enumeration
- what durability guarantees the direct-write save path is intentionally making

Those do not require new abstractions, but they do require explicit architecture language.

## Document Write Strategy

### Decision

Downward intentionally keeps a **coordinated direct-write** save strategy for the active editor document.

That means:

- the app coordinates the real workspace file URL with `NSFileCoordinator`
- it writes the current UTF-8 editor buffer directly to that coordinated URL
- it does **not** add a second temp-file replacement or app-owned staging layer on top of that write

### Why this is the chosen policy

The app edits the user-selected workspace in place, often through Files/iCloud/provider-backed folders.
For this product, preserving a calm live-file boundary is more important than adding an extra replacement
step that may:

- manufacture another filesystem replacement event
- make provider behavior noisier or less predictable
- complicate file identity for observation/revalidation flows
- drift away from the “edit the real workspace file directly” trust model

### Recovery expectations

This is not claiming desktop-class crash-safe journaling.
The product contract is narrower and explicit:

- a normal successful save writes the current editor buffer back to the real workspace path
- newer in-memory edits must survive older save acknowledgements
- missing/moved paths surface explicit recovery instead of silent data loss
- real durability and provider behavior must still be validated on device, especially for iCloud Drive
  and third-party Files providers

### What should change only with explicit intent

Future contributors should not replace this with temp-file swap, app-owned mirror storage, or any other
write strategy as a cleanup-by-default change. If the write strategy changes, it should be treated as a
product/architecture decision with updated QA expectations and save-path tests.

---

## Proposed architecture adjustments

These are **small structural adjustments**, not a rewrite.

## Adjustment A — Split navigation state by layout role

Suggested shape:

- `compactPath: [AppRoute]`
- `regularDetail: RegularWorkspaceDetailSelection`

where regular detail selection is an explicit model, not inferred from compact path history.

## Adjustment B — Introduce an editor host boundary file

Suggested shape:

- `EditorScreen` remains the feature screen
- a dedicated host/bridge type owns any UIKit `TextEditor` inset/configuration behavior

That keeps editor UI policy out of general screen composition.

## Adjustment C — Move refresh winner policy to the application edge

Either:

- coordinator owns refresh generation, or
- manager never returns stale refresh results

Pick one and document it.

## Adjustment D — Promote file policy to documented contracts

Write down:

- enumeration skip/fail policy
- direct-write durability policy
- expected QA coverage for provider-backed folders

---

## Architecture invariants to preserve

Any future changes should preserve these:

1. the workspace folder remains the source of truth
2. canonical relative path remains the identity for restore/recent/reconcile logic
3. newer in-memory edits survive older save acknowledgements
4. routine autosave remains quiet
5. live document observation must not create noisy self-conflicts
6. file mutations remain coordinated
7. views do not perform raw file-system work directly

---

## What not to do next

Do **not** do these as a reaction to current issues:

- do not replace the whole architecture with a document database
- do not move file-system coordination into SwiftUI views
- do not bolt more route cases onto the current mixed compact/regular path model
- do not spread more editor bridge logic across unrelated view files
- do not add broad abstraction layers before the ownership boundaries are clarified

---

## Current best next move

The strongest next move is a narrow hardening pass that:

1. splits navigation ownership
2. isolates the editor host boundary
3. closes the stale-refresh hole
4. defines observation and file-boundary policy explicitly

That will make the current architecture strong enough for the next real feature wave.
