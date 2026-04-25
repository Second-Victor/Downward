# TASKS.md

## Purpose

This is the active fix-tracking backlog for Downward. It should stay checkable and current so completed work can be marked off as fixes land. Use `PLANS.md` for the deeper engineering plan behind each item, and `CODE_REVIEW.md` for review rationale.

## Current state

The project is no longer in an emergency-hardening phase. The main architecture foundations are in place: trusted workspace access, relative-path-first routing, safer restore/reconnect flows, a split editor bridge, quiet autosave cancellation, explicit syntax visibility, real settings pages, and persistent custom themes.

The remaining work is mostly validation, production polish, scalability, and preventing large files from accumulating more responsibilities.

## Completed foundations

- [x] Keep final file-system trust checks in `WorkspaceManager`/`WorkspaceRelativePath`.
- [x] Route workspace document opening by relative path instead of display name or raw URL where possible.
- [x] Keep `.json` workspace files openable as normal text documents.
- [x] Keep theme JSON import as an explicit Settings action, not an implicit file-open side effect.
- [x] Preserve newer in-memory edits when save acknowledgements arrive after additional typing.
- [x] Cancel autosave tasks cleanly when an editor session is closed or replaced.
- [x] Keep the editor representable thin by splitting coordinator, keyboard accessory, keyboard geometry, and text-view subclass responsibilities.
- [x] Preserve full-height editor layout and first-line top clearance behavior.
- [x] Keep markdown syntax visibility controlled by editor appearance state.
- [x] Persist built-in and custom theme selection.
- [x] Persist custom themes through `ThemeStore`/`ThemePersistenceService`.
- [x] Support JSON theme import/export through `ThemeExchangeDocument` and `ThemeImportService`.
- [x] Keep settings as a sheet-based hierarchy on compact and regular-width layouts.
- [x] Keep StoreKit tips, legal URLs, ratings/review routing, line numbers, and larger heading text as explicitly future-backed features.

## P0 validation gate before release

No new P0 code defect was found in the 2026-04-24 static review, but release validation is still open.

- [ ] Build the app in Xcode.
- [ ] Run the focused XCTest suites for workspace restore, document manager, editor autosave, editor undo/redo, markdown rendering, settings, themes, and keyboard geometry.
- [ ] Run the app on at least one iPhone simulator.
- [ ] Run the app on at least one iPad simulator or device.
- [ ] Manually verify workspace selection, restore, reconnect, recent-file reopening, and stale workspace handling.
- [ ] Manually verify editing, autosave, close/reopen, and rapid document switching.
- [ ] Manually verify keyboard accessory behavior on first keyboard presentation and during interactive dismissal.
- [ ] Manually verify Settings sheet presentation on compact and regular width.
- [ ] Record build/test/manual QA results here before treating the release as ready.

## P1 active work

### 1. Align keyboard accessory and theme contract

Current finding: the shipping code deliberately keeps the accessory host clear/non-opaque and themes the controls/tint. Older docs described a painted accessory underlay. The docs have been corrected; now the runtime contract needs to be protected.

- [x] Add a regression test for `EditorKeyboardAccessoryToolbarView` proving the wrapper stays clear and non-opaque.
- [x] Add or keep a regression test proving toolbar tint follows the resolved editor theme.
- [ ] Verify there is no white band on first keyboard presentation.
- [ ] Verify there is no full-screen background takeover caused by accessory host painting.
- [ ] Verify light, dark, and at least one custom non-standard theme.
- [ ] Verify interactive keyboard dismissal.
- [ ] Keep `CODE_REVIEW.md`, `PLANS.md`, and this file aligned if the accessory strategy changes again.

Done when:

- [ ] Device/simulator QA confirms the accessory behavior is stable.
- [x] Tests encode the clear-host/tinted-controls contract.

### 2. Harden theme import/export UX

- [ ] Decide whether export means “current editor draft” or “last saved theme”.
- [ ] Rename/copy the export action if current unsaved form state is intentionally exported.
- [ ] Add a clear user-facing warning for low-contrast themes if save/export remains allowed.
- [x] Reject or clearly handle unsupported future `schemaVersion` values.
- [x] Improve import errors for invalid JSON.
- [x] Improve import errors for unsupported schema.
- [x] Improve import errors for duplicate names.
- [x] Improve import errors for oversized files.
- [ ] Improve import errors for bundle failures.
- [ ] Verify import/export through Files, iCloud Drive, and one third-party provider.
- [x] Add tests for duplicate names.
- [x] Add tests for same-ID replacement.
- [ ] Add tests for selected-theme deletion fallback.
- [ ] Add tests for legacy JSON.
- [ ] Add tests for file-size rejection.

