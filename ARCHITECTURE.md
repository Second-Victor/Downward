# ARCHITECTURE.md

## Overview

Downward is a SwiftUI-first, single-workspace markdown editor.

The current architecture is still the right one:

- one `AppSession` holds root UI state
- one `AppCoordinator` orchestrates workspace, editor, restore, and mutation flows
- one `WorkspaceManager` owns workspace selection, restore, refresh, and file mutations
- one `DocumentManager` owns open / reload / revalidate / save for the active text file
- feature view models adapt session/coordinator state into SwiftUI screens

The review conclusion is **not** “replace the architecture.” It is: **tighten the contracts at the file boundary and the async lifecycle boundary.**

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
      PlainTextDocumentSession.swift
    Errors/
      AppError.swift
      ErrorReporter.swift
      UserFacingError.swift
    Persistence/
      BookmarkStore.swift
      EditorAppearanceStore.swift
      RecentFileItem.swift
      RecentFilesStore.swift
      SessionStore.swift
    Workspace/
      SupportedFileType.swift
      WorkspaceManager.swift
      WorkspaceNode.swift
      WorkspaceSnapshot.swift

  Features/
    Editor/
    Root/
    Settings/
    Workspace/

  Infrastructure/
    Logging/
    Platform/
    WorkspaceEnumerator.swift

  Shared/
    Models/
    PreviewSupport/
```

---

## Architectural rules that should now be explicit

## 1. Canonical file identity

Every layer that persists, restores, reopens, or reconciles a file should use one canonical identity:

- workspace root identity
- workspace-relative path

`displayName` is presentation data only.

### Implications

- `WorkspaceNode` should carry canonical relative-path metadata
- recent-file pruning must not rebuild canonical paths from display strings
- rename/delete reconciliation should use canonical paths where possible
- search results may show display paths, but they should not invent identity from them

---

## 2. Security-scoped access is a first-class boundary

The app’s real root of trust is not the editor view. It is the workspace access adapter.

That layer should own:

- bookmark creation
- bookmark resolution
- validation
- start/stop access
- descendant URL resolution under the active workspace root

No other layer should need to know bookmark option details.

---

## 3. Browser mutations and editor saves must share one consistency model

Today the architecture already centralizes document I/O. The next step is to make workspace mutations equally disciplined.

That means:

- create / rename / delete should not be “looser” than save/reload
- provider-backed behavior should be reviewed under the same file-coordination assumptions
- rename/move semantics should be explicit for any live observation state

A future `WorkspaceMutationCoordinator` or equivalent helper would be a reasonable addition if it keeps these rules centralized without bloating the coordinator.

---

## 4. Observation belongs to the visible editor

The app should not keep long-lived document observation around for a file the user already left.

### Rules

- no observation should start for a document unless the matching editor is still current and visible
- observation should stop when the last matching editor route disappears
- late async loads must not reactivate a document or an observer after the user navigated away

---

## 5. Generation guards must protect the whole async path

Some parts of the code already do this well.

The rule needs to become universal:

- a stale manager result should not be applied at the coordinator layer
- a stale coordinator result should not be applied at the view-model layer
- route loss should invalidate in-flight document loads
- overlapping refreshes should have one winner

---

## 6. Write durability is an architectural choice, not an implementation detail

The document session already makes a deliberate decision to avoid an extra atomic replacement step.

That is important enough to document as an architecture choice.

### The architecture must answer:

- what write strategy is used for local/provider-backed files?
- what tradeoff is being made?
- what failure modes are acceptable?
- what regression tests protect that choice?

---

## Main responsibilities by type

### `AppSession`

Owns:

- launch state
- workspace snapshot
- current open document
- current navigation path
- current user-facing error

It should stay a simple state container.

### `AppCoordinator`

Owns:

- bootstrapping
- restore / reconnect / clear flows
- document load / activate / save / reload orchestration
- workspace mutation reconciliation into session state
- scene-activation refresh behavior

It should coordinate policy, not reimplement filesystem access.

### `WorkspaceManager`

Owns:

- selecting and restoring the workspace
- refreshing the snapshot
- create / rename / delete file mutations

It should operate on canonical workspace identity and keep raw bookmark logic outside the UI.

### `DocumentManager` / `PlainTextDocumentSession`

Own:

- opening the active document
- coordinated read/write/revalidate behavior
- live observation bridge
- conflict mapping for the active document policy

They should stay the single place that decides how the active file is read and written.

### View models

`RootViewModel`, `WorkspaceViewModel`, and `EditorViewModel` should:

- adapt coordinator/session state for SwiftUI
- own UI-only flags and prompts
- never become alternate sources of filesystem truth

---

## Current known debt to pay down

These are the most important architectural gaps left after review:

1. security-scoped bookmark options are not treated explicitly enough
2. canonical relative-path identity is not shared consistently across all layers
3. editor-load cancellation does not fully own late-result invalidation
4. workspace mutations are less coordinated than document I/O
5. stale workspace refresh results can still escape to session state
6. fallback observation is more expensive than it should be
7. enumeration is still all-or-nothing for nested failures

---

## What should not change

Do **not** “fix” the issues above by introducing:

- an app-owned mirrored document store
- a custom editor engine
- a second persistence model for file contents
- view-layer filesystem access
- broad protocol abstraction that hides the file-safety rules

The current structure is already small and good. The right next step is to harden it, not replace it.

---

## Decision checklist for future changes

Before touching `DocumentManager`, `WorkspaceManager`, `AppCoordinator`, or `EditorViewModel`, check:

1. does this preserve canonical file identity?
2. does this preserve calm autosave behavior?
3. does this keep stale async work from reapplying old state?
4. does this keep browser mutations and editor I/O on equally safe footing?
5. is there targeted regression coverage for the risky path?

If any answer is no, stop and fix that first.
