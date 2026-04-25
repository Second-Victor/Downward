# CODE_REVIEW.md

## 2026-04-24 static review refresh

### Scope and verification

This review covers the uploaded `Downward.zip` project after the latest code changes. I reviewed the app sources, domain/infrastructure layers, feature modules, tests, and steering markdown files.

Verification status:

- [x] Static source review completed.
- [x] Steering docs refreshed to match the current code direction.
- [x] Xcode build completed.
- [x] XCTest suite completed.
- [ ] Simulator/device manual QA completed.

Verification note (2026-04-25): `xcodebuild -list` found the `Downward` scheme. A simulator-specific build for `name=iPhone 17` could not resolve a concrete device during build discovery, so the build gate was run with `xcodebuild build -scheme Downward -destination 'generic/platform=iOS Simulator'` and passed. The full XCTest suite then passed with `xcodebuild test -scheme Downward -destination 'platform=iOS Simulator,name=iPhone 17'` on iPhone 17, iOS 26.4 Simulator: 341 passed, 2 skipped, 0 failed. An initial suite run exposed a timeout in `EditorAutosaveTests.testLiveObservationReloadsCleanEditorAfterOutsideWrite()`; this batch fixed the test to use the existing deterministic fallback-observation seam and reran the focused test plus the full suite successfully. Manual simulator/device QA remains open.

Runtime smoke note (2026-04-25): `RELEASE_QA.md` now records the runtime QA matrix and latest QA run. `xcodebuild build` passed on iPhone 17 and iPad Pro 13-inch (M5), both on iOS 26.4 Simulator, and focused app-hosted smoke/restore/mutation tests passed on both destinations with 55 passed, 0 skipped, 0 failed per destination. This is command-line smoke evidence only; manual visual, real-device, Files-provider, keyboard, and Settings hierarchy QA remain open.

### Snapshot metrics

| Area | Current snapshot |
| --- | --- |
| Swift files reviewed | 115 |
| Swift lines reviewed | 32,138 |
| Largest app file | `Downward/Features/Editor/MarkdownStyledTextRenderer.swift` — 1,612 lines |
| Largest domain file | `Downward/Domain/Workspace/WorkspaceManager.swift` — 1,509 lines |
| Largest coordinator file | `Downward/App/AppCoordinator.swift` — 1,336 lines |
| Largest feature view model | `Downward/Features/Workspace/WorkspaceViewModel.swift` — 1,049 lines |

### Review verdict

No new P0 release-blocking defect was found by static review. The current codebase looks materially healthier than the previous emergency-hardening state: workspace safety, editor layout, restore flows, autosave, theme persistence, and settings structure all have clearer ownership and stronger tests.

Do not treat that as release-ready until the validation checklist passes. The remaining risk is concentrated in runtime UI behavior, theme import/export polish, renderer scalability, and a few large-file/large-tree architecture seams.

## What is now in good shape

- [x] Workspace trust remains centred in `WorkspaceManager` and `WorkspaceRelativePath` rather than being spread through UI code.
- [x] Relative-path-first document routing is explicit through `WorkspaceNavigationPolicy`, `WorkspaceViewModel`, and workspace snapshot helpers.
- [x] Restore/reconnect flows have better stale-result guards and clearer coordinator/session ownership.
- [x] Editor autosave cancellation is now guarded around `Task.sleep`, and cancelled autosave tasks no longer fall through to save work.
- [x] Save acknowledgement merging preserves newer in-memory edits instead of blindly replacing state with the saved version.
- [x] The editor bridge is split into focused collaborators instead of one monolithic representable file.
- [x] Full-height editor sizing, top underlay, first-line placement, and document-open viewport reset are treated as product behavior.
- [x] Markdown syntax visibility is an explicit editor appearance setting.
- [x] Current-line restyling reduces the cost of ordinary same-line edits, with deferred full rerendering still available for broader markdown-context changes.
- [x] Settings now have a real sheet-based hierarchy rather than placeholder-only surfaces.
- [x] Built-in and custom theme selection persist through `EditorAppearanceStore`, `ThemeStore`, and `ThemePersistenceService`.
- [x] JSON theme import/export is routed through explicit theme settings flows rather than through normal document opening.
- [x] `.json` workspace files can open as text editor documents while explicit theme import stays separate.
- [x] Tests cover many of the important seams: workspace restore, document manager behavior, editor undo/redo, autosave, keyboard geometry, renderer behavior, settings model, theme store, and theme exchange documents.

