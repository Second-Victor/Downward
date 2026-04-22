# CODE_REVIEW

## Review scope

- Static code review of the uploaded `Downward.zip` snapshot.
- Reviewed `App/`, `Domain/`, `Infrastructure/`, `Features/`, `Shared/`, `Tests/`, and the archive contents.
- I could not run `xcodebuild` or launch the app in this environment, so anything marked **runtime verification needed** is based on source inspection plus the screenshots you provided.


## 2026-04-21 review refresh

This refresh was done against the latest uploaded `Downward.zip` after the keyboard safe-area fix and before/with the large-file typing-latency patch in this review.

### Checked off in this refresh

- **P0 editor height / clipping** — fixed in current code. `MarkdownEditorTextView` now uses an effectively unbounded text container, tracks width, implements `sizeThatFits`, lowers vertical layout priorities, and has `MarkdownEditorTextViewSizingTests`.
- **P0 keyboard accessory transparency** — fixed in current code. The root cause was the SwiftUI editor container ignoring only `.container` safe area, not `.keyboard`; `EditorScreen` now includes `.ignoresSafeArea(.keyboard, edges: .bottom)`.
- **P0 initial keyboard underlap** — closed as obsolete. The current implementation no longer uses accessory-height underlap subtraction; it matches the prototype model by reserving the full keyboard overlap and letting the accessory overlay the full-height editor.
- **P1 dead `showsKeyboardToolbar` state** — fixed. The property is gone and tests now target the actual UIKit accessory view.
- **P1 accessory appearance lifecycle hooks** — closed as obsolete. The remaining transparency issue was not solved by toolbar appearance hooks; the final fix was the keyboard safe-area underlay. The current accessory intentionally matches the prototype-style passive `UIToolbar` wrapper.

### Still relevant after this refresh

- Undo/redo/dismiss still have two command paths: visible accessory actions plus token commands.
- Top-chrome safe-area math still needs real-device verification.
- Workspace snapshot path lookup, search, recents pruning, and document read/write memory churn are still relevant performance items.
- Large files now have a separate P0 typing-latency item because the uploaded `large_test_file.md` exposed multi-second keypress lag.
- Large files/editor performance needs real device verification and, ideally, regression coverage.

## Executive summary

The project has **good bones**:

- the workspace trust boundary is clearly treated as a real product invariant,
- document/session logic is kept out of views more than in many SwiftUI apps,
- actor boundaries are used in the right places for workspace/document work,
- the editor has meaningful unit coverage,
- the repo docs (`AGENTS.md`, `ARCHITECTURE.md`, `TASKS.md`) are unusually strong and mostly tell the truth.

The biggest current risks are not basic data safety. They are:

1. **editor layout / keyboard accessory geometry instability**,
2. **duplicate or stale editor paths left over from earlier implementations**,
3. **hot-path performance on larger workspaces and larger files**,
4. **oversized files that are becoming hard to reason about safely**.

## Project metrics from this snapshot

- **80 Swift files total**
  - **63 app files**
  - **17 test files**
- Largest files:
  - `Tests/MarkdownWorkspaceAppSmokeTests.swift` — **3946 lines**
  - `Downward/App/AppCoordinator.swift` — **1732 lines**
  - `Downward/Domain/Workspace/WorkspaceManager.swift` — **1509 lines**
  - `Downward/Features/Editor/MarkdownStyledTextRenderer.swift` — **1436 lines**
  - `Downward/Features/Workspace/WorkspaceViewModel.swift` — **1049 lines**
  - `Downward/Domain/Document/PlainTextDocumentSession.swift` — **978 lines**
  - `Downward/Features/Editor/MarkdownEditorTextView.swift` — **807 lines**

## What is already strong and should be preserved

- `LiveWorkspaceManager` is clearly trying to keep the **workspace root** as the only trust boundary.
- `PlainTextDocumentSession` is taking the right stance that the **live editor buffer stays authoritative while typing**.
- The app is disciplined about **workspace-relative identity** being primary.
- The docs explicitly protect calm autosave behavior and exceptional-only conflict UI.
- The test suite is broad and covers real risk areas: restore, autosave, conflict handling, enumeration, security-scoped access, recents, and search.

---

# 1) P0 / release-blocking issues

