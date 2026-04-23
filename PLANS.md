# PLANS.md

## Purpose

This is the detailed technical plan for work that should happen before Downward grows a larger markdown feature set or a JSON-driven theme system.

`TASKS.md` remains the short active backlog. This file is the deeper engineering checklist: performance plans, code-review findings, sequencing, and QA gates.

---

## Review scope

Reviewed current project shape across:

- editor rendering and hidden syntax handling,
- `MarkdownEditorTextView` and TextKit layout behavior,
- keyboard accessory behavior and themed-background risk areas,
- renderer tests,
- workspace search and recent-file path lookup,
- workspace/document view-model task lifecycles,
- document observation and save paths,
- architecture docs and stale editor bridge code.

Current state is good enough to continue product work, but large-file rendering, renderer structure, keyboard accessory/theme integration, and path lookup hot paths should be cleaned up before adding more markdown features or themes.

---

## Priority guide

- **P0**: fix before adding new markdown or theme features.
- **P1**: do soon; safe to run alongside UI polish and settings work.
- **P2**: future architecture work that should not block current shipping unless performance regresses again.

---

## P0 — immediate fixes before new markdown/theme features

### 1. Keep the current hidden-syntax optimization layer in place

**Current finding**

The current tree already contains the important optimization layer. In the current code:

- `MarkdownEditorTextView.Coordinator.applyRenderedText(...)` updates `textStorage` in place instead of replacing `attributedText` wholesale.
- `textViewDidChangeSelection(...)` stays on the cheaper reveal/hide path unless a pending text mutation still needs a deferred full pass.
- `MarkdownCodeBackgroundLayoutManager.shouldGenerateGlyphs(...)` walks effective `.markdownHiddenSyntax` runs instead of allocating a hidden-range array per glyph batch.
- `MarkdownStyledTextRenderer.updateHiddenSyntaxVisibility(...)` skips no-op attribute changes and invalidates only the changed ranges.

**Plan**

- [x] Update full rerenders to mutate `textView.textStorage` with `setAttributedString(...)` instead of replacing `attributedText`.
- [x] Add a short deferred rerender after text edits so ordinary typing does not pay the full markdown pass immediately.
- [x] Keep selection/caret movement on the cheap path whenever no text mutation requires a full rerender.
- [x] In glyph generation, walk effective `.markdownHiddenSyntax` attribute runs instead of allocating a `hiddenRanges` array per glyph batch.
- [x] In hidden-syntax visibility updates, skip no-op attribute changes.
- [x] Invalidate layout/display for the actual changed syntax ranges instead of broader line ranges when possible.
- [x] Add or restore tests for deferred rerender behavior and no-op hidden-syntax updates.
- [x] Manually verify typing, fast caret movement, selection dragging, undo/redo, and IME/marked-text input on large files.

**Likely files**

- `Downward/Features/Editor/MarkdownEditorTextView.swift`
- `Downward/Features/Editor/MarkdownStyledTextRenderer.swift`
- `Downward/Features/Editor/MarkdownCodeBackgroundLayoutManager.swift`
- `Tests/MarkdownStyledTextRendererTests.swift`

---

### 2. Fix autosave cancellation semantics

**Current finding**

`EditorViewModel.scheduleAutosave(for:)` uses `try? await Task.sleep(for: autosaveDelay)` and then continues to `requestAutosave(...)`. A canceled sleep therefore still falls through. Generation checks make most cases harmless, but cancellation should be explicit and future-proof.

**Plan**

- [x] Replace `try? await Task.sleep(...)` with `do/catch` or a post-sleep `Task.isCancelled` guard.
- [x] Ensure canceled autosave tasks cannot queue or start a save merely because the generation still matches.
- [x] Add a regression test for canceling autosave without performing an old save.

Manual follow-up: still exercise rapid typing, background/foreground flushes, and conflict-recovery actions on device to confirm autosave timing stays calm under real Files providers.

**Likely files**

- `Downward/Features/Editor/EditorViewModel.swift`
- `Tests/EditorAutosaveTests.swift`

---

### 3. Remove or repurpose stale `EditorTextViewHostBridge`

**Current finding**

