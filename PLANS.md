# PLANS.md

## Purpose

This is the single active planning backlog for **Downward**. It replaces the old split between a detailed plan and a separate task backlog.

Keep this file focused on **what we are working on next**. Do not let it become a long archive of completed work. When work is finished, remove or heavily compress the completed checklist and rely on git history, release notes, and `RELEASE_QA.md` for evidence.

Related docs:

- `AGENTS.md` — product invariants, engineering guardrails, and contribution rules.
- `ARCHITECTURE.md` — current app shape, ownership boundaries, and known scale limits.
- `RELEASE_QA.md` — build, test, simulator, real-device, and Files-provider validation log.
- `CODE_REVIEW.md` — lightweight review index; active review findings should be converted into actionable work in this file.

## Review snapshot

Date: 2026-04-28
Scope: stabilization pass for `CODE_REVIEW_2026-04-28.md`, focused on editor formatter extraction, undo/redo integration, line-ending preservation, semantic heading/task formatting, and narrow editor accessory cleanup.
Build/test status for this pass: `xcodebuild -list`, simulator destination discovery, focused formatter/editor/gutter tests, focused renderer diagnostics, and the full iPhone 17 Pro simulator XCTest suite passed. See `RELEASE_QA.md` for exact commands and counts.

Previous command-line simulator evidence remains in `RELEASE_QA.md`, but the 2026-04-28 run is the current automated evidence for this source state.

## Current direction

The project has a solid foundation: one selected Files workspace, one active live document session per app scene, guarded same-file split-view behavior, workspace-relative identity, a real `UITextView` editor boundary, explicit session/navigation/mutation policy seams, and broad test coverage around restore, autosave, mutation, recents, renderer, and theme flows.

The next phase should be **release stabilization and risk reduction**, not feature expansion. The main risks are:

1. preserving a verified green build after the latest edits,
2. finishing manual QA on real devices and Files providers,
3. preventing the coordinator, workspace manager, editor bridge, and renderer from regrowing,
4. making large-document editing progressively more local and measurable,
5. documenting unstructured task ownership before more async flows are added.

## Working rules for this file

- Add new findings here as checkable work.
- Keep each section small enough to finish in one focused batch.
- Prefer “done when” checks over broad aspirational notes.
- Move completed implementation detail out of this file once it is no longer useful for deciding what to do next.
- Keep runtime evidence in `RELEASE_QA.md`, not here.
- Do not recreate a separate task backlog unless the planning model is intentionally changed again.

---

## P0 — Restore a verified green build

### Finding

`Downward/App/AppCoordinator.swift` had a malformed stale-recent-file cleanup call in `loadDocument(at:)`. The call should use the current workspace snapshot once and remove the stale recent by workspace-relative path:

```swift
recentFilesStore.removeItem(
    using: snapshot,
    relativePath: staleRecentFileOpen.relativePath
)
```

The working tree now has this call shape. Treat the remaining work in this gate as build and test verification.

### Checklist

- [x] Fix the duplicated `using:` argument in `AppCoordinator.loadDocument(at:)`.
- [x] Run `xcodebuild -list` and confirm the `Downward` scheme is still available.
- [x] Run an iPhone simulator build.
- [x] Run an iPad simulator build.
- [x] Run the full XCTest suite.
- [x] Run the focused app-hosted smoke, restore, and mutation tests on iPhone simulator.
- [x] Run the focused app-hosted smoke, restore, and mutation tests on iPad simulator.
- [x] Record the exact commands, simulator names, OS versions, pass/fail counts, and any failures in `RELEASE_QA.md`.

### Done when

- [x] The app builds cleanly.
- [x] The full test suite passes or every failure is captured below as a new active finding.
- [x] `RELEASE_QA.md` reflects the current source state.

---

## P0 — Finish manual release QA before calling the current build shippable

### Finding

Automated tests cover many risky flows, but the remaining release risk is mostly runtime behavior: real Files-provider access, UIKit keyboard/accessory presentation, sheet hierarchy, and real-device layout.

### Checklist

