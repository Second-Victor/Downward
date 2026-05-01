# Downward Architecture

Downward is a SwiftUI-first iPhone and iPad app that edits files in a user-selected Files workspace. The selected folder is the source of truth; the app does not mirror documents into an app-owned database for normal editing.

## Layers

- `App`: scene composition, app/session state, coordination, navigation policy, mutation policy, and root UIKit/SwiftUI integration.
- `Domain`: workspace snapshots and paths, document sessions, file versions, persistence stores, themes, StoreKit entitlement state, and user-facing errors.
- `Infrastructure`: platform boundaries such as security-scoped access, folder picking, workspace enumeration, and debug logging.
- `Features`: SwiftUI feature surfaces for root, workspace browser/search/recents, editor, settings, and shared visual components.
- `Shared`: small cross-feature models, preview support, and UI helpers.
- `Tests`: focused unit and flow tests for file safety, restore, navigation, autosave, editor behavior, settings, themes, and workspace mutations.

## Workspace Model

Each app scene owns one `AppContainer`, one `AppSession`, one `AppCoordinator`, one workspace view model, and one active editor view model. The user selects a single workspace folder through Files. Bookmark persistence and restore live below the UI in `BookmarkStore`, `SecurityScopedAccessHandling`, and `LiveWorkspaceManager`.

Workspace snapshots are read views of the real folder. Browser, search, recents, restore, and editor routing should prefer trusted workspace-relative paths. Raw URL opens are compatibility paths and must be revalidated before file access.

## Document Model

Each scene currently owns one active live document session. `LiveDocumentManager` opens a real workspace file, and `PlainTextDocumentSession` owns save, autosave, revalidation, conflict state, and observation for that document. The editor buffer remains authoritative while typing; older async save or reload completions must not clobber newer in-memory edits.

## File Trust Boundary

`WorkspaceRelativePath` is the final path validation boundary for workspace-relative identity. It rejects absolute routes, `.`/`..` path control components, percent-encoded path escapes, and symlinked descendants. Existing items must resolve under the canonical workspace root. New mutation candidates are allowed only when every existing ancestor is real, in-root, and not a symlink.

`LiveWorkspaceEnumerator` keeps real folders, filters files to `SupportedFileType`, and intentionally skips hidden files/folders, package directories, symlinks, redirected descendants, and unsupported files. Finder aliases/bookmark-like items inside a workspace are not followed as navigation shortcuts; only real in-workspace folders and supported regular text files are browser/editor surfaces. Mutation, document open/save, recents, and route restore should stay aligned with this boundary.

## StoreKit Ownership

Supporter entitlements are owned by `ThemeStore` through a `ThemeEntitlementProviding` implementation. The live app uses `StoreKitThemeEntitlementStore`, while tests can use `ThemeEntitlementStore`. Tip purchases are isolated in `TipJarManager` and are surfaced only through Settings release configuration.

## Where To Change Things

- Workspace file access, restore, enumeration, and mutations: `Domain/Workspace`, `Infrastructure`, and `App` policy/coordinator seams.
- Document open/save/conflict behavior: `Domain/Document` first, then editor view models only for presentation.
- Editor UI behavior: `Features/Editor`, keeping filesystem state out of views.
- Settings and release toggles: `Features/Settings` and persistence stores.
- New product rules or release evidence: update `AGENTS.md`, `TODO.md`, and `RELEASE_QA.md` rather than adding competing checklist files.