## [x] P0 — Fix the editor height / clipping bug in `MarkdownEditorTextView`

**Files**
- `Downward/Features/Editor/MarkdownEditorTextView.swift:27-54`
- `Downward/Features/Editor/MarkdownEditorTextView.swift:77-99`
- `Downward/Features/Editor/EditorScreen.swift:49-80`

**Evidence**
- The current editor is created with `NSTextContainer(size: .zero)` at line 30.
- The representable does **not** implement `sizeThatFits(_:uiView:context:)`.
- The `UITextView` only lowers **horizontal** compression resistance at line 54, not vertical.
- Your screenshot shows the editor content visually stopping around mid-screen, leaving a large dead area below.

**Why this matters**
- This is a **core editing bug**, not just polish.
- It also makes the keyboard accessory debugging misleading, because a half-height editor can make a transparent accessory look opaque simply because there is no text behind it.

**Recommended change**
- Create the text container with an effectively unbounded height.
- Make the text container track width.
- Implement `UIViewRepresentable.sizeThatFits` so SwiftUI gives the text view the full proposed height.
- Lower **vertical** hugging/compression resistance as well.
- Re-test before making more keyboard-bar visual tweaks.

**Done when**
- A long document fills the full editor area on iPhone and iPad.
- There is no large blank dead zone under the text before the keyboard appears.
- The bug reproducing in your screenshot is gone on device and simulator.

**Status after 2026-04-21 refresh**
- Fixed in code: unbounded text container height, width tracking, full-proposal `sizeThatFits`, lowered vertical layout priorities, and sizing regression coverage are present.
- Keep real-device coverage in the QA checklist, but this no longer belongs in the active P0 bug list.

---

## [x] P0 — Fix the keyboard accessory “transparent only after touch/scroll” bug

**Files**
- `Downward/Features/Editor/MarkdownEditorTextView.swift:300-327`
- `Downward/Features/Editor/MarkdownEditorTextView.swift:454-477`
- `Downward/Features/Editor/MarkdownEditorTextView.swift:531-583`
- `Downward/Features/Editor/MarkdownEditorTextView.swift:699-790`

**Observed bug**
- You reported: **the bar the buttons sit on above the keyboard is only transparent when the user touches and scrolls down**.

**My read from the code**
- The accessory itself is configured to be transparent (`backgroundColor = .clear`, `isOpaque = false`, transparent `UIToolbarAppearance`, clear background/shadow images).
- That means the symptom is **likely not a simple “toolbar is opaque” bug**.
- The more likely causes are:
  1. the editor is not filling height yet, so there is no content under the accessory until the user scrolls,
  2. the underlap inset math is not correct on the **first** keyboard presentation,
  3. the toolbar appearance is only configured in `init`, not re-applied when the accessory is attached to the keyboard host view or when traits change.

**Important note**
- This item needs **runtime verification** after the height bug above is fixed, because right now the sizing bug can mask the real root cause.

**Recommended change**
- Fix the full-height editor issue first.
- Then instrument and verify:
  - `keyboardOverlapInset`
  - `accessoryHeightToUnderlap(...)`
  - final `contentInset.bottom`
  - final `verticalScrollIndicatorInsets.bottom`
- Re-apply accessory appearance when the accessory moves into a window and when the trait collection changes.
- Confirm the accessory host view itself is not drawing an inherited background.

**Done when**
- The accessory looks transparent immediately when the keyboard appears.
- Transparency does not depend on the user scrolling first.
- The same behavior is confirmed on a real iPhone, not just simulator.

**Status after 2026-04-21 refresh**
- Fixed in code and confirmed by the user.
- Root cause: the editor container ignored `.container` safe areas but not the keyboard safe area, so the transparent accessory initially sat over SwiftUI background instead of live editor content.
- Fix: `EditorScreen` now applies `.ignoresSafeArea(.keyboard, edges: .bottom)` to the editor container.

---

## [x] P0 — Stabilize initial keyboard underlap so text is visible behind the accessory on first presentation

**Files**
- `Downward/Features/Editor/MarkdownEditorTextView.swift:312-319`
- `Downward/Features/Editor/MarkdownEditorTextView.swift:551-569`
- `Downward/Features/Editor/MarkdownEditorTextView.swift:612-635`