## Current findings

### [P1] Keyboard accessory/theme contract needs final runtime verification and docs discipline

**Status:** regression coverage now matches the clear-host/tinted-controls contract; runtime verification still open.

Relevant files:

- `Downward/Features/Editor/EditorKeyboardAccessoryToolbarView.swift`
- `Downward/Features/Editor/EditorKeyboardGeometryController.swift`
- `Downward/Features/Editor/MarkdownEditorTextView.swift`
- `Downward/Features/Editor/EditorScreen.swift`
- `Tests/EditorKeyboardGeometryControllerTests.swift`
- `Tests/MarkdownEditorTextViewSizingTests.swift`

The current accessory implementation deliberately keeps the accessory wrapper clear and non-opaque, and applies tint/appearance to the toolbar controls. This is different from earlier docs that described a painted accessory underlay matching the editor surface. The code comment is clear that painting the accessory host previously caused broader keyboard-host/editor background side effects.

Action items:

- [x] Keep docs aligned with the current contract: editor/TextKit/renderer colors are theme-driven, but the keyboard accessory background remains clear/material-hosted rather than painted as an editor-surface underlay.
- [x] Add or keep a focused regression test that asserts the accessory wrapper remains clear and non-opaque while toolbar tint follows the resolved theme.
- [ ] Verify on iPhone and iPad that the accessory does not flash white, does not inherit an unwanted editor-wide background, and behaves correctly during interactive keyboard dismissal.
- [ ] Verify the behavior with at least one non-standard custom theme, not just system light/dark.

Follow-up note (2026-04-24): `Tests/EditorUndoRedoTests.swift` now asserts that `KeyboardAccessoryToolbarView` stays clear/non-opaque across theme changes and that toolbar tint tracks the resolved accent. Runtime QA is still required because this environment cannot complete simulator-backed XCTest runs.

Done when:

- [ ] Manual QA confirms no first-presentation white band, no unexpected full-screen editor background takeover, and correct control tint in light, dark, and custom themes.
- [ ] `PLANS.md`, `TASKS.md`, and this review all describe the same accessory contract.

### [P1] Theme import/export needs a production hardening pass

**Status:** future schema rejection, direct invalid-JSON import messaging, precise oversized-file messaging, oversized-file rejection coverage, import-specific duplicate-name messaging, same-ID replacement regression coverage, all-or-nothing partial-bundle failure messaging, current-draft export labeling, low-contrast save/export warning copy, and legacy JSON import coverage are now explicit; external-file UX and broader validation still need polish.

Relevant files:

- `Downward/Features/Settings/ThemeEditorSettingsPage.swift`
- `Downward/Features/Settings/ThemeSettingsPage.swift`
- `Downward/Infrastructure/Theme/ThemeImportService.swift`
- `Downward/Infrastructure/Theme/ThemePersistenceService.swift`
- `Downward/Shared/Theme/ThemeExchangeDocument.swift`
- `Downward/Shared/Theme/CustomTheme.swift`
- `Downward/Shared/Theme/ThemeStore.swift`
- `Tests/ThemeStoreTests.swift`

The theme foundation is useful: custom themes persist, JSON exchange accepts single-theme/array/bundle shapes, import is security-scoped, and imported themes replace matching IDs while rejecting duplicate names.

Remaining concerns:

- [x] `CustomTheme` decodes `schemaVersion` but currently treats it mostly as stored metadata. Before sharing themes externally, unknown future schema versions should produce a clear user-facing outcome.
- [x] Import now surfaces precise errors for invalid JSON, unsupported schema, duplicate names, and oversized files.
- [x] Import now surfaces precise errors for partial-bundle failures, while keeping bundle import all-or-nothing.
- [x] Export from `ThemeEditorSettingsPage` serializes the current editor form state and is labelled as `Export Draft`.
- [x] Contrast warnings do not block save/export, and the warning copy now explicitly says Save and Export Draft remain available.
- [ ] Security-scoped import should be manually tested with Files, iCloud Drive, and at least one third-party provider.

Follow-up note (2026-04-25): theme exchange import/export now encodes `schemaVersion`, rejects versions newer than `CustomTheme.currentSchemaVersion`, surfaces a direct localized error instead of silently accepting unknown future schema payloads, preserves the invalid-JSON message in the Settings import alert instead of wrapping it in a generic prefix, reports oversized imports with both the actual file size and the configured limit, and uses an import-specific duplicate-name error when an imported theme conflicts with an existing different-ID theme.