`EditorTextViewHostBridge.swift` still describes a `TextEditor` probing bridge, but the shipping editor is now the custom `MarkdownEditorTextView` / `UITextView` boundary. The file still owns `EditorTextViewLayout`, so it cannot simply disappear without moving those constants.

**Plan**

- [x] Move `EditorTextViewLayout` into a dedicated editor layout file or into `MarkdownEditorTextView.swift`.
- [x] Delete the obsolete `EditorTextViewHostBridge` and `EditorTextViewHostBridgeView` if they are unused.
- [x] Delete or rewrite `EditorTextViewHostBridgeTests.swift` so tests describe the shipping editor path only.
- [x] Update docs that still imply the app uses a SwiftUI `TextEditor` implementation.

Note: `EditorTextViewLayout` was kept and moved into a dedicated editor layout file because the shipping `MarkdownEditorTextView` still uses those spacing constants.

**Likely files**

- `Downward/Features/Editor/EditorTextViewHostBridge.swift`
- `Downward/Features/Editor/MarkdownEditorTextView.swift`
- `Tests/EditorTextViewHostBridgeTests.swift`
- `ARCHITECTURE.md`

---

### 4. Make markdown syntax visibility rules explicit

**Current finding**

The renderer has a mixed contract:

- emphasis, heading, blockquote, link, and image marker hiding flows through `hideSyntaxIfNeeded(...)`, which respects `MarkdownSyntaxMode`;
- inline code delimiters and fenced code fences currently call `hideRange(...)` directly and are hidden even in `.visible` mode;
- tests currently encode always-hidden code delimiters/fences.

That may be a valid product choice, but it needs to be named before more markdown features are added.

**Plan**

- [x] Decide whether `.visible` means “all markdown syntax visible” or “editor-friendly rendered mode where some structural code syntax is always hidden.”
- [x] Rename the mode or add a second visibility policy if needed.
- [x] Update tests so the intended behavior is obvious for emphasis, links, images, inline code, and fenced code.
- [x] Keep future features from guessing whether their markers should use `hideSyntaxIfNeeded(...)` or unconditional `hideRange(...)`.

Note: `.visible` remains the rendered editing mode, not a fully raw markdown mode. Supported markdown syntax now follows `MarkdownSyntaxMode` consistently, including inline-code delimiters and fenced-code fences, so caret-line reveal behaves the same way across syntax categories.

**Likely files**

- `Downward/Features/Editor/MarkdownSyntaxMode.swift`
- `Downward/Features/Editor/MarkdownStyledTextRenderer.swift`
- `Tests/MarkdownStyledTextRendererTests.swift`

---

### 5. Introduce renderer style/theme roles before JSON themes

**Current finding**

`MarkdownStyledTextRenderer` hard-codes many UIKit colors directly while recognizing markdown. That will make JSON themes harder because parsing, styling, and theme decisions are currently tangled.

**Plan**

- [ ] Add an internal editor theme/style model before importing JSON themes.
- [ ] Map semantic roles to concrete UIKit values in one place.
- [ ] Replace direct renderer references to `UIColor.label`, `.secondaryLabel`, `.tertiaryLabel`, `.link`, and `.secondarySystemFill` with theme roles.
- [ ] Keep code background and blockquote drawing colors in the same theme pipeline as attributed text.
- [ ] Add fallback/default theme values matching the current UI exactly.
- [ ] Add tests that default theme output matches current expected styling.

**Likely files**

- `Downward/Features/Editor/MarkdownStyledTextRenderer.swift`
- `Downward/Features/Editor/MarkdownCodeBackgroundLayoutManager.swift`
- `Downward/Domain/Persistence/EditorAppearanceStore.swift`
- `Downward/Features/Settings/SettingsScreen.swift`
- new editor theme model file

---

### 5a. Make keyboard accessory transparency explicit before custom backgrounds return

**Current finding**

The current safe-area fix in `EditorScreen` is necessary, but it is not the whole story once themed editor backgrounds return. The accessory bar sits at the intersection of:

- the SwiftUI editor underlay,
- the `UITextView` background and TextKit drawing stack,
- the embedded `UIToolbar` used by `KeyboardAccessoryToolbarView`.

That means the old opaque-bar regression can still come back if toolbar transparency is treated as an implicit platform default instead of a deliberate accessory contract.