**Problem**
- The editor underlap is currently computed as:
  - keyboard overlap
  - minus accessory height
- That is the right idea.
- The problem is that the current implementation depends on keyboard geometry being available and correct at the right moment. If that geometry is stale or the editor has not finished sizing, users see a blank band rather than content under the accessory.

**Why this matters**
- This directly affects the “floating, native” feeling of the keyboard controls.
- If the content does not underlap correctly, the accessory always feels like a bar sitting *above* the editor instead of part of the editor chrome.

**Recommended change**
- After the full-height fix, verify the first keyboard presentation path explicitly.
- Ensure the first responder path and first `keyboardWillChangeFrame` path produce the same final inset as later scroll interactions.
- Add targeted test coverage for initial keyboard presentation, not only steady-state `keyboardOverlapInset` math.

**Done when**
- When the keyboard first appears, text is already visible behind the transparent accessory.
- The user does not need to scroll or tap to get the intended visual effect.

**Status after 2026-04-21 refresh**
- Closed as obsolete. The current implementation no longer uses accessory-height underlap subtraction.
- The working model is the prototype model: reserve full keyboard overlap in scroll insets, keep the editor full-height, and let the accessory overlay the editor content.
- The real transparency fix was `.ignoresSafeArea(.keyboard, edges: .bottom)`, not more underlap math.

---

## [ ] P0 — Fix large-file typing latency in `MarkdownEditorTextView`

**Files**
- `Downward/Features/Editor/MarkdownEditorTextView.swift:248-320`
- `Downward/Features/Editor/MarkdownStyledTextRenderer.swift:31-297`
- `Downward/Features/Editor/EditorViewModel.swift:163-175`
- `Tests/EditorUndoRedoTests.swift`

**Observed bug**
- The uploaded `large_test_file.md` is around 250 KB and repeated editing in that file produced multi-second keypress lag.

**Likely root cause from source inspection**
- In `hiddenOutsideCurrentLine` mode, `textViewDidChangeSelection(_:)` can re-render the full markdown document after each typed character because the revealed current-line `NSRange` changes length while the cursor remains on the same line.
- A full render runs many whole-document passes over headings, code blocks, inline styles, links/images, and hidden-syntax ranges. That is acceptable on load or when moving to another line, but not on every keypress in a large file.
- The hot path also did large string equality checks before publishing the editor buffer to SwiftUI/session state.

**Patch included with this review**
- Track whether the edit inserted or removed a line break via `textView(_:shouldChangeTextIn:replacementText:)`.
- When typing ordinary characters on the same current line, update the stored revealed-line range but skip the full attributed re-render.
- Still re-render when moving to a different line, when editing line breaks, or when making an explicit selection.
- Avoid one unnecessary full-string equality check in `textViewDidChange(_:)` and another in `EditorViewModel.handleTextChange(_:)`.
- Cache compiled markdown regexes so repeated full renders do not recompile every pattern.
- Add a focused regression test for same-line typing not forcing a hidden-syntax rerender.

**Done when**
- Editing the uploaded large markdown file is responsive in both syntax modes, especially `hiddenOutsideCurrentLine`.
- Typing ordinary characters on the same line does not trigger full-document re-rendering.
- Moving the cursor to another line still updates hidden-syntax presentation.
- Line-break edits still refresh the current-line presentation correctly.
- Confirmed on simulator and a real iPhone.

**Status after 2026-04-21 refresh**
- Patch prepared, but not checked off yet because it needs Xcode/device verification.

---

# 2) P1 user-visible correctness / UX cleanup

## [ ] P1 — Consolidate undo / redo / dismiss into a single source of truth

**Files**
- `Downward/Features/Editor/EditorViewModel.swift:300-317`
- `Downward/Features/Editor/MarkdownEditorTextView.swift:123-125`
- `Downward/Features/Editor/MarkdownEditorTextView.swift:415-444`
- `Downward/Features/Editor/MarkdownEditorTextView.swift:492-529`

**Problem**
- The editor currently has **two command paths** for the same actions:
  1. token-based commands from the SwiftUI view model,
  2. direct accessory button actions on the `UITextView`.