Follow-up note (2026-04-25): focused theme exchange coverage now verifies file-backed single-theme, array, and bundle imports; invalid JSON; oversized imports; duplicate-name rejection; same-ID replacement; partial bundle failures; legacy JSON; selected-theme deletion fallback; and current-draft export behavior through `ThemeEditorDraftExport`. Verified with `xcodebuild test` on the available iPhone 17 simulator.

Done when:

- [x] Theme import/export failures are specific enough for a non-developer user to understand.
- [x] Export behavior is intentionally labelled: either “Export Current Draft” or “Export Saved Theme”.
- [x] Tests cover invalid JSON, too-large files, duplicate imported names, same-ID replacement, bundle import, selected-theme deletion fallback, and legacy JSON without newer optional fields.

### [P1] Markdown renderer remains the main scalability and maintainability risk

**Status:** improved; recognition, visibility, the first styling/application slice, conservative large-document work-scope budget, and local latency measurements are now covered.

Relevant files:

- `Downward/Features/Editor/MarkdownSyntaxScanner.swift`
- `Downward/Features/Editor/MarkdownSyntaxVisibilityPolicy.swift`
- `Downward/Features/Editor/MarkdownSyntaxStyleApplicator.swift`
- `Downward/Features/Editor/MarkdownStyledTextRenderer.swift`
- `Downward/Features/Editor/MarkdownCodeBackgroundLayoutManager.swift`
- `Downward/Features/Editor/MarkdownEditorTextViewCoordinator.swift`
- `Tests/MarkdownSyntaxScannerTests.swift`
- `Tests/MarkdownSyntaxStyleApplicatorTests.swift`
- `Tests/MarkdownRendererPerformanceTests.swift`
- `Tests/MarkdownStyledTextRendererTests.swift`
- `Tests/EditorUndoRedoTests.swift`

`MarkdownStyledTextRenderer.swift` is still a large app source file. Current-line restyling is a meaningful win for ordinary typing, and styling/application has started moving into `MarkdownSyntaxStyleApplicator`, but the renderer still owns plenty of regex-driven inline and block coordination.

Action items:

- [x] Split the first syntax recognition slice from UIKit styling before adding more markdown constructs.
- [x] Move hidden-syntax visibility decisions behind a small value type or strategy that can be tested without `UITextView`.
- [x] Extract the first styling/application slice from the renderer.
- [x] Keep current-line restyle as the fast path for simple same-line edits.
- [x] Keep line-breaks, block-context changes, selection-driven reveal changes, and paste operations on a deferred full-rerender path until a real incremental parser exists.
- [x] Add large-document performance fixtures before adding tables, footnotes, task-list interactions, or richer code-block behavior.

Follow-up note (2026-04-25): `MarkdownSyntaxScanner` now provides a UIKit-free first recognition layer for line ranges, indented code blocks, fenced code blocks, merged protected code block ranges, inline code spans, and image ranges. `MarkdownStyledTextRenderer` consumes those scanner results while retaining attributed-string styling and theme-role mapping. `MarkdownSyntaxVisibilityPolicy` now contains the pure syntax-hidden decision. Focused scanner and renderer tests passed on the available iPhone 17 simulator.

Follow-up note (2026-04-25): `MarkdownSyntaxStyleApplicator` now owns concrete attributed-string application for base attributes, headings, blockquotes, lists, inline/fenced/indented code, emphasis markers, links, images, horizontal rules, and hidden syntax markers. Focused applicator coverage was added while the renderer remains responsible for markdown recognition/range coordination.

Batch reconciliation note (2026-04-25): the source already contained the scanner, visibility policy, style applicator, and renderer wiring claimed by the docs. This pass kept that scope intact, clarified that the renderer still coordinates remaining recognition and TextKit handoff, and added scanner-only coverage for code-block protection, merged protected ranges, and inline matching exclusions.

Inline split note (2026-04-25): delimited inline emphasis/strong/strikethrough recognition now returns scanner value types instead of being styled directly from renderer-local regex callbacks. `MarkdownSyntaxStyleApplicator` owns the corresponding inline font/color/strikethrough application, and focused scanner/applicator tests cover those extracted spans.

Performance budget note (2026-04-25): large-document renderer coverage now uses an explicit work-scope budget rather than a brittle wall-clock threshold. Full document open/theme restyle may render the whole buffer; ordinary same-line typing in the large fixture must stay bounded to the edited line, with an automated 512-character current-line render ceiling; line-break/structural edits must schedule the deferred full-document pass.