Done when:

- [ ] Import/export failures are specific and user understandable.
- [ ] Theme exchange behavior is covered by tests and manual Files-provider QA.

### 3. Continue renderer scalability work

- [ ] Split markdown recognition/scanning from UIKit styling.
- [ ] Keep theme role mapping out of parsing code.
- [ ] Keep hidden-syntax reveal decisions testable without a live `UITextView`.
- [ ] Preserve same-line current-line restyle as the fast path.
- [ ] Preserve deferred full rerender for line breaks, paste, block-context changes, and selection-driven reveal changes.
- [ ] Add large-document performance fixtures.
- [ ] Avoid adding tables, footnotes, or richer code-block behavior until the renderer split is underway.

Done when:

- [ ] Renderer tests can exercise syntax recognition without attributed-string styling.
- [ ] Large-file typing has an explicit performance budget.

### 4. Add workspace snapshot lookup indexes

- [ ] Build per-snapshot indexes for relative-path and file-identity lookup.
- [ ] Use indexes in navigation, recents, mutation reconciliation, and restore paths.
- [ ] Keep recursive traversal as a correctness fallback while the index lands.
- [ ] Add tests for duplicate names in different folders.
- [ ] Add tests for rename, move, delete, and case-only rename.
- [ ] Add tests for stale recent-file paths after a workspace refresh.

Done when:

- [ ] Path/file resolution no longer repeatedly walks the whole snapshot tree in common flows.
- [ ] Mutation tests prove index rebuild/invalidation behavior.

### 5. Keep coordinator and workspace view model from growing again

- [ ] Keep new workspace decision logic in `WorkspaceNavigationPolicy`, `WorkspaceMutationPolicy`, or focused helpers.
- [ ] Avoid adding feature-specific UI rules directly to `AppCoordinator`.
- [ ] Extract mutation-result reconciliation if rename/move/delete flows grow.
- [ ] Keep search-specific state in `WorkspaceSearchModel`.
- [ ] Extract workspace prompt/command state if more browser dialogs are added.

Done when:

- [ ] New features add small policies/models instead of expanding coordinator/view-model switchboards.

### 6. Finish runtime QA for Files-provider behavior

- [ ] Select a local workspace.
- [ ] Select an iCloud Drive workspace.
- [ ] Select a third-party provider workspace if available.
- [ ] Rename a folder outside the app and confirm refresh/reconnect behavior.
- [ ] Move/delete an open document outside the app and confirm the app surfaces a safe state.
- [ ] Import a theme from Files.
- [ ] Export a theme to Files.
- [ ] Open a normal `.json` file from the workspace and confirm it opens as text.

Done when:

- [ ] Real Files-provider results are recorded in this checklist.

## P2 cleanup and polish

- [ ] Add a dedicated release checklist file if this task list becomes too crowded.
- [ ] Replace placeholder-backed Settings actions when StoreKit, review routing, and legal URL infrastructure are ready.
- [ ] Add line-number support only after renderer/layout performance is protected.
- [ ] Add larger heading text only after accessibility, dynamic type, and markdown layout behavior are tested.
- [ ] Consider extracting renderer theme role tables into smaller value types.
- [ ] Consider extracting workspace expansion/path rewrite helpers from `WorkspaceViewModel`.
- [ ] Keep `ARCHITECTURE.md` updated when ownership boundaries change.

## Guardrails for future changes

- [ ] Do not bypass workspace-relative path validation with raw URLs from UI code.
- [ ] Do not make normal document opening trigger theme import automatically.
- [ ] Do not add long-lived unstructured tasks without cancellation ownership and stale-result guards.
- [ ] Do not add more markdown features to `MarkdownStyledTextRenderer` without preserving the current-line fast path.
- [ ] Do not paint UIKit keyboard host/container backgrounds unless device QA proves there is no wider visual side effect.
- [ ] Do not mark a UI geometry fix complete without iPhone and iPad verification.

## Files to update when priorities change

- [ ] `TASKS.md` for active checklists and fix status.
- [ ] `PLANS.md` for detailed implementation sequencing.
- [ ] `CODE_REVIEW.md` for review findings and severity changes.
- [ ] `ARCHITECTURE.md` when ownership boundaries or module responsibilities change.