**Why this matters**
- This increases the number of states that must stay in sync.
- It makes the code harder to reason about during regressions.
- It also makes tests less representative if the visible UI uses one path and tests assert the other.

**Recommended change**
- Pick one on-screen interaction path as canonical.
- Keep the token path only if you still need it for non-accessory invocations such as external commands or future hardware keyboard shortcuts.
- Document which layer owns the visible toolbar behavior.

**Done when**
- One code path is clearly canonical for the visible accessory buttons.
- The other path is either removed or explicitly documented as secondary.

---

## [x] P1 — Remove dead `showsKeyboardToolbar` state and update tests that still assume the old UI

**Files**
- `Downward/Features/Editor/EditorViewModel.swift:163-165`
- `Tests/EditorUndoRedoTests.swift:11-24`
- `Tests/EditorUndoRedoTests.swift:40-45`

**Problem**
- `showsKeyboardToolbar` still exists in `EditorViewModel`, but `EditorScreen` no longer reads it.
- Tests still assert that property even though the visible on-screen toolbar is now driven by the `inputAccessoryView` path.

**Why this matters**
- It creates false confidence.
- Passing tests can suggest the keyboard-toolbar feature works when they are only asserting leftover state.

**Recommended change**
- Remove `showsKeyboardToolbar` if it is no longer part of the product surface.
- Rewrite tests to assert the actual current UI behavior: accessory existence, enabled states, inset behavior, and real focus transitions.

**Done when**
- There is no dead keyboard-toolbar state left in `EditorViewModel`.
- Tests only assert behavior that still exists in the current editor architecture.

**Status after 2026-04-21 refresh**
- Fixed. `showsKeyboardToolbar` no longer exists, SwiftUI `.keyboard` toolbar items are gone, and tests assert the actual `inputAccessoryView` toolbar path.

---

## [ ] P1 — Re-test and harden top-chrome safe-area math on device

**Files**
- `Downward/Features/Editor/EditorScreen.swift:79-80`
- `Downward/Features/Editor/MarkdownEditorTextView.swift:300-309`
- `Downward/Features/Editor/MarkdownEditorTextView.swift:638-655`

**Problem**
- The editor ignores container safe areas and then manually reconstructs top clearance from navigation-bar / safe-area geometry.
- This is workable, but it is fragile and is already called out in `TASKS.md` as a real product issue.

**Why this matters**
- This is exactly the sort of geometry code that looks correct on simulator and still fails on a real iPhone or iPad.

**Recommended change**
- Keep the dynamic approach, but verify it on:
  - iPhone portrait
  - iPhone landscape
  - iPad split view
  - large dynamic type
- Add at least one dedicated regression test or diagnostic harness around the resulting top inset.

**Done when**
- The first visible line, placeholder, and caret start position all align on iPhone and iPad.
- No device-specific magic offsets are required.

---

## [x] P1 — Re-apply keyboard accessory appearance on attachment and trait changes

**Files**
- `Downward/Features/Editor/MarkdownEditorTextView.swift:734-745`
- `Downward/Features/Editor/MarkdownEditorTextView.swift:775-789`

**Problem**
- Transparent appearance is configured only in `KeyboardAccessoryToolbarView.init(...)`.
- There is no `didMoveToWindow`, `layoutSubviews` re-application, or `traitCollectionDidChange` hook to keep the accessory appearance stable when the keyboard host or system appearance changes.

**Why this matters**
- It is a likely contributor to the “only looks right after interaction” class of bugs.
- It is also a likely future bug for dark mode / keyboard-style transitions.

**Recommended change**
- Reapply the appearance in lifecycle hooks that are actually exercised when the accessory joins the keyboard host view.
- Explicitly test light/dark appearance changes if the app supports both.

**Done when**
- The accessory appearance is stable across presentation, dismissal, and appearance changes.

**Status after 2026-04-21 refresh**
- Closed as obsolete for the current implementation. The final transparency bug was not caused by missing toolbar lifecycle hooks.
- The accessory now intentionally behaves like the prototype: a passive clear wrapper hosting a stock `UIToolbar`; the editor underlay is provided by ignoring the keyboard safe area.

---

# 3) P1 performance and scalability

## [ ] P1 — Add cached URL ↔ relative-path indexes to `WorkspaceSnapshot`