Latency measurement note (2026-04-25): `MarkdownRendererPerformanceTests` now includes XCTest clock-metric measurements for the 2,000-line, 58,800 UTF-16 character markdown fixture. Run on a MacBook Pro with Apple M4 Pro, macOS 26.4.1, targeting iPhone 17 iOS 26.4 Simulator with `xcodebuild test -scheme Downward -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4' -only-testing:DownwardTests/MarkdownRendererPerformanceTests -only-testing:DownwardTests/MarkdownStyledTextRendererTests -only-testing:DownwardTests/MarkdownSyntaxScannerTests -only-testing:DownwardTests/MarkdownSyntaxStyleApplicatorTests`: same-line typing/current-line restyle averaged 1.81 ms over 5 samples, paste/full render of a 64,094-character pasted document averaged 198.87 ms, and theme-switch restyle averaged 196.11 ms. These are local regression guidance, not release guarantees.

Done when:

- [x] The renderer has a recognizer/scanner layer that can be tested without UIKit.
- [x] Styling/theme application is a separate layer.
- [x] Large-file typing has an explicit performance budget and regression coverage.
- [x] Long-document typing, paste/full-render, and theme-switch latency have local measured baselines.

### [P1] Workspace snapshot reverse lookup is indexed

**Status:** per-snapshot lookup indexes now cover common path and URL resolution; recursive traversal remains as a correctness fallback.

Relevant files:

- `Downward/Domain/Workspace/WorkspaceSnapshot.swift`
- `Downward/Domain/Workspace/WorkspaceSnapshotPathResolver.swift`
- `Downward/Features/Workspace/WorkspaceSearchEngine.swift`
- `Downward/Domain/Persistence/RecentFilesStore.swift`
- `Downward/Features/Workspace/WorkspaceViewModel.swift`
- `Downward/App/WorkspaceNavigationPolicy.swift`
- `Tests/WorkspaceSnapshotPathResolverTests.swift`
- `Tests/WorkspaceSearchTests.swift`
- `Tests/RecentFilesStoreTests.swift`

`WorkspaceSnapshot` now builds an immutable lookup index when each snapshot is created. `WorkspaceSnapshotPathResolver.relativePath(for:)`, `fileURL(forRelativePath:)`, `containsFile(relativePath:)`, `fileEntries()`, and `relativeFilePaths()` use that index for the common path while keeping the existing recursive tree walkers as private fallbacks for lookup correctness.

Follow-up note (2026-04-25): focused resolver coverage now includes duplicate filenames in different folders, nested path lookup, URL-to-relative lookup, stale missing paths, replacement snapshots after rename/move/delete, exact-case case-only rename behavior, and traversal-order preservation. Broader workspace navigation, coordinator policy, and recent-file store tests passed on the available iPhone 17 simulator.

Batch reconciliation note (2026-04-25): source inspection confirmed `WorkspaceSearchEngine` already carries relative paths from `snapshot.forEachFile` and `RecentFilesStore.pruneInvalidItems(using:)` uses `snapshot.relativeFilePaths()` instead of flattening URLs and re-resolving each one. This pass kept recursive fallbacks private, made the snapshot index storage private, and added focused file-only and ordered-enumeration coverage.

Folder mutation coverage note (2026-04-25): focused resolver coverage now includes folder rename, folder move with duplicate descendant filenames elsewhere, ancestor-folder delete, and a deterministic 1,440-file synthetic tree lookup/order regression. Mutation-flow coverage now verifies moving a folder that contains the open document updates editor route, open-document identity, restore state, and recents, while deleting the open document's ancestor folder closes the editor, clears restore state, prunes recents, and leaves the refreshed snapshot without the stale relative path.

Action items:

- [x] Introduce a snapshot index keyed by relative path and normalized URL identity.
- [x] Build the index once per snapshot refresh.
- [x] Keep recursive traversal as a fallback or validation path while the index is introduced.
- [x] Add tests for rename, move, delete, case-only rename, duplicate filenames in different folders, and stale recent-file paths.
- [x] Add tests for folder rename, folder move, delete-ancestor-folder safe state, and large synthetic tree lookup/order behavior.

Done when:

- [x] Navigation and recent-file reconciliation can resolve path/file identity without repeatedly walking the whole tree.
- [x] Workspace mutation tests prove index invalidation/rebuild behavior.

