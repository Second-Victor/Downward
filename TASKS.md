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

- [x] Build the app in Xcode.
- [x] Run the focused XCTest suites for workspace restore, document manager, editor autosave, editor undo/redo, markdown rendering, settings, themes, and keyboard geometry.
- [x] Run command-line app smoke coverage on at least one iPhone simulator.
- [x] Run command-line app smoke coverage on at least one iPad simulator or device.
- [ ] Manually verify workspace selection, restore, reconnect, recent-file reopening, and stale workspace handling.
- [ ] Manually verify editing, autosave, close/reopen, and rapid document switching.
- [ ] Manually verify keyboard accessory behavior on first keyboard presentation and during interactive dismissal.
- [ ] Manually verify Settings sheet presentation on compact and regular width.
- [x] Record build/test/command-line smoke results in `RELEASE_QA.md`.
- [ ] Record manual QA results in `RELEASE_QA.md` before treating the release as ready.

Verification note (2026-04-25): `xcodebuild -list` identified the `Downward` scheme. `xcodebuild build -scheme Downward -destination 'generic/platform=iOS Simulator'` passed after the named simulator build destination was unavailable during build discovery. `xcodebuild test -scheme Downward -destination 'platform=iOS Simulator,name=iPhone 17'` passed on iPhone 17, iOS 26.4 Simulator with 341 passed, 2 skipped, 0 failed. The full run covered the required workspace snapshot/search/recent-file, document manager, editor autosave, editor undo/redo, markdown scanner/style/renderer/performance, settings/theme, keyboard geometry, restore, mutation, and smoke suites. An initial full test run failed in `EditorAutosaveTests.testLiveObservationReloadsCleanEditorAfterOutsideWrite()`; this batch fixed that test's observation timing and reran the focused case plus the full suite successfully.

Runtime smoke note (2026-04-25): `RELEASE_QA.md` now records the dedicated runtime QA checklist and the latest command-line simulator smoke pass. `xcodebuild build` passed on iPhone 17 and iPad Pro 13-inch (M5), both on iOS 26.4 Simulator. Focused app-hosted smoke/restore/mutation tests passed on both simulators with 55 passed, 0 skipped, 0 failed per destination. This was not manual visual, real-device, Files-provider, or keyboard-interaction QA.

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

- [x] Decide whether export means “current editor draft” or “last saved theme”.
- [x] Rename/copy the export action if current unsaved form state is intentionally exported.
- [x] Add a clear user-facing warning for low-contrast themes if save/export remains allowed.
- [x] Reject or clearly handle unsupported future `schemaVersion` values.
- [x] Improve import errors for invalid JSON.
- [x] Improve import errors for unsupported schema.
- [x] Improve import errors for duplicate names.
- [x] Improve import errors for oversized files.
- [x] Improve import errors for bundle failures.
- [ ] Verify import/export through Files, iCloud Drive, and one third-party provider.
- [x] Add tests for duplicate names.
- [x] Add tests for same-ID replacement.
- [x] Add tests for selected-theme deletion fallback.
- [x] Add tests for legacy JSON.
- [x] Add tests for file-size rejection.

Done when:

- [x] Import/export failures are specific and user understandable.
- [ ] Theme exchange behavior is covered by tests and manual Files-provider QA.

### 3. Continue renderer scalability work

Batch reconciliation note (2026-04-25): the code already has `MarkdownSyntaxScanner`, `MarkdownSyntaxVisibilityPolicy`, and `MarkdownSyntaxStyleApplicator`, and `MarkdownStyledTextRenderer` uses the scanner. This pass added scanner-only coverage for code-block protection, merged protected ranges, and inline matching exclusions without changing rendered output.

Inline split note (2026-04-25): scanner output now includes delimited inline style spans for emphasis, strong, bold-italic, nested marker combinations, and strikethrough. The renderer consumes those values and delegates the font/color/marker styling choice to `MarkdownSyntaxStyleApplicator`.

Performance budget note (2026-04-25): large-document markdown rendering now has automated work-scope regression coverage. Initial open/theme restyle may render the whole document, ordinary same-line typing must stay on a current-line render budget of 512 characters or less in the large fixture, and structural line-break edits must defer the full-document rerender.

Latency measurement note (2026-04-25): local XCTest clock metrics now cover the 2,000-line, 58,800 UTF-16 character markdown fixture on iPhone 17 iOS 26.4 Simulator from a MacBook Pro with Apple M4 Pro, macOS 26.4.1. Same-line typing/current-line restyle averaged 1.81 ms over 5 samples, paste/full render of a 64,094-character pasted document averaged 198.87 ms, and theme-switch restyle averaged 196.11 ms. These measurements are regression guidance only, not a release guarantee across devices.

- [x] Split the first markdown recognition/scanning slice from UIKit styling.
- [x] Keep theme role mapping out of parsing code for the extracted scanner slice.
- [x] Keep hidden-syntax reveal decisions testable without a live `UITextView`.
- [x] Extract a focused markdown styling/application helper from the renderer.
- [x] Add focused tests for the extracted styling/application helper.
- [x] Preserve same-line current-line restyle as the fast path.
- [x] Preserve deferred full rerender for line breaks, paste, block-context changes, and selection-driven reveal changes.
- [x] Add large-document performance fixtures.
- [x] Measure typing latency in long documents.
- [x] Measure paste latency in long documents.
- [x] Measure theme-switch restyle latency in long documents.
- [x] Avoid adding tables, footnotes, or richer code-block behavior until the renderer split is underway.

Done when:

- [x] Renderer tests can exercise syntax recognition without attributed-string styling.
- [x] Renderer styling/application logic has focused helper coverage.
- [x] Large-file typing has an explicit performance budget.
- [x] Long-document renderer latency has local measured baselines for typing, paste/full render, and theme restyle.

### 4. Add workspace snapshot lookup indexes

Batch reconciliation note (2026-04-25): `WorkspaceSnapshot` owns cached URL/path indexes, lookup APIs use them before private recursive fallbacks, `WorkspaceSearchEngine` carries relative paths through `snapshot.forEachFile`, and `RecentFilesStore.pruneInvalidItems(using:)` uses `snapshot.relativeFilePaths()`.

Folder mutation coverage note (2026-04-25): focused resolver tests now cover replacement snapshots after folder rename, folder move, ancestor-folder delete, and a deterministic 1,440-file synthetic tree lookup/order regression. Mutation-flow coverage now verifies moving a folder that contains the open document rewrites editor route, open-document identity, restore state, and recents, and deleting an ancestor folder of the open document closes the editor, clears restore state, prunes recents, and leaves the refreshed snapshot without the stale relative path.

- [x] Build per-snapshot indexes for relative-path and normalized URL lookup.
- [x] Use indexes in navigation, recents, mutation reconciliation, and restore paths.
- [x] Keep recursive traversal as a correctness fallback while the index lands.
- [x] Add tests for duplicate names in different folders.
- [x] Add tests for rename, move, delete, and case-only rename.
- [x] Add tests for folder rename and folder move.
- [x] Add tests for deleting an ancestor folder of the open document.
- [x] Add tests for stale recent-file paths after a workspace refresh.
- [x] Add a deterministic large synthetic tree lookup regression.

Done when:

- [x] Path/file resolution no longer repeatedly walks the whole snapshot tree in common flows.
- [x] Mutation tests prove index rebuild/invalidation behavior.

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

- [ ] Real Files-provider results are recorded in `RELEASE_QA.md`.

## P2 cleanup and polish

- [x] Add a dedicated release checklist file if this task list becomes too crowded.
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