**Files**
- `Downward/Domain/Workspace/WorkspaceSnapshotPathResolver.swift:8-47`
- `Downward/Domain/Workspace/WorkspaceSnapshotPathResolver.swift:49-73`

**Problem**
- `WorkspaceSnapshot.relativePath(for:)` does a recursive tree walk every time.
- `WorkspaceSnapshot.fileURL(forRelativePath:)` also does a recursive tree walk every time.
- This is fine for small workspaces but becomes expensive once the snapshot grows.

**Why this matters**
- Other parts of the app already call these methods repeatedly in hot paths.
- That turns tree traversal into an avoidable performance cost.

**Recommended change**
- Build snapshot indexes once during snapshot creation:
  - normalized URL path → relative path
  - relative path → URL
- Keep the current APIs, but back them with O(1) lookup tables.

**Done when**
- Search, recents pruning, and path-resolution flows no longer recursively walk the entire snapshot for repeated lookups.

---

## [ ] P1 — Rewrite `WorkspaceSearchEngine` to carry relative paths during traversal instead of re-resolving every file

**Files**
- `Downward/Features/Workspace/WorkspaceSearchEngine.swift:21-37`
- `Downward/Features/Workspace/WorkspaceSearchEngine.swift:40-72`

**Problem**
- Search recursively traverses the tree, but for every file match candidate it calls `snapshot.relativePath(for: file.url)`.
- That means one traversal is nested inside another traversal.

**Why this matters**
- On larger workspaces, this becomes effectively O(n²) behavior.
- Search should feel instantaneous because it operates on an already in-memory snapshot.

**Recommended change**
- Carry the current relative path down the recursive traversal.
- Do not ask the snapshot to rediscover the path for each file.
- If you add snapshot indexes, search can also just use the cached path mapping.

**Done when**
- Search traverses the tree once per query.
- Search does not call `snapshot.relativePath(for:)` for every file.

---

## [ ] P1 — Rewrite `RecentFilesStore.pruneInvalidItems(using:)` to avoid flattening the whole tree and then re-walking it

**Files**
- `Downward/Domain/Persistence/RecentFilesStore.swift:60-64`
- `Downward/Domain/Persistence/RecentFilesStore.swift:255-267`
- `Downward/Domain/Workspace/WorkspaceSnapshotPathResolver.swift:8-47`

**Problem**
- `pruneInvalidItems(using:)` builds a set of valid paths by:
  1. flattening all file URLs,
  2. then calling `snapshot.relativePath(for:)` on every file URL.
- That is correct, but needlessly expensive.

**Why this matters**
- This is a maintenance and performance issue in a workflow that can happen during refresh and mutation reconciliation.

**Recommended change**
- Reuse a snapshot index or carry paths while traversing.
- Avoid generating `[URL]` only to immediately convert them back to relative paths.

**Done when**
- Recent-file pruning is a single traversal or index lookup.
- No repeated whole-tree path re-resolution remains in that flow.

---

## [ ] P1 — Reduce large-file memory churn in `PlainTextDocumentSession`

**Files**
- `Downward/Domain/Document/PlainTextDocumentSession.swift:749-760`
- `Downward/Domain/Document/PlainTextDocumentSession.swift:765-775`
- `Downward/Domain/Document/PlainTextDocumentSession.swift:777-790`

**Problem**
- Current read flow does:
  1. `Data(contentsOf:)`
  2. decode to `String`
  3. re-encode to `Data(text.utf8)` to compute the digest
- Current save flow encodes the text again for writing and separately computes the digest from the string path.

**Why this matters**
- Large markdown / JSON / text files will pay extra memory and CPU cost.
- This lines up with `TASKS.md`, which already flags large-file pressure as a current risk.

**Recommended change**
- On read: hash the raw file data you already loaded before decoding it to a string.
- On save: reuse the encoded UTF-8 data you are already writing.
- Consider thresholds for very large files so versioning work stays predictable.

**Done when**
- Open/save/revalidate do not create unnecessary extra full-buffer copies.
- Large-file behavior is measured and documented.

---

# 4) P1/P2 architecture and maintainability

## [ ] P1 — Split `MarkdownEditorTextView.swift` by responsibility

**File**
- `Downward/Features/Editor/MarkdownEditorTextView.swift` (**807 lines**)