**Plan**

- [x] Reintroduce explicit transparent `UIToolbarAppearance` configuration for the keyboard accessory.
- [x] Reapply that appearance when the accessory moves into a window or traits change.
- [x] Add a regression test proving the wrapper and toolbar are transparent by configuration.
- [ ] When editor themes are added, drive the editor background, TextKit background drawing, and accessory underlay from the same resolved theme model.
- [ ] Add manual QA coverage for light, dark, and at least one non-standard editor background color.

**Likely files**

- `Downward/Features/Editor/MarkdownEditorTextView.swift`
- `Downward/Features/Editor/MarkdownCodeBackgroundLayoutManager.swift`
- `Downward/Domain/Persistence/EditorAppearanceStore.swift`
- `Tests/EditorUndoRedoTests.swift`

---

### 6. Reduce renderer duplication and allocation pressure

**Current finding**

`MarkdownStyledTextRenderer` repeats inline regex patterns in discovery and styling passes, repeatedly builds protected-range arrays, and uses linear `protectedRanges.contains(where:)` checks throughout. This is manageable today, but it will get worse as more markdown features are added.

**Plan**

- [ ] Extract inline pattern definitions into named token rules.
- [ ] Avoid duplicating regex literals between pre-scan and styling passes.
- [ ] Sort/merge protected ranges once and use a small helper for intersection checks.
- [ ] Consider binary-searching protected ranges once the list is sorted.
- [ ] Remove unused parameters in `hideRange(...)` once the old font/kerning strategy is gone.
- [ ] Keep regex cache behavior, but do not let regex matching become the only extension mechanism for future block features.

**Likely files**

- `Downward/Features/Editor/MarkdownStyledTextRenderer.swift`
- `Tests/MarkdownStyledTextRendererTests.swift`

---

## P1 — workspace, tests, and maintainability cleanup

### 7. Remove repeated snapshot-wide relative-path lookup

**Current finding**

`WorkspaceSearchEngine` traverses the workspace tree and then calls `snapshot.relativePath(for:)` for each file. `RecentFilesStore.relativeFilePaths(in:)` flattens file URLs and then calls `snapshot.relativePath(for:)` for each URL. Since `relativePath(for:)` scans the tree, those paths can become unnecessarily expensive in large workspaces.

**Plan**

- [x] Traverse workspace nodes with an accumulated relative path instead of resolving each URL with a second tree scan.
- [x] Add a helper for walking files/folders with `(node, relativePath)` pairs.
- [ ] Use that helper in search, recents pruning, move destination construction, and expanded-folder cleanup where it fits.
- [ ] Keep final file-system access validation separate from snapshot-derived identity.
- [x] Add tests proving search and recents still produce the same relative paths.

**Likely files**

- `Downward/Features/Workspace/WorkspaceSearchEngine.swift`
- `Downward/Domain/Persistence/RecentFilesStore.swift`
- `Downward/Domain/Workspace/WorkspaceSnapshotPathResolver.swift`
- `Downward/Features/Workspace/WorkspaceViewModel.swift`
- `Tests/WorkspaceSearchTests.swift`
- `Tests/RecentFilesStoreTests.swift`

---

### 8. Split the giant smoke-test file

**Current finding**

`Tests/MarkdownWorkspaceAppSmokeTests.swift` is still the largest test file by far. It is useful, but it is becoming difficult to scan and maintain.

**Plan**

- [ ] Keep true end-to-end smoke flows in `MarkdownWorkspaceAppSmokeTests.swift`.
- [ ] Move restore/reconnect cases into a focused restore suite.
- [ ] Move mutation/navigation cases into focused coordinator or workspace suites.
- [ ] Move editor save/conflict flows into focused editor suites.
- [ ] Preserve existing coverage before adding new feature tests.

**Likely files**

- `Tests/MarkdownWorkspaceAppSmokeTests.swift`
- new focused test files under `Tests/`

---

### 9. Make fire-and-forget tasks explicit

**Current finding**

Most long-lived tasks are tracked and canceled, but some UI event tasks in `RootViewModel` and `EditorViewModel` are intentionally fire-and-forget. That can be fine, but the distinction should be explicit before more async settings/import/theme work is added.

