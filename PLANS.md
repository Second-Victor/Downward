# PLANS.md

## Purpose

This file is the deeper engineering plan for Downward. It explains how to pay down the current review findings while keeping work checkable. `TASKS.md` is the short active backlog. `CODE_REVIEW.md` records review findings and rationale.

## Review baseline

Baseline: 2026-04-24 static review of the uploaded `Downward.zip` project.

- [x] Static review completed.
- [x] Steering docs refreshed.
- [ ] Xcode build completed.
- [ ] XCTest suites completed.
- [ ] Simulator/device QA completed.

The codebase has moved out of emergency hardening. The current foundations are good enough to continue product work only if validation remains disciplined. The main risks are now renderer scale, runtime keyboard/accessory behavior, theme exchange polish, large-workspace lookup cost, and preventing coordinator/view-model files from regrowing.

## Status legend

- [x] Completed or currently satisfied by the reviewed code.
- [ ] Open work.

## Completed foundation checklist

### Workspace and document safety

- [x] Keep final trust decisions inside `WorkspaceManager` and `WorkspaceRelativePath`.
- [x] Prefer workspace-relative paths for document routing, recents, search results, and restore flows.
- [x] Keep document display names out of routing identity.
- [x] Keep normal `.json` files openable as text documents.
- [x] Keep theme import as an explicit settings action.
- [x] Guard restore/reconnect flows against stale async results.
- [x] Preserve newer editor edits when save acknowledgements arrive after additional typing.
- [x] Cancel autosave tasks cleanly when editor sessions are replaced or closed.

### Editor architecture

- [x] Keep `MarkdownEditorTextView` as a thin SwiftUI/UITextView boundary.
- [x] Keep text syncing and selection behavior in `MarkdownEditorTextViewCoordinator`.
- [x] Keep keyboard accessory UI in `EditorKeyboardAccessoryToolbarView`.
- [x] Keep keyboard geometry in `EditorKeyboardGeometryController`.
- [x] Keep custom `UITextView` chrome behavior in `EditorChromeAwareTextView`.
- [x] Preserve full-height editor sizing.
- [x] Preserve top underlay and first-visible-line spacing as product behavior.
- [x] Preserve document-open viewport reset.
- [x] Keep syntax visibility explicit through editor appearance state.
- [x] Keep same-line current-line restyling as the fast typing path.

### Theme and settings foundation

- [x] Persist built-in editor theme selection.
- [x] Persist custom themes.
- [x] Support custom theme create/edit/delete flows.
- [x] Support JSON theme import/export through a dedicated theme exchange document.
- [x] Keep settings as a sheet-based hierarchy on compact and regular-width layouts.
- [x] Keep placeholder-backed future features visibly disabled or clearly non-final.

### Code ownership

- [x] Push workspace navigation decisions into `WorkspaceNavigationPolicy`.
- [x] Push workspace mutation decisions into `WorkspaceMutationPolicy`.
- [x] Keep workspace restore coordination behind a focused helper.
- [x] Keep settings display summaries behind settings model/store seams.

## P0 plan — validation before release

No new static-review P0 was found. The P0 work is therefore validation, not a known code patch.

### Build and test gate

- [ ] Build the app in Xcode.
- [ ] Run all available unit tests.
- [ ] Run focused workspace restore/reconnect tests.
- [ ] Run focused document manager tests.
- [ ] Run focused editor autosave tests.
- [ ] Run focused editor undo/redo tests.
- [ ] Run focused markdown renderer tests.
- [ ] Run focused settings/theme tests.
- [ ] Run focused keyboard geometry/editor sizing tests.
- [ ] Record failures in `TASKS.md` and add new review findings if needed.

### Manual app gate

- [ ] Fresh install opens cleanly with no workspace.
- [ ] Workspace picker opens and grants access.
- [ ] Workspace restore works after relaunch.
- [ ] Reconnect flow works when access is stale or missing.
- [ ] Recent files reopen by relative path.
- [ ] Open document survives app background/foreground.
- [ ] Autosave survives rapid typing and document switching.
- [ ] Rename/move/delete flows leave the editor in a safe state.
- [ ] Settings sheet works on compact and regular width.

## P1 plan — keyboard accessory and theme contract

### Current finding

The current code deliberately keeps the keyboard accessory wrapper clear and non-opaque, then themes toolbar controls/tint. Earlier steering docs described a painted accessory underlay matching the editor surface, but that is not the current contract. Painting the accessory host can create wider UIKit keyboard-host side effects, so the code should stay explicit and tested.

### Implementation plan

- [ ] Keep the accessory wrapper background clear.
- [ ] Keep the accessory wrapper non-opaque.
- [ ] Keep toolbar background/shadow treatment explicit.
- [ ] Apply resolved theme tint to accessory controls.
- [ ] Do not paint private keyboard host/container backgrounds unless a future device QA pass proves it is safe.
- [x] Add tests for clear/non-opaque wrapper behavior.
- [x] Add tests for toolbar tint following the resolved theme.
- [ ] Keep docs aligned if the strategy changes again.