**Problem**
This file currently owns all of these responsibilities at once:

- SwiftUI `UIViewRepresentable` construction
- coordinator lifecycle
- renderer refresh logic
- selection preservation
- keyboard notification handling
- accessory toolbar construction
- top-chrome overlap math
- keyboard underlap math
- custom `UITextView` subclass
- custom accessory view class

**Why this matters**
- This is now the highest-risk UI file in the app.
- Small changes in one area can easily break another.
- It is already hard to review and even harder to debug quickly.

**Recommended split**
- `MarkdownEditorTextView.swift` — representable surface only
- `MarkdownEditorTextViewCoordinator.swift` — text sync / selection / rendering
- `EditorKeyboardAccessoryToolbarView.swift` — accessory UI only
- `EditorKeyboardGeometryController.swift` — keyboard overlap + insets
- `EditorChromeAwareTextView.swift` — subclass only

**Done when**
- No single editor file owns both rendering and keyboard geometry and accessory UI.

---

## [ ] P1 — Split `AppCoordinator.swift` before more feature logic accumulates there

**File**
- `Downward/App/AppCoordinator.swift` (**1732 lines**)

**Problem**
- The coordinator is already doing bootstrap, restore, reconnect, refresh, create/rename/delete/move, route handling, editor handoff, and alert coordination.

**Why this matters**
- The docs explicitly warn against letting `AppCoordinator` become the architecture again.
- At its current size, it is already the easiest place for “just one more rule” to land.

**Recommended split**
- Extract by policy/flow, not by arbitrary helper name.
- Strong candidates:
  - restore + reconnect application
  - workspace mutation reconciliation
  - open-document routing / recent-file flows

**Done when**
- New navigation and workspace rules land in policy types or dedicated collaborators, not inline in the coordinator.

---

## [ ] P2 — Split `WorkspaceViewModel.swift`

**File**
- `Downward/Features/Workspace/WorkspaceViewModel.swift` (**1049 lines**)

**Problem**
- It currently owns snapshot loading, refresh, search, folder expansion state, recents sheet flow, create/rename/delete/move flows, and settings routing.

**Why this matters**
- The workspace screen is one of the app’s main surfaces.
- A very large view model raises regression risk every time browser features move.

**Recommended split**
- Separate search state, mutation prompts, and folder-expansion behavior into dedicated helpers.

**Done when**
- `WorkspaceViewModel` reads as a feature orchestrator, not a storage bucket for every workspace-screen concern.

---

## [ ] P1 — Remove the stale `EditorTextViewHostBridge` path after first extracting the shared layout constants

**Files**
- `Downward/Features/Editor/EditorTextViewHostBridge.swift:1-169`
- `TASKS.md` section “Remove stale editor bridge leftovers”

**Problem**
- The file is documented as a `TextEditor` bridge, but the shipping editor is no longer `TextEditor`.
- This leaves the codebase telling two different stories.
- `EditorTextViewLayout` currently lives in this file, so the bridge cannot simply be deleted without moving those constants.

**Why this matters**
- This is exactly the kind of historical leftover that confuses future changes.

**Recommended change**
- Move `EditorTextViewLayout` into its own dedicated file.
- Delete `EditorTextViewHostBridge` and its tests if it is no longer used.
- Update docs to reflect one editor implementation path only.

**Done when**
- There is no `TextEditor`-specific bridge file left in the shipping editor path.

---

## [ ] P2 — Split the giant smoke-test suite into true smoke flows plus targeted suites

**File**
- `Tests/MarkdownWorkspaceAppSmokeTests.swift` (**3946 lines**)

**Problem**
- The file is extremely valuable, but now too large to stay healthy.

**Why this matters**
- Giant mixed-purpose test files are hard to debug, hard to name clearly, and discourage maintenance.

**Recommended change**
- Keep only true end-to-end “app still basically works” flows in the smoke file.
- Move feature-specific cases into smaller suites.

**Done when**
- The smoke suite is short enough to scan quickly.
- Failing tests identify a specific feature area immediately.

---

# 5) Test and QA gaps

## [ ] P0/P1 — Add a real-device editor regression checklist specifically for keyboard accessory behavior