### [P1] Runtime QA is still required for the most sensitive UI and Files-provider paths

**Status:** dedicated checklist created and command-line simulator smoke completed; manual runtime QA is still not completed.

Runtime-only checklist:

- [ ] Launch with no workspace selected.
- [ ] Select a workspace from Files.
- [ ] Reopen the app and confirm workspace restore/reconnect behavior.
- [ ] Open nested documents via workspace browser and recents.
- [ ] Rename/move/delete files and folders while the edited document is open.
- [ ] Type long edits and verify autosave does not lose text after rapid open/close/reopen.
- [ ] Confirm first visible line placement below the top chrome on iPhone portrait, iPhone landscape, iPad split view, and iPad full screen.
- [ ] Confirm keyboard accessory controls on first keyboard presentation, after scroll, after theme change, and during interactive dismissal.
- [ ] Import and export themes through Files/iCloud Drive.
- [ ] Open ordinary `.json` files from a workspace and confirm they do not trigger theme import accidentally.
- [ ] Verify Settings sheet hierarchy on compact and regular width.

Done when:

- [ ] Manual QA results are recorded in `RELEASE_QA.md`.

### [P2] `AppCoordinator` is improved but still large

**Status:** acceptable for now; keep feature logic from creeping back in.

Relevant files:

- `Downward/App/AppCoordinator.swift`
- `Downward/App/WorkspaceNavigationPolicy.swift`
- `Downward/App/WorkspaceMutationPolicy.swift`
- `Downward/App/WorkspaceRestoreCoordinator.swift`
- `Downward/App/AppSession.swift`

At 1,336 lines, `AppCoordinator` is no longer the 1,500+ line hotspot it previously was, but it remains large enough that new feature work can easily reintroduce hidden coupling. The current seams are good: navigation and mutation decisions are already pushed into policy helpers.

Action items:

- [ ] Keep new workspace rules in policy/helper types, not directly in `AppCoordinator`.
- [ ] Consider extracting mutation-outcome reconciliation if rename/move/delete flows grow further.
- [ ] Consider extracting restore-state presentation decisions if reconnect UX grows.
- [ ] Add tests before moving coordinator logic so behavior remains stable.

### [P2] `WorkspaceViewModel` mixes several UI concerns

**Status:** not urgent, but watch it before adding more browser features.

Relevant files:

- `Downward/Features/Workspace/WorkspaceViewModel.swift`
- `Downward/Features/Workspace/WorkspaceBrowserView.swift`
- `Downward/Features/Workspace/WorkspaceSearchModel.swift`

The view model owns search, expansion, create/rename/delete/move prompts, recent-file presentation, async workspace operation state, and mutation-result UI updates. It is coherent enough today, but future browser features will make it harder to reason about.

Action items:

- [ ] Keep search state in `WorkspaceSearchModel` rather than pulling it back into the main view model.
- [ ] Extract command/prompt state if more mutation dialogs are added.
- [ ] Extract expansion/path-rewrite helpers if the tree mutation logic grows.

## Test gaps to close next

- [x] Theme import invalid JSON.
- [x] Theme import file larger than the 5 MB limit.
- [x] Theme import duplicate name with different ID.
- [x] Theme import same ID replacement.
- [x] Theme import bundle/array decoding and partial failure behavior.
- [x] Selected custom theme deletion fallback.
- [x] Theme export current-draft versus saved-theme behavior.
- [ ] Accessory clear-background/tint contract.
- [ ] Accessory behavior during keyboard presentation and interactive dismissal on device.
- [x] Large-document renderer performance fixture.
- [x] Snapshot index behavior after rename/move/delete/case-only rename.
- [ ] Real Files-provider workspace observation and theme import.

## Documentation changes made by this review

- [x] `CODE_REVIEW.md` refreshed with the current static review and actionable findings.
- [x] `TASKS.md` converted into an active checkable backlog.
- [x] `PLANS.md` refreshed into checkable engineering plans and QA gates.
- [x] Stale claims about a painted accessory underlay were removed from steering docs.

## Next recommended sequence

1. Run the Xcode build and focused XCTest suites.
2. Complete the runtime QA checklist for editor geometry, keyboard accessory, settings, workspace restore, and Files-provider import/export.
3. Patch any build/test regressions before adding new product features.
4. Harden theme import/export UX.
5. Keep workspace snapshot indexes protected with focused resolver/search/recent-file tests as mutation paths evolve.
6. Continue markdown renderer decomposition before expanding markdown features.