### Manual QA plan

- [ ] Verify first keyboard presentation on iPhone portrait.
- [ ] Verify first keyboard presentation on iPhone landscape.
- [ ] Verify first keyboard presentation on iPad full screen.
- [ ] Verify first keyboard presentation on iPad split view.
- [ ] Verify interactive keyboard dismissal.
- [ ] Verify accessory controls after switching themes.
- [ ] Verify at least one custom theme with a non-standard background.
- [ ] Verify no white band or default light host flash.
- [ ] Verify no full-screen background takeover from accessory painting.

### Likely files

- `Downward/Features/Editor/EditorKeyboardAccessoryToolbarView.swift`
- `Downward/Features/Editor/EditorKeyboardGeometryController.swift`
- `Downward/Features/Editor/MarkdownEditorTextView.swift`
- `Tests/EditorKeyboardGeometryControllerTests.swift`
- `Tests/MarkdownEditorTextViewSizingTests.swift`
- New focused accessory appearance tests if needed.

## P1 plan — theme import/export hardening

### Current finding

The app now has real custom theme infrastructure, but import/export is still closer to a functional foundation than a polished external file format. The biggest product decision is whether export means “current form draft” or “last saved theme”.

### Implementation plan

- [ ] Decide whether export should serialize the current editor form or the persisted theme.
- [ ] If exporting the form, label it as draft/current export.
- [ ] If exporting the saved theme, load the persisted theme by ID before export.
- [ ] Decide whether low-contrast warnings should block export.
- [x] Add explicit unsupported-schema handling for future `schemaVersion` values.
- [ ] Make duplicate-name import errors user-readable.
- [ ] Make oversized-file errors user-readable.
- [ ] Make invalid JSON errors user-readable without exposing raw decoder internals.
- [ ] Decide whether bundle import should be all-or-nothing or allow partial import.
- [ ] Keep normal `.json` document opening separate from theme import.

### Test plan

- [ ] Import a valid single-theme JSON file.
- [ ] Import a valid array of themes.
- [ ] Import a valid bundle document.
- [ ] Import invalid JSON.
- [ ] Import a file above the 5 MB limit.
- [ ] Import a theme with duplicate name and different ID.
- [ ] Import a theme with the same ID and confirm replacement behavior.
- [ ] Import legacy JSON missing newer optional fields.
- [ ] Delete the currently selected custom theme and confirm fallback.
- [ ] Export a saved theme.
- [ ] Export unsaved editor form state if that remains the chosen behavior.

### Manual QA plan

- [ ] Import from Files local storage.
- [ ] Import from iCloud Drive.
- [ ] Import from a third-party provider if available.
- [ ] Export to Files local storage.
- [ ] Export to iCloud Drive.
- [ ] Confirm exported JSON can be re-imported.
- [ ] Confirm ordinary workspace `.json` files open as text documents.

### Likely files

- `Downward/Features/Settings/ThemeEditorSettingsPage.swift`
- `Downward/Features/Settings/ThemeSettingsPage.swift`
- `Downward/Infrastructure/Theme/ThemeImportService.swift`
- `Downward/Infrastructure/Theme/ThemePersistenceService.swift`
- `Downward/Shared/Theme/ThemeExchangeDocument.swift`
- `Downward/Shared/Theme/CustomTheme.swift`
- `Downward/Shared/Theme/ThemeStore.swift`
- `Tests/ThemeStoreTests.swift`

## P1 plan — markdown renderer scalability

### Current finding

`MarkdownStyledTextRenderer.swift` remains the largest app file and still owns too many concerns. Current-line restyling is the right short-term optimization, but long-term markdown feature work needs recognition, hidden-syntax decisions, theme role mapping, and attributed-string styling to be separated.

### Architecture plan

- [ ] Create a syntax recognition/scanning layer that returns markdown spans and block metadata without UIKit dependencies.
- [ ] Create a styling layer that maps recognized spans to fonts, colors, paragraph styles, and hidden-syntax attributes.
- [ ] Create a hidden-syntax visibility policy that can be tested without a live text view.
- [ ] Keep code-block/background layout drawing separate from syntax recognition.
- [ ] Keep theme role mapping separate from markdown parsing.
- [ ] Keep renderer tests focused on both recognition and styled output during the transition.

### Performance plan

- [ ] Keep same-line edits on the current-line restyle path.
- [ ] Send line breaks, paste, structural edits, and selection reveal changes through deferred full rerender until a real incremental parser exists.
- [ ] Add large-document fixtures.
- [ ] Measure typing latency in long documents.
- [ ] Measure paste latency in long documents.
- [ ] Measure theme-switch restyle latency in long documents.
- [ ] Do not add table/footnote/task-list interaction features until the split starts.

### Likely files