**Why**
The repo docs already say real devices are the source of truth for editor chrome, and the recent regressions prove that is correct.

**Suggested checklist**
- keyboard appears on first tap
- accessory buttons appear immediately
- accessory is visually transparent immediately
- text is visible behind accessory immediately
- long document still fills full editor height
- keyboard dismiss works interactively and via button
- undo/redo enabled states stay correct while typing
- file switch while keyboard is visible does not leave stale insets
- iPhone and iPad both verified

**Done when**
- This checklist is part of every editor-geometry/accessory change.

---

## [x] P1 — Add tests for full-height editor sizing

**Gap**
- There is test coverage for accessory existence and inset math, but not enough around “does the representable actually occupy the full proposed height?”

**Recommended tests**
- host `MarkdownEditorTextView` in a fixed-size container and assert its rendered `UITextView` frame matches the proposal
- assert large documents do not truncate visible height

**Done when**
- The half-height editor bug would fail a test before reaching a device.

**Status after 2026-04-21 refresh**
- Fixed in current code. `Tests/MarkdownEditorTextViewSizingTests.swift` hosts the representable in a fixed-size container and asserts the `EditorChromeAwareTextView` fills the proposed width and height.

---

## [ ] P1 — Add tests for accessory transparency / underlap timing, not just steady-state enabled states

**Files**
- `Tests/EditorUndoRedoTests.swift`

**Gap**
- Current tests prove the accessory exists and button enabled states update.
- They do **not** prove the accessory is visually correct on the first keyboard presentation.

**Recommended tests**
- test initial `keyboardOverlapInset == 0` → keyboard frame change → final inset state
- test keyboard hide resets the underlap correctly
- add a diagnostic-only path if needed to inspect first-presentation values

**Done when**
- The “transparent only after scroll” class of bug is much harder to reintroduce.

---

## [ ] P2 — Add performance regression coverage for large snapshots and larger files

**Why**
- The app is already mature enough that performance regressions are now a real product risk.

**Recommended coverage**
- synthetic snapshot with thousands of nodes
- recent-file pruning against a large tree
- search against a large tree
- open/save/revalidate on larger text files

**Done when**
- Path lookup and file-size regressions can be caught before shipping.

---

# 6) Documentation and repo hygiene

## [ ] P1 — Update the docs once the keyboard accessory architecture is stable

**Files**
- `AGENTS.md`
- `ARCHITECTURE.md`
- `TASKS.md`

**Problem**
- The docs are strong overall, but the keyboard accessory approach has shifted significantly during the recent patch attempts.
- Once the implementation settles, the docs should reflect the final ownership story.

**Done when**
- The docs explain the actual shipping keyboard accessory approach and its constraints.

---

## [ ] P2 — Clean archive/repo noise and add or verify ignore rules

**Archive contents observed in this snapshot**
- `.DS_Store`
- `.git/`
- `__MACOSX/`
- `.codex/`
- `.pi/`

**Why this matters**
- It makes shared archives noisy.
- It raises the odds of accidental commits of local/editor-specific data.

**Recommended change**
- Add or verify `.gitignore` coverage.
- Exclude macOS archive cruft and local tool directories from shared zips and commits.

**Done when**
- Fresh shared archives contain only project files that matter.

---

# Suggested fix order after 2026-04-21 refresh

1. **Verify and land the large-file typing-latency fix.** This is now the highest active editor blocker.
2. **Run the real-device keyboard/accessory regression checklist** to protect the safe-area fix.
3. **Consolidate undo / redo / dismiss command ownership.**
4. **Keep top-chrome safe-area verification on the device QA list.**
5. **Split the editor file into smaller units.**
6. **Fix snapshot path lookup hot paths.**
7. **Reduce large-file read/write memory churn.**
8. **Remove stale bridge leftovers.**
9. **Split the oversized smoke tests and coordinator/view model files over time.**

---

# Bottom line

This codebase is closer to “solid app with a few unstable hot zones” than “messy rewrite candidate.”

The most important immediate conclusion is:

- **do not keep chasing accessory visuals until the editor sizing bug is fixed**, because it is currently distorting what you are seeing,
- then lock down **initial keyboard underlap and transparency behavior on real devices**,
- then remove the stale editor paths so the repo tells one clear story again.