**Plan**

- [ ] Audit unstructured `Task { ... }` usage in view models.
- [ ] Store and cancel tasks that can outlive the UI state they mutate.
- [ ] Leave truly fire-and-forget actions as documented one-shot tasks.
- [ ] Add generation checks where an old async action can overwrite newer state.

**Likely files**

- `Downward/Features/Root/RootViewModel.swift`
- `Downward/Features/Editor/EditorViewModel.swift`
- `Downward/Features/Workspace/WorkspaceViewModel.swift`

---

### 10. Keep `AppCoordinator` from absorbing feature logic

**Current finding**

`AppCoordinator.swift` is still the central orchestration file and remains large. The current policy seams are working, but future markdown/theme work should not add editor-specific decisions here.

**Plan**

- [ ] Extract repeated mutation error-handling helpers if coordinator growth continues.
- [ ] Keep navigation decisions inside `WorkspaceNavigationPolicy` where possible.
- [ ] Keep workspace snapshot application decisions inside `WorkspaceSessionPolicy` where possible.
- [ ] Do not route editor theme or markdown parser state through the coordinator unless it affects route/session state.

**Likely files**

- `Downward/App/AppCoordinator.swift`
- `Downward/App/WorkspaceNavigationPolicy.swift`
- `Downward/App/WorkspaceSessionPolicy.swift`

---

## P1 — markdown feature architecture preparation

### 11. Add semantic token types before adding more markdown features

**Plan**

- [ ] Define semantic token roles for existing features first.
- [ ] Represent syntax markers separately from content ranges.
- [ ] Represent hidden-syntax eligibility separately from current hidden/revealed state.
- [ ] Keep block-level tokens separate from inline tokens.
- [ ] Include enough metadata for theming and later incremental parsing.

Suggested starting roles:

- [ ] `plainText`
- [ ] `heading(level:)`
- [ ] `headingMarker`
- [ ] `setextUnderline`
- [ ] `emphasisContent`
- [ ] `strongContent`
- [ ] `strikethroughContent`
- [ ] `inlineCodeContent`
- [ ] `inlineCodeDelimiter`
- [ ] `fencedCodeContent`
- [ ] `fencedCodeDelimiter`
- [ ] `blockquoteMarker(depth:)`
- [ ] `blockquoteContent(depth:)`
- [ ] `listMarker`
- [ ] `linkLabel`
- [ ] `linkDestination`
- [ ] `imageAltText`
- [ ] `imageSource`
- [ ] `syntaxMarker`
- [ ] `hiddenSyntaxCandidate`

---

### 12. Split parser, styler, theme, and layout responsibilities

**Plan**

- [ ] Keep markdown recognition in a parser/tokenizer layer.
- [ ] Keep attributed-string mutation in a styler layer.
- [ ] Keep colors/fonts/backgrounds in a theme layer.
- [ ] Keep glyph suppression and background drawing in TextKit layout code.
- [ ] Keep `PlainTextDocumentSession` completely unaware of markdown rendering.
- [ ] Keep `EditorAppearanceStore` responsible for persisted appearance settings, not parsing.

---

### 13. Define the extension protocol for new markdown features

**Plan**

Before adding each new feature, document:

- [ ] which block or inline token roles it creates,
- [ ] whether it can affect following lines,
- [ ] whether it needs current-line syntax reveal behavior,
- [ ] whether it participates in theme roles,
- [ ] how it interacts with code blocks and inline code protection,
- [ ] what tests prove it does not leak into protected ranges.

---

## P2 — future large-file incremental rendering

### 14. Stage 1: region-bounded restyling

**Goal**

Reduce edit-time work without committing to a full parser rewrite immediately.

**Plan**

- [ ] Track the edited character range from `UITextViewDelegate` callbacks.
- [ ] Convert the edit range into a dirty line range.
- [ ] Expand to include previous and next lines.
- [ ] Expand over adjacent blockquote/list/indented-code regions where needed.
- [ ] Expand to nearby fence boundaries when a code fence may be affected.
- [ ] Render only that substring/window.
- [ ] Offset produced ranges back into full-document coordinates.
- [ ] Clear and replace attributes only inside the dirty window.
- [ ] Fall back to whole-document rendering when the safe window cannot be proven.
- [ ] Add large-file tests that assert the dirty range stays bounded for ordinary inline edits.