- [ ] Fresh install opens cleanly with no workspace selected.
- [ ] Workspace picker opens and grants access.
- [ ] Workspace restore works after relaunch.
- [ ] Reconnect flow works when access is stale or missing.
- [ ] Recent files reopen by workspace-relative path.
- [ ] Open document survives background/foreground.
- [ ] Autosave survives rapid typing and document switching.
- [ ] Rename, move, and delete flows leave browser, editor, recents, and route state coherent.
- [ ] Settings sheet hierarchy works on compact width.
- [ ] Settings sheet hierarchy works on regular width.
- [ ] Keyboard accessory has no white-band flash on first presentation.
- [ ] Keyboard accessory remains correctly tinted after theme changes.
- [ ] Editor first visible line is correct below top chrome on iPhone portrait and landscape.
- [ ] Editor first visible line is correct below top chrome on iPad full screen and split view.
- [ ] Line number toggle is verified on real iPhone.
- [ ] Line number toggle is verified on iPad.
- [ ] Large document scrolling with line numbers remains smooth on device.
- [ ] Hidden syntax and line numbers are visually verified together.
- [ ] Larger heading text toggle is verified on real iPhone.
- [ ] Larger heading text toggle is verified on iPad.
- [ ] Enabling larger heading text is verified to disable line numbers visually.
- [ ] Local Files workspace has been tested.
- [ ] iCloud Drive workspace has been tested.
- [ ] Third-party Files provider workspace has been tested if one is available.
- [ ] Results are recorded in `RELEASE_QA.md`.

### Done when

- [ ] `RELEASE_QA.md` contains a current manual QA run.
- [ ] Any failures are added back into this file as P0 or P1 findings.

---

## P1 — Verify formatter undo/redo integration

### Finding

Markdown formatter actions need proof that they participate in the UIKit undo stack and keep accessory undo/redo state coherent.

### Checklist

- [x] Route formatter mutations through one coordinator helper that clamps ranges, registers undo, restores selection, refreshes editor state, and publishes undo/redo availability.
- [x] Add regression coverage for bold, link insertion, task prefix insertion, heading prefix insertion, and toggling existing inline formatting off.
- [x] Verify undo and redo text, selection, and accessory state where testable.

### Done when

- [x] `EditorUndoRedoTests` covers formatter undo and redo behavior directly.

---

## P1 — Programmatic editor mutations participate in undo/redo

### Finding

Task-list continuation and tap-to-toggle task checkbox edits bypass UIKit's default text edit path, so they need the same undo/redo guarantees as toolbar formatter commands.

### Checklist

- [x] Route task-list continuation through the shared programmatic text replacement helper.
- [x] Route task checkbox toggles through the shared programmatic text replacement helper.
- [x] Keep task checkbox presentation attributes restored after toggle, undo, and redo.
- [x] Audit remaining direct text-storage mutations and keep initial/configuration and presentation-only paths undo-free.
- [x] Return semantic line-format cursor information from the formatting plan layer for zero-length heading/task selections.

### Done when

- [x] Task continuation, generated-task removal, and task checkbox toggles are covered by integration undo/redo tests.
- [x] Semantic heading/task line-format selections are covered by focused coordinator and plan tests.

---

## P1 — Match editor status-bar chrome to editor theme

### Finding

The editor paints its theme background behind the status bar, but the status-bar and navigation chrome can still follow the global app appearance. Dark-on-dark or light-on-light chrome becomes hard to read when the selected editor theme does not match the app/phone appearance.

### Checklist

- [x] Derive the preferred editor chrome scheme from the resolved editor background luminance.
- [x] Resolve adaptive/system theme colors against the current app scheme so they continue to behave naturally.
- [x] Apply the editor chrome scheme only when `matchSystemChromeToTheme` is enabled.
- [x] Preserve the app-wide appearance setting when `matchSystemChromeToTheme` is disabled.
- [x] Add tests for the chrome scheme decision and view-model setting pass-through.
- [x] Add manual QA cases to `RELEASE_QA.md`.

### Done when

- [x] Simulator tests cover the luminance decision and setting pass-through.
- [ ] Real-device status-bar/navigation readability is verified with dark and light editor themes.

---

## P1 — Extract markdown formatting plans

### Finding

Pure markdown formatting transformations should live outside `MarkdownEditorTextViewCoordinator` so the coordinator can stay focused on UIKit application, selection, undo/redo, and restyling.

### Checklist