- `Downward/Features/Editor/MarkdownStyledTextRenderer.swift`
- `Downward/Features/Editor/MarkdownCodeBackgroundLayoutManager.swift`
- `Downward/Features/Editor/MarkdownEditorTextViewCoordinator.swift`
- `Tests/MarkdownStyledTextRendererTests.swift`
- `Tests/MarkdownCurrentLineRestyleTests.swift`
- New scanner/recognizer tests.

## P1 plan — workspace snapshot indexing

### Current finding

`WorkspaceSnapshotPathResolver` still uses recursive lookup for relative-path and URL resolution. This is correct and simple, but it will become a performance problem in large workspaces and in flows that repeatedly reconcile recents, mutations, and navigation state.

### Implementation plan

- [ ] Add a per-snapshot index for relative path to node/file metadata.
- [ ] Add a per-snapshot index for file URL or stable file identity where available.
- [ ] Build indexes when a snapshot is created or refreshed.
- [ ] Keep recursive traversal as a fallback while indexes are introduced.
- [ ] Route navigation lookup through the index.
- [ ] Route recent-file reconciliation through the index.
- [ ] Route mutation outcome lookup through the index.
- [ ] Ensure indexes rebuild after refresh, rename, move, delete, and reconnect.

### Test plan

- [ ] Duplicate filenames in different folders.
- [ ] Rename file.
- [ ] Rename folder.
- [ ] Move file.
- [ ] Move folder.
- [ ] Delete open file.
- [ ] Delete ancestor folder of open file.
- [ ] Case-only rename.
- [ ] Stale recent file after external change.
- [ ] Large synthetic tree lookup benchmark if practical.

### Likely files

- `Downward/Domain/Workspace/WorkspaceSnapshotPathResolver.swift`
- `Downward/Domain/Workspace/WorkspaceSnapshot.swift`
- `Downward/Features/Workspace/WorkspaceViewModel.swift`
- `Downward/App/WorkspaceNavigationPolicy.swift`
- `Downward/App/WorkspaceMutationPolicy.swift`
- `Tests/WorkspaceSnapshotPathResolverTests.swift`
- `Tests/WorkspaceViewModelMutationTests.swift`

## P1 plan — runtime QA matrix

### Editor layout and keyboard

- [ ] iPhone portrait: top underlay and first line.
- [ ] iPhone landscape: top underlay and first line.
- [ ] iPad full screen: top underlay and first line.
- [ ] iPad split view: top underlay and first line.
- [ ] First keyboard presentation.
- [ ] Keyboard dismissal.
- [ ] Interactive keyboard dismissal.
- [ ] Undo/redo accessory buttons.
- [ ] Accessory after theme switch.
- [ ] Accessory after app foreground/background.

### Workspace and Files providers

- [ ] Local workspace select/open/edit/save.
- [ ] iCloud Drive workspace select/open/edit/save.
- [ ] Third-party provider workspace select/open/edit/save if available.
- [ ] External rename while app is open.
- [ ] External move while app is open.
- [ ] External delete while app is open.
- [ ] Reconnect after stale bookmark/access.
- [ ] Recent file after workspace refresh.

### Settings and themes

- [ ] Settings sheet compact width.
- [ ] Settings sheet regular width.
- [ ] Built-in theme switch.
- [ ] Custom theme create/edit/delete.
- [ ] Custom theme import.
- [ ] Custom theme export.
- [ ] Low-contrast warning.
- [ ] Open ordinary workspace `.json` as a document.

## P2 plan — coordinator and workspace view model containment

### App coordinator

- [ ] Keep new workspace decisions in focused policies/helpers.
- [ ] Extract mutation-outcome reconciliation if it grows.
- [ ] Extract restore presentation decisions if reconnect UX grows.
- [ ] Keep coordinator tests around every extraction.
- [ ] Avoid adding settings/theme/editor feature logic directly to `AppCoordinator`.

### Workspace view model

- [ ] Keep search behaviour in `WorkspaceSearchModel`.
- [ ] Extract prompt/command state if more dialogs are added.
- [ ] Extract expansion/path-rewrite helpers if tree mutation handling grows.
- [ ] Add tests before splitting to preserve browser behavior.

## P2 plan — future product features

These stay behind the current validation and architecture work.

- [ ] StoreKit tips.
- [ ] App Store review/rating routing.
- [ ] Configured legal/privacy URLs.
- [ ] Line numbers.
- [ ] Larger heading text.
- [ ] Richer markdown constructs such as tables and footnotes.
- [ ] Deeper theme marketplace/sharing behavior.

## Documentation maintenance plan

- [x] Refresh `CODE_REVIEW.md` with current findings.
- [x] Convert `TASKS.md` to checkable sections.
- [x] Convert this file to checkable engineering plans.
- [ ] Update `ARCHITECTURE.md` whenever ownership boundaries change.
- [ ] Update `AGENTS.md` only when contributor instructions or project rules change.
- [ ] Keep runtime QA results in `TASKS.md` or a dedicated release checklist.