---

### 15. Stage 2: cached line/block state

**Goal**

Make fenced code blocks and other stateful block features correct without reparsing the whole document after most edits.

**Plan**

- [ ] Cache per-line state for normal text vs fenced-code-block state.
- [ ] Include fence delimiter metadata and fence language/info string if added later.
- [ ] Recompute from a safe boundary before the edit.
- [ ] Continue forward until newly computed state matches cached old state.
- [ ] Invalidate only changed semantic ranges and changed layout ranges.
- [ ] Keep a whole-document recovery pass for pathological cases and debugging.
- [ ] Add tests for inserting/removing opening fences, closing fences, and edits near setext headings.

---

### 16. Stage 3: fast retheme from semantic ranges

**Goal**

Theme switches should eventually avoid reparsing markdown.

**Plan**

- [ ] Cache semantic ranges from the latest successful parse.
- [ ] On theme change, rebuild attributes from semantic ranges without re-running markdown recognition.
- [ ] Re-run parsing only when document text changes or parser settings change.
- [ ] Keep hidden-syntax current-line state as a layout/text-storage toggle, not a parser operation.

---

## P1 — JSON theme plan

### 17. Theme schema and validation

**Plan**

- [ ] Add a versioned JSON schema.
- [ ] Support partial themes with default fallback values.
- [ ] Validate color strings before storing them.
- [ ] Clamp font sizes and reject unsupported font families gracefully.
- [ ] Keep imported theme data separate from the resolved runtime theme.
- [ ] Add tests for missing fields, invalid colors, unknown roles, and future schema versions.

---

### 18. Theme application UX

**Plan**

- [ ] Add built-in default themes first.
- [ ] Add a preview surface before applying imported themes globally.
- [ ] Make reset-to-default obvious.
- [ ] Avoid applying malformed JSON directly to the live editor.
- [ ] Keep theme import/export out of document save paths.

---

## QA gates before larger feature work

### 19. Large-file editor QA

- [ ] Open a very large markdown file with hidden syntax enabled.
- [ ] Move the caret rapidly across headings, emphasis, code spans, links, images, and blockquotes.
- [ ] Type inside a long paragraph.
- [ ] Type near fenced-code block delimiters.
- [ ] Drag-select across hidden markers.
- [ ] Undo and redo after deferred rendering.
- [ ] Verify no phantom marker spaces appear when syntax is hidden.
- [ ] Verify caret placement remains sane around hidden markers.

---

### 20. Real-device UI QA

- [x] Restore seamless editor underlay beneath the top chrome while using one shared safe-area-driven inset for the first visible line and placeholder.
- [ ] Verify first-line placement below top chrome on iPhone.
- [ ] Verify first-line placement below top chrome on iPad.
- [ ] Verify keyboard accessory behavior and keyboard dismissal.
- [ ] Verify scroll indicators with top chrome and keyboard visible.
- [ ] Verify the editor remains usable in iCloud Drive and local Files workspaces.

Note: the code path no longer reconstructs top clearance from navigation-bar/window geometry. The editor surface now underlaps the top chrome again, while `MarkdownEditorTextView` and the placeholder share one safe-area-driven top inset helper and still keep zero extra scroll-view top compensation. Real-device verification is still required before closing the remaining QA bullets above.

---

### 21. Regression test coverage

- [x] Hidden syntax remains glyph-suppressed, not font-collapsed.
- [x] Current-line syntax reveal updates without full rerender when text is already rendered.
- [ ] Deferred rerender happens after edits and does not break undo/redo.
- [x] Canceled autosave tasks do not start stale saves.
- [x] Search and recents keep the same relative-path identity after path traversal optimization.
- [ ] Theme defaults reproduce current colors and fonts.

---

## Explicit non-goals for now

Do not start these until the P0 list is handled or there is a specific product need:

- [ ] Full CommonMark compliance.
- [ ] Third-party markdown parser dependency.
- [ ] A second competing editor implementation.
- [ ] Multi-document live editing.
- [ ] Content indexing/search.
- [ ] Background parsing service without a clear UI performance requirement.