- [x] Add `MarkdownFormattingPlan.swift` for inline format, line prefix, heading, task, link, image, and URL-classification planning.
- [x] Move pure string-transformation coverage into `MarkdownFormattingPlanTests`.
- [x] Keep the coordinator responsible for applying plans to `UITextView`.

### Done when

- [x] Formatter planning has focused pure tests and no longer lives at the bottom of the coordinator file.

---

## P1 — Preserve CRLF in line-prefix formatting

### Finding

Line-prefix formatter planning must not normalize existing newline style when applying or removing prefixes.

### Checklist

- [x] Parse selected text into line segments that preserve `\n`, `\r\n`, and `\r` separators.
- [x] Cover applying and removing prefixes for LF, CRLF, CR, and trailing CRLF selections.

### Done when

- [x] `MarkdownFormattingPlanTests` confirms line-ending preservation for the reviewed cases.

---

## P1 — Improve semantic heading/task formatting

### Finding

Header and task commands should avoid stacking markdown markers on lines that are already headings or tasks.

### Checklist

- [x] Treat heading formatting as “set heading level” for each selected non-empty line.
- [x] Treat task formatting as a toggle for all-task selections and a normalization/prefix operation for mixed selections without stacking markers.
- [x] Cover normal, unchecked, checked, partial, star-task, ordered-task, and multi-line task cases.

### Done when

- [x] Existing headings and tasks no longer produce stacked markdown when formatted through the plan layer.

---

## P1 — Real-device QA for line numbers + hidden syntax

### Finding

Simulator and pure layout tests protect line-number behavior, but final release confidence still needs a real-device visual pass for the editor gutter and hidden syntax together.

### Checklist

- [ ] Verify line numbers with hidden syntax on a real iPhone.
- [ ] Verify line numbers with hidden syntax on a real iPad.
- [ ] Verify keyboard/accessory presentation does not shift the first visible line unexpectedly.
- [ ] Record device, OS version, Files provider, and result in `RELEASE_QA.md`.

### Done when

- [ ] Real-device line-number and hidden-syntax results are recorded, or failures are promoted to active P0/P1 findings.

---

## P1 — Keep architecture boundaries from regrowing

### Finding

The current architecture is much healthier than a monolithic SwiftUI app, but several files are still large enough to attract unrelated work:

- `WorkspaceManager.swift` — about 1,500 lines.
- `AppCoordinator.swift` — about 1,300 lines.
- `WorkspaceViewModel.swift` — about 1,000 lines.
- `PlainTextDocumentSession.swift` — about 980 lines.
- `MarkdownEditorTextViewCoordinator.swift` — about 930 lines.
- `EditorViewModel.swift` — about 750 lines.
- `MarkdownStyledTextRenderer.swift` — about 660 lines.

Large files are acceptable only when they are true ownership boundaries. New feature code should not be added to these files by default.

### Checklist

- [x] Add a short ownership comment to each large boundary file explaining what belongs there and what must be delegated elsewhere.
- [ ] Before adding new coordinator logic, check whether it belongs in `WorkspaceNavigationPolicy`, `WorkspaceSessionPolicy`, `WorkspaceMutationPolicy`, or `WorkspaceMutationService`.
- [ ] Before adding new workspace mutation logic, check whether it belongs in a smaller validator/name-normalizer/file-coordination helper extracted from `WorkspaceManager`.
- [ ] Before adding new document-save behavior, check whether it belongs in `PlainTextDocumentSession` or in `EditorViewModel` merge/presentation logic.
- [ ] Before adding new editor bridge behavior, check whether it belongs in `MarkdownEditorTextViewCoordinator`, `EditorKeyboardGeometryController`, `EditorChromeAwareTextView`, or a new focused collaborator.
- [ ] Add a lightweight architecture test or static checklist for “no new direct file-system writes from Views”.

### Done when

- [ ] New work has an obvious home without expanding `AppCoordinator` first.
- [ ] Any extraction is covered by focused tests before deleting old paths.
- [ ] `ARCHITECTURE.md` stays accurate after the extraction.

---

## P1 — Renderer scalability and markdown ownership

### Finding

The markdown renderer is still the most likely future performance bottleneck. The code now has useful seams (`MarkdownSyntaxScanner`, `MarkdownSyntaxVisibilityPolicy`, `MarkdownSyntaxStyleApplicator`, and TextKit layout handling), but rendering remains partly whole-document oriented and regex-heavy.

