# ARCHITECTURE.md

## Purpose

This document describes the **current architecture as it actually exists now**.
It is not a wishlist and not a clean-room rewrite proposal.

Downward is a SwiftUI iPhone/iPad app that edits real files in one user-selected workspace folder from Files.
The codebase is now in a “stable single-workspace, single-live-document” shape.

---

## Top-level shape

The repo is organized into these layers:

- `App/`
  - composition, session state, top-level orchestration, navigation/session policies
- `Domain/`
  - core workspace/document/persistence rules and models
- `Infrastructure/`
  - platform/file-system/bookmark/logging bridges
- `Features/`
  - SwiftUI feature surfaces and their view models
- `Shared/`
  - shared models and preview support
- `Tests/`
  - unit and smoke-style tests for the risky behaviors

This is a **SwiftUI-first app**.
The UI is not supposed to own file-system semantics.
The file/document/workspace rules live below the view layer.

---

## Core current model

### 1. One active workspace

The app operates against one selected workspace folder at a time.

That workspace is represented in UI state by:

- `AppSession.workspaceSnapshot`
- `AppSession.workspaceAccessState`
- `AppSession.launchState`

The workspace is restored through bookmark-backed persistence and refreshed into a value-style `WorkspaceSnapshot`.

### 2. One active live document session

The app currently assumes **one active live document at a time**.

This is visible in:

- `AppSession.openDocument`
- `LiveDocumentManager` keeping one active `PlainTextDocumentSession`
- editor presentation always reconciling through a single shared active document slot

This is an intentional product/architecture constraint.
It is fine for the current app.
It is **not** a hidden multi-pane foundation.

Any future multi-document, multi-pane, or multi-window work would need to redesign:

- document-session ownership,
- editor presentation state,
- restore/session persistence,
- how navigation refers to active document instances.

### 3. Workspace-relative identity is the canonical file identity

The app’s canonical file identity is the **workspace-relative path**.

That identity is now used as the safest common language between:

- the browser tree,
- search results,
- recent-file entries,
- regular-detail selection,
- pending editor presentation,
- live document-session ownership.

Raw URLs still exist because the app ultimately edits real files, but **URLs are not the primary browser/editor identity source anymore**.

That distinction matters, especially on iOS/iPadOS and provider-backed storage where equivalent files may appear through slightly different URL forms.

---

## Source-of-truth boundaries

## `AppSession`

`AppSession` is the main UI-facing state container.
It owns:

- launch/access state,
- current workspace snapshot,
- current open document,
- workspace/editor error slots by surface,
- compact navigation path,
- regular-detail selection,
- pending editor presentation.

It should stay a **state container**, not a place for policy-heavy logic.

## `AppCoordinator`

`AppCoordinator` is the top-level orchestrator.
It coordinates:

- restore/reconnect,
- workspace refresh,
- mutation result application,
- editor presentation and loading,
- save/revalidate escalation,
- route/session persistence.

It should remain the orchestration entry point, but policy-heavy logic should continue to be pushed into smaller explicit seams when it becomes stable enough.

## `WorkspaceNavigationPolicy`

This owns navigation-state transforms.
It should be the first stop for rules about:

- compact vs regular transitions,
- route replacement/removal,
- editor/settings presentation state.

## `WorkspaceSessionPolicy`

This owns workspace-state application and reconciliation rules.
It should be the first stop for rules about:

- restore application,
- reconnect application,
- snapshot reconciliation,
- clearing stale editor/browser state after workspace changes.

## `WorkspaceManager`

`WorkspaceManager` owns workspace selection, restore, refresh, and file mutations.

It is the boundary for:

- bookmark-backed workspace persistence,
- snapshot creation,
- create/rename/delete file operations,
- current workspace refresh.

## `DocumentManager` / `PlainTextDocumentSession`

`DocumentManager` is the document-domain entry point.
`PlainTextDocumentSession` owns the live file session for the current active document.

That layer is responsible for:

- open/reload/revalidate/save,
- conflict mapping,
- observation,
- relocating the active session after in-app rename,
- protecting the confirmed disk version versus live in-memory edits.

This is one of the most sensitive boundaries in the app.

---

## Browser and search architecture

### Workspace snapshot model

The browser is driven by `WorkspaceSnapshot`, which holds:

- workspace root URL,
- display name,
- root nodes,
- last update timestamp.

This is still a **whole-snapshot value model**.
That is deliberate.
It keeps refresh/mutation application easy to reason about and test.

### Inline tree browser

The workspace browser is no longer folder-route navigation.
It is an inline expanding tree built from the snapshot.

Important rule:

- folder expansion state should stay keyed by **relative path**, not display text and not ad hoc URL assumptions.

### Search

Search is still snapshot-based filename/path search.
It is intentionally simple.
Search presentation is now separate from tree-row presentation so duplicate filenames can be disambiguated.

---

## Editor presentation model

The app supports two navigation layouts:

- **compact**: stack-based navigation via `NavigationStack`
- **regular**: split-view sidebar plus explicit regular-detail selection

The important current rule is:

- browser/search/recent-file opens should start from **trusted relative-path identity**,
- pending editor presentation carries both a `routeURL` and a trusted `relativePath`,
- regular-detail rendering may resolve a visible URL from the snapshot or pending presentation,
- final file access still resolves through hardened relative-path validation at the document boundary.

This is the architecture that repaired the recent “Document Unavailable” regression.
Do not regress browser-driven open back to URL-first identity.

---

## Workspace trust model

The current trust policy is intentionally strict.

### Redirected descendants

The workspace browser and document/mutation flows should not trust redirected descendants casually.
The current relative-path boundary rejects redirected descendants rather than trying to support every aliasing case.

That means the app prefers:

- a stricter workspace safety model,
- over broader symlink/provider cleverness.

This is the right tradeoff for the current product promise.

### Final access boundary

Even when browser/search identity starts from a trusted snapshot relative path, actual file access must still pass through the hardened document/workspace boundary.

That is intentional.
Trusted UI identity is not permission to bypass the file-safety boundary.

---

## Concurrency model

### Main actor

UI-facing state lives on `@MainActor` types such as:

- `AppSession`
- `WorkspaceViewModel`
- `EditorViewModel`
- `RootViewModel`

### Background work

Expensive reads stay off the main actor.
The recent hardening moved cancelable read-side work away from casual detached usage.

### Intentional detached exceptions

The codebase still keeps detached work in the narrow cases where **writes or mutations should complete even if a transient caller task is canceled**.
That is an intentional exception, not a default concurrency style.

Future contributors should not add `Task.detached` casually. If it appears, it should be because the operation is intentionally allowed to outlive view-task cancellation.

---

## Current scaling limits

These are known limits of the current design, not hidden bugs.

### 1. Whole-snapshot browser model

The browser still replaces/apply-reconciles entire snapshots.
That is appropriate now, but it is not the final shape for:

- content search,
- very large workspaces,
- highly dynamic live browser behavior.

### 2. Single active live document session

The app is not yet designed for concurrent live editor sessions.
Multi-pane or multi-window work would need an intentional redesign.

### 3. Large-file pressure points remain

The following files still deserve extra care when changing them:

- `AppCoordinator.swift`
- `WorkspaceManager.swift`
- `PlainTextDocumentSession.swift`
- `WorkspaceViewModel.swift`

That is not a call for an immediate rewrite. It is a warning not to let new complexity pile in casually.

---

## Practical contributor guidance

When adding new work:

1. Start from the current source-of-truth boundary.
2. Prefer relative-path identity for browser/editor flows.
3. Keep UI code out of file-system policy.
4. Prefer extending an existing policy seam over inflating `AppCoordinator`.
5. Do not treat current single-document behavior as a hidden multi-document foundation.
6. Update tests and docs when changing a trust/state boundary.

The current architecture is strong enough for future work **if new code keeps respecting these boundaries**.