### Checklist

- [x] Define local work budgets for opening, typing in, and retheming representative 1k, 5k, 20k, and diagnostic 50k-line documents.
- [x] Turn those budgets into repeatable work-unit tests or diagnostics without fragile wall-clock thresholds.
- [x] Keep ordinary same-line edits on a bounded current-line restyling path for representative large documents.
- [x] Keep line-break, fenced-code, blockquote, setext, and horizontal-rule-sensitive edits on a deferred full-document fallback path until region-bounded state is implemented.
- [ ] Continue extracting semantic roles from `MarkdownStyledTextRenderer` into scanner/style collaborators before adding new markdown features; setext underline role is now explicit for fallback safety.
- [ ] Introduce a dirty-window calculation for edit ranges and expand it to safe markdown boundaries.
- [ ] Add cacheable line/block state for fenced code and other constructs that affect following lines.
- [x] Keep hidden syntax as a TextKit/layout concern; do not collapse syntax markers with font-size, kerning, or whitespace hacks.

### Done when

- [x] Typing latency has repeatable diagnostics for representative large files.
- [x] The renderer has a clear local-work path for ordinary edits.
- [ ] New markdown features are expressed through semantic roles, not direct one-off attributed-string mutations.

---

## P1 — Audit async task ownership

### Finding

The project generally uses main-actor state and generation guards well, but there are still several unstructured `Task { ... }` sites in view models and settings actions. That is fine only when ownership is explicit and stale-result suppression is guaranteed.

Important examples to audit:

- `EditorViewModel.handleDisappear(for:)` and scene-phase flushing.
- `EditorViewModel` load, autosave, conflict-resolution, and observation tasks.
- `WorkspaceViewModel` file-operation tasks.
- `RootViewModel` bootstrap/retry/reconnect tasks.
- Settings theme import/export tasks.

### Checklist

- [x] Classify current production `Task { ... }` sites for this pass and use the audit to pick the safest small fix.
- [x] Make editor disappear/background save flushing view-model-owned, cancellable, and document-identity gated.
- [x] Add focused tests for editor immediate flush, duplicate suppression, delayed-autosave cancellation, and route-change stale flush protection.
- [x] Store and cancel view-model-owned tasks when route, workspace, or document identity changes (`EditorViewModel`, `WorkspaceViewModel`, `ThemeStore`).
- [x] Ensure remaining reviewed tasks that mutate state after `await` check identity/generation or delegate to coordinator/store-owned stale-result suppression.
- [x] Add comments only where ownership is non-obvious in the editor flush path.
- [x] Add tests for newly discovered stale-result paths (`ThemeStoreTests` overlapping explicit mutations).
- [x] Review `RootViewModel` bootstrap/retry/reconnect one-shot tasks for explicit stale-result handling; they delegate to AppCoordinator transition generation guards covered by app-hosted restore/mutation tests.
- [x] Review Settings theme import/export view-owned tasks for dismissal and cancellation behavior; explicit persistence is ThemeStore-owned and serialized.
- [x] Review `WorkspaceViewModel` load, file-operation, and search-observation tasks for stale-result handling.
- [x] Add focused lifecycle tests before changing `PlainTextDocumentSession` observation fallback or `MarkdownEditorTextViewCoordinator` delayed TextKit/UI tasks.

### Done when

- [x] A future contributor can tell who owns every long-lived task.
- [x] Disappearing views, route changes, and workspace changes cannot apply stale async results in the reviewed editor, root, workspace, and settings paths.

---

## P1 — Workspace mutation and recents coherence

### Finding

Workspace-relative identity is the right product model and is applied broadly, but mutation flows remain high risk because they coordinate browser state, editor state, recents, routes, and session restoration in one operation.

### Checklist

- [x] Add or verify coverage for stale recent-file opens after files are deleted externally (`MarkdownWorkspaceAppTrustedOpenAndRecentTests`).
- [x] Add or verify coverage for folder rename/move while a descendant is in recents (`MarkdownWorkspaceAppMutationFlowTests`, `RecentFilesStoreTests`).
- [x] Add or verify coverage for deleting a folder that contains the visible editor route (`MarkdownWorkspaceAppMutationFlowTests`).
- [ ] Verify case-only rename behavior on a case-insensitive test volume; existing platform-gated `WorkspaceManagerRestoreTests` skipped in the latest simulator run.
- [x] Add or verify coverage for move-to-same-folder and move-to-current-location no-op behavior (`WorkspaceManagerRestoreTests`).
- [x] Keep mutation preflight decisions in `WorkspaceMutationPolicy` rather than inline view logic (`WorkspaceCoordinatorPolicyTests`).
- [x] Keep final path validation inside workspace/domain boundaries (`WorkspaceManagerRestoreTests`, `WorkspaceSnapshotPathResolverTests`).

### Done when

- [ ] Browser, editor, recents, restore state, and navigation route agree after every supported mutation on simulator and manual device QA.
- [x] Stale recent-file items are removed quietly and safely.

---

## P1 — Keyboard accessory and editor chrome contract

### Finding

The current contract is intentionally conservative: keep the keyboard accessory host clear/non-opaque, theme the toolbar controls, and avoid painting private keyboard host/container backgrounds without real-device evidence.

### Checklist

- [ ] Keep the accessory wrapper background clear.
- [ ] Keep the accessory wrapper non-opaque.
- [ ] Keep toolbar background, shadow, and tint treatment explicit.
- [ ] Verify first keyboard presentation on real iPhone.
- [ ] Verify first keyboard presentation on real iPad.
- [ ] Verify iPad split-view keyboard behavior.
- [ ] Verify interactive keyboard dismissal.
- [ ] Verify accessory controls after switching built-in and custom themes.
- [ ] Do not paint private keyboard-host/container backgrounds unless a device QA pass proves it is safe.

### Done when

- [ ] Keyboard accessory behavior is confirmed in `RELEASE_QA.md` on real hardware or explicitly deferred with the reason.

---

## P1 — Theme import/export polish

### Finding

Theme import/export has real infrastructure now, but the user-facing contract should stay explicit: normal workspace `.json` files open as text documents; JSON theme import happens only through Settings; export behavior should make clear whether it is exporting a saved theme or current draft state.

### Checklist

- [x] Confirm export labels match actual behavior.
- [x] Confirm invalid JSON, unsupported schema, oversized file, duplicate name, and partial bundle errors remain user-readable.
- [x] Confirm ordinary workspace `.json` files open in the editor route.
- [x] Confirm explicit Settings import remains the only theme-import path.
- [ ] Manually import from local Files storage.
- [ ] Manually import from iCloud Drive.
- [ ] Manually import from a third-party provider if available.
- [ ] Export to local Files storage.
- [ ] Export to iCloud Drive.
- [ ] Re-import exported JSON successfully.

Automated evidence: `ThemeEditorDraftExport` uses the explicit `Export Draft` label and tests prove exported JSON reflects current draft values, filename sanitization remains stable, blank names fall back to `Theme.json`, and exported JSON imports again. `ThemeStoreTests` cover invalid JSON, unsupported schema, oversized files, duplicate names, invalid themes inside arrays/bundles, empty arrays/bundles, non-theme JSON objects, serialized explicit imports, and ignored user cancellation. `MarkdownWorkspaceAppTrustedOpenAndRecentTests`, `MarkdownWorkspaceAppSmokeTests`, and `WorkspaceNavigationModeTests` cover workspace/browser, recents, stale recents, and restore paths for ordinary `.json` editor documents without changing `ThemeStore`.

### Done when

- [x] The theme exchange contract is obvious to non-developer users.
- [ ] Manual results are recorded in `RELEASE_QA.md`.

---

## P2 — Placeholder-backed product surfaces

### Finding

Some settings affordances are intentionally placeholder-backed. That is acceptable before release only if they are visibly non-final and cannot create broken user expectations.

### Checklist

- [ ] StoreKit tips remain disabled or clearly placeholder-only until StoreKit infrastructure exists.
- [ ] App Store review/rating routing remains disabled or clearly placeholder-only until a real app identifier/path exists.
- [ ] Legal/privacy links remain disabled or clearly placeholder-only until real URLs exist.
- [x] Line numbers are backed by the editor, settings persistence, and focused tests.
- [x] Larger heading text is backed by the renderer, settings persistence, and focused tests.
- [ ] Future markdown settings such as tables and footnotes remain disabled until renderer support exists.

### Done when

- [ ] No Settings control promises a feature that is not backed by working implementation.

---
