# Code Review — 2026-04-28

## Scope

Reviewed the uploaded `Downward.zip` project archive.

This is a static code review only. I could not run `xcodebuild`, the iOS simulator, or the XCTest suite in this environment because it is Linux-based and does not have Xcode or UIKit runtime support.

The uploaded project contains a Git working tree with these local modifications relative to the latest commit:

```text
 M Downward/Features/Editor/EditorChromeAwareTextView.swift
 M Downward/Features/Editor/EditorKeyboardAccessoryToolbarView.swift
 M Downward/Features/Editor/MarkdownEditorTextViewCoordinator.swift
 M Tests/EditorUndoRedoTests.swift
```

Change size:

```text
596 insertions, 6 deletions
```

The reviewed tree has:

```text
129 Swift files
~40,355 lines of Swift
```

The largest current files are:

```text
1,773 Downward/Features/Editor/MarkdownEditorTextViewCoordinator.swift
1,734 Tests/EditorUndoRedoTests.swift
1,511 Downward/Domain/Workspace/WorkspaceManager.swift
1,351 Downward/App/AppCoordinator.swift
1,063 Downward/Features/Workspace/WorkspaceViewModel.swift
1,022 Downward/Domain/Document/PlainTextDocumentSession.swift
  961 Downward/Features/Editor/EditorViewModel.swift
  668 Downward/Features/Editor/MarkdownStyledTextRenderer.swift
  530 Downward/Features/Editor/LineNumberGutterView.swift
```

## Executive summary

The project is still moving in a good direction architecturally. The main app/domain split is clear, the document/workspace model is stronger than a typical SwiftUI prototype, and the editor stack has useful seams around TextKit, markdown scanning, style application, keyboard geometry, and line-number rendering.

The newest feature work appears to be the editor keyboard formatting accessory and additional line-number/hidden-syntax stabilization. The functionality is valuable, but it increases risk in the already-largest file: `MarkdownEditorTextViewCoordinator.swift`.

The highest-priority concern is not that the new code is obviously broken. It is that the coordinator now owns too many separate behaviours:

- text syncing,
- selection syncing,
- markdown rendering,
- hidden syntax refresh,
- incremental restyling,
- deferred full rerendering,
- viewport resets,
- keyboard geometry,
- undo/redo command dispatch,
- keyboard accessory state,
- formatting menu actions,
- task checkbox tap detection,
- task checkbox mutation,
- line-number invalidation.

That file is now the project’s biggest regression surface.

## Good changes

### 1. Keyboard accessory direction is sensible

The new accessory layout in:

```text
Downward/Features/Editor/EditorKeyboardAccessoryToolbarView.swift
```

adds a left-side formatting button and keeps undo/redo/dismiss controls to the right.

This is a good interaction direction for an iOS markdown editor. The accessory also keeps the background clear and avoids painting private keyboard host views, which is the right choice after the earlier keyboard white-band/background issues.

### 2. Format menu commands are covered by targeted tests

`Tests/EditorUndoRedoTests.swift` now includes tests for:

- accessory toolbar layout,
- format menu presence,
- avoiding menu rebuild during accessory refresh,
- bold wrapping selected text,
- inline format toggling off,
- empty italic insertion,
- task prefix insertion,
- heading prefix insertion,
- link insertion for selected URL.

That is good coverage for basic command output.

### 3. Line-number tests are much stronger than before

`Tests/LineNumberGutterViewTests.swift` has useful regression coverage for:

- large-document drawing not walking the whole file,
- gutter drawing in content coordinates while scrolled,
- blank line before hidden markdown syntax,
- no shared visible Y positions,
- hidden syntax fence delimiters,
- horizontal rules,
- setext underlines,
- scroll-position stability.

This is the correct direction for the bug class you have been fighting.

### 4. The project already has strong architecture docs

`ARCHITECTURE.md`, `PLANS.md`, `CODE_REVIEW.md`, and `RELEASE_QA.md` are useful and mostly aligned. The project now has enough structure that reviews can be turned directly into tracked work.

## P0 — Run a real build and test pass before doing more feature work

### Finding

This environment could not run Xcode, so the new formatter/accessory changes still need local verification.

Because the changed files touch UIKit, TextKit, SwiftUI bridging, keyboard accessory UI, undo state, and tests, this needs a real simulator run before further refactoring.

### Run locally

From the project root:

```bash
xcodebuild -list -project Downward.xcodeproj
```

Then run the full test suite using the simulator name currently available on your machine. Example:

```bash
xcodebuild test \
  -project Downward.xcodeproj \
  -scheme Downward \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

Also run an iPad build/test if you have the simulator available:

```bash
xcodebuild test \
  -project Downward.xcodeproj \
  -scheme Downward \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)'
```

### Done when

- The project builds cleanly.
- The full XCTest suite passes.
- Any failures are added to `PLANS.md`.
- `RELEASE_QA.md` records the exact simulator/device, iOS version, command, and result.

## P1 — Formatting commands need real undo/redo regression coverage

### Finding

The new formatting operations in `MarkdownEditorTextViewCoordinator.swift` mutate the editor using:

```swift
textView.textStorage.replaceCharacters(in: safeReplacementRange, with: replacement)
textView.selectedRange = safeRange(selectionAfter, forTextLength: textView.textStorage.length)
textViewDidChange(textView)
textViewDidChangeSelection(textView)
publishUndoRedoAvailability(for: textView)
updateKeyboardAccessoryState(for: textView)
```

This path is used by:

- bold,
- italic,
- strikethrough,
- inline code,
- task prefix,
- heading prefix,
- link insertion,
- image insertion.

The output tests are good, but they do not prove that these edits are registered correctly with `UITextView`’s undo manager.

This matters because the same accessory also exposes Undo and Redo. Users will expect a toolbar formatting action to be undoable exactly like keyboard typing.

### Risk

Direct `textStorage.replaceCharacters` can work visually while still failing to integrate perfectly with UIKit editing behaviours, depending on how the text view and undo manager observe the mutation.

The current tests use a `TrackingUndoManager` with simulated `canUndo`/`canRedo`, but they do not verify that a formatter action creates a real undo registration.

### Recommended fix

Add tests that perform a formatting command and then request undo/redo through the same path the app uses.

Minimum cases:

- bold selected text, then undo, then redo;
- insert link with empty selection, then undo, then redo;
- prefix current line as task, then undo, then redo;
- prefix multiple selected lines as heading, then undo, then redo;
- toggle an existing inline format off, then undo, then redo.

### Preferred implementation direction

Consider routing formatter edits through `UITextView` editing APIs rather than raw `textStorage` mutation where possible.

A safer long-term shape would be:

```swift
private func replaceSelectionOrRange(
    _ range: NSRange,
    with replacement: String,
    selectionAfter: NSRange,
    in textView: UITextView
)
```

That helper should become the one place that decides:

- how the mutation is applied,
- how undo grouping is registered,
- how selection is restored,
- how `pendingTextMutationContext` is set,
- how markdown restyling is scheduled,
- how accessory state is refreshed.

### Done when

- Formatter commands are proven undoable.
- The accessory Undo/Redo buttons become enabled after formatter edits.
- Undo restores both text and a reasonable selection.
- Redo reapplies both text and a reasonable selection.

## P1 — Extract markdown formatting plans out of the coordinator

### Finding

`MarkdownEditorTextViewCoordinator.swift` is now about 1,773 lines. The new formatter planning structs were added at the bottom of the coordinator file:

- `MarkdownInlineFormatPlan`
- `MarkdownLinePrefixPlan`
- `MarkdownLinkInsertionPlan`
- `MarkdownImageInsertionPlan`
- `isLikelyMarkdownURL`

These are mostly pure string-transformation logic. They do not need to live inside the UIKit bridge file.

### Risk

The coordinator is becoming a grab bag for editor behaviours. Every new editor feature currently has a strong chance of landing there.

That makes regressions more likely because unrelated concepts now share one very large file:

- rendering,
- keyboard accessory state,
- formatting menu construction,
- line restyling,
- task checkbox hit testing,
- viewport reset scheduling.

### Recommended fix

Create a focused file:

```text
Downward/Features/Editor/MarkdownFormattingPlan.swift
```

Move the pure formatter logic there.

Suggested types:

```swift
struct MarkdownInlineFormatPlan
struct MarkdownLinePrefixPlan
struct MarkdownLinkInsertionPlan
struct MarkdownImageInsertionPlan
enum MarkdownFormattingURLClassifier
```

Then add a separate test file:

```text
Tests/MarkdownFormattingPlanTests.swift
```

Move the pure string cases out of `EditorUndoRedoTests.swift`.

Keep `EditorUndoRedoTests.swift` for coordinator integration only.

### Done when

- `MarkdownEditorTextViewCoordinator.swift` loses the pure formatter planning code.
- Pure markdown formatting behaviour has small, fast tests.
- Coordinator tests only verify UIKit integration, selection, undo/redo, and restyling side effects.

## P1 — Preserve CRLF and CR line endings in line-prefix formatting

### Finding

`MarkdownLinePrefixPlan.make(prefix:selectedText:)` currently splits and rejoins selected text using `\n`:

```swift
var lines = selectedText.components(separatedBy: "\n")
...
let stripped = lines.map { ... }.joined(separator: "\n")
...
let prefixed = lines.map { prefix + $0 }.joined(separator: "\n")
```

The rest of the project already acknowledges CRLF and CR line endings. For example, `TextLineMetrics` explicitly handles:

- `\n`,
- `\r\n`,
- `\r`.

### Risk

Applying a task prefix or heading prefix to a CRLF document can silently rewrite selected line endings to LF.

For a real file editor, preserving line endings is important. Users may edit files from Git repos, Windows-authored docs, or synced folders where line ending churn creates noisy diffs.

### Recommended fix

Make line-prefix formatting preserve the original separators.

Instead of `components(separatedBy: "\n")`, parse the selected text into:

```swift
struct MarkdownLineSegment {
    var content: String
    var lineEnding: String
}
```

Then reconstruct each segment with its original `lineEnding`.

### Add tests

Add cases for:

```text
"one\r\ntwo"
"one\rtwo"
"one\ntwo"
"one\r\ntwo\r\n"
```

Each test should verify that the same line-ending style survives after:

- applying a prefix,
- removing the same prefix.

### Done when

- Prefix formatting does not normalize line endings.
- Tests cover LF, CRLF, and CR.

## P1 — Header command should probably replace existing header markers

### Finding

The new Header menu applies a prefix directly:

```swift
self?.applyLineMarkdownPrefix(String(repeating: "#", count: level) + " ")
```

This means applying H3 to an existing H2 line likely produces:

```markdown
### ## Existing heading
```

rather than:

```markdown
### Existing heading
```

### Risk

The command is labelled as a semantic “Header → H1/H2/H3...” action. Users will expect it to set the heading level, not blindly prepend characters.

### Recommended fix

Add a dedicated heading formatter instead of using the generic prefix formatter.

Suggested behaviour:

- If the line starts with `#{1,6} `, replace that marker with the requested heading level.
- If the line is plain text, insert the requested marker.
- If the selected line is empty, insert the marker and place the cursor after the space.
- If multiple lines are selected, apply the same rule line by line.
- Decide whether applying the same heading level again should remove the heading or leave it unchanged.

### Add tests

Examples:

```text
"Title" + H2 -> "## Title"
"# Title" + H3 -> "### Title"
"### Title" + H1 -> "# Title"
"###### Title" + H2 -> "## Title"
```

### Done when

- Header actions behave like “set heading level”.
- The generic line-prefix formatter remains available for tasks/lists.
- Existing heading markers do not accumulate.

## P1 — Task prefix command should avoid stacking task markers

### Finding

The Task menu action uses:

```swift
applyLineMarkdownPrefix("- [ ] ")
```

The generic prefix planner only removes the prefix when all non-empty selected lines already have that exact prefix.

This means applying Task to a line that already starts with another supported task marker can stack prefixes.

Examples that may currently stack:

```markdown
- [x] Done
* [ ] Star task
1. [ ] Ordered task
```

The result may become:

```markdown
- [ ] - [x] Done
- [ ] * [ ] Star task
- [ ] 1. [ ] Ordered task
```

### Risk

The app already supports task checkbox recognition for different list markers. The formatter should probably respect those same markdown task forms.

### Recommended fix

Create a dedicated task-list formatter.

It should recognize and normalize:

```text
- [ ] text
- [x] text
- [/] text
* [ ] text
1. [ ] text
```

Then decide desired behaviour:

- “Task” converts a normal line into `- [ ] line`.
- “Task” on any existing task line toggles/removes task syntax, or normalizes to `- [ ]`.
- Existing completed state may be preserved when changing bullet style.

### Done when

- Task formatting does not stack task markers.
- Tests cover unchecked, checked, partial, bullet, star, and ordered task lines.

## P1 — The line-number gutter fix is safer than before, but still needs real-device QA

### Finding

`LineNumberGutterView` now tries to keep rows monotonic when hidden syntax produces odd TextKit fragments:

```swift
return syntheticFragmentRect(after: previousFragmentRect, fallback: fragmentRect)
```

This is intended to prevent overlapping numbers when hidden syntax-only lines report neighboring TextKit fragments.

The tests are good and specifically cover several hidden-syntax cases.

### Risk

The synthetic fallback solves the “same Y position” class of bugs, but it can also create visual drift if TextKit’s real line fragment geometry differs from the synthetic height.

That matters for the exact area that recently caused trouble: hidden syntax, blank lines, markdown syntax markers, and scrolling.

### Recommended manual QA

Test the following combinations on real iPhone and iPad:

- line numbers on/off,
- hidden syntax on/off,
- larger heading text on/off,
- top of document,
- middle of long document,
- after scrolling,
- after rotating,
- after editing near a hidden markdown marker.

Use files containing:

```markdown
# Heading


**Bold line**
- [ ] task

---

## Next heading
```

And:

````markdown
Before

```swift
let x = 1
```

After
````

### Done when

- No numbers overlap.
- Numbers do not drift while scrolling.
- Blank lines receive stable positions.
- Hidden syntax-only rows do not create “extra” scrolling gutter behaviour.
- Current line highlight tracks the real cursor line.

## P1 — Avoid using the gutter as an independent scrolling surface

### Finding

The current gutter is a subview of the text view with:

```swift
frame = CGRect(x: 0, y: 0, width: gutterWidth, height: contentHeight)
```

The draw logic uses content coordinates and the tests verify that line-number content positions do not change when scrolled.

This is the right conceptual model: the gutter should be content-aligned, not independently scrolling.

### Risk

Any future change that makes the gutter frame follow `contentOffset`, or applies scroll transforms to the gutter itself, can reintroduce the “scrolling line numbers” issue.

### Recommended protection

Add a comment directly above `LineNumberGutterView.updateGutter()` explaining the invariant:

```swift
// The gutter is drawn in text-view content coordinates.
// Do not offset the gutter by contentOffset. Scrolling is handled by the
// text view clipping the content-aligned gutter, not by moving number rows.
```

The current test `testLineNumberContentPositionsDoNotChangeWhenScrolled` is a good guard. Keep it.

### Done when

- The invariant is documented in code.
- Tests continue to prove stable content coordinates.

## P2 — Formatting menu construction can move out of the coordinator

### Finding

`makeFormattingMenu()` lives inside `MarkdownEditorTextViewCoordinator`.

It is UIKit-specific, so it does belong near the editor bridge, but it does not need to be inside the main coordinator type.

### Recommended fix

Create a small helper:

```swift
struct MarkdownFormattingMenuFactory {
    func makeMenu(actions: MarkdownFormattingActions) -> UIMenu
}
```

Or:

```swift
final class MarkdownKeyboardAccessoryController
```

The coordinator would provide closures:

```swift
onBold
onItalic
onCode
onTask
onHeader(level:)
onLink
onImage
```

### Benefit

This keeps the coordinator focused on synchronising `UITextView` with SwiftUI and the document model.

### Done when

- Menu construction no longer adds visual/action noise to the coordinator.
- Tests still verify the accessory has the expected controls.

## P2 — `KeyboardAccessoryToolbarView.updateFormatMenu(_:)` is currently unused

### Finding

`KeyboardAccessoryToolbarView` exposes:

```swift
func updateFormatMenu(_ formatMenu: UIMenu) {
    formatButton.menu = formatMenu
}
```

But `configureKeyboardAccessory` intentionally does not rebuild the format menu after creation, and a test verifies that the menu is not rebuilt.

### Risk

This is not a bug, but the API is ambiguous. It suggests the menu should be updated, while current behaviour says the opposite.

### Recommended fix

Either:

1. remove `updateFormatMenu(_:)` until it is needed, or
2. add a comment explaining when it should be used.

### Done when

- The toolbar API reflects actual intended behaviour.

## P2 — Fixed-space accessory item likely needs an explicit width or removal

### Finding

The toolbar items for compact/iPhone mode are:

```swift
[formatButton, .flexibleSpace(), undoButton, redoButton, UIBarButtonItem(systemItem: .fixedSpace), dismissButton]
```

A fixed-space item without an explicit width may not provide meaningful spacing.

### Recommended fix

Either set a width:

```swift
let spacer = UIBarButtonItem(systemItem: .fixedSpace)
spacer.width = 8
```

Or remove the fixed-space item if the default button spacing is acceptable.

### Done when

- Toolbar spacing is intentional and verified on iPhone and iPad.

## P2 — Link and image insertion should escape problematic selected text

### Finding

The link/image plans use the selected text directly:

```swift
replacement: "[\(selectedText)](\(urlPlaceholder))"
replacement: "![\(selectedText)](\(urlPlaceholder))"
```

### Risk

Selected text containing `]`, `[`, `)`, or newline characters can produce malformed markdown.

Examples:

```text
hello [world]
image)name
multi
line
```

### Recommended fix

Add a small escaping/sanitising layer for label/alt text.

At minimum:

- replace newlines with spaces for inline link/image labels,
- escape `[` and `]`,
- consider handling `)` in URLs if selected URL insertion supports arbitrary selected text.

### Done when

- Link/image insertion produces valid markdown for common punctuation.
- Tests cover selected text containing brackets and newlines.

## P2 — `isLikelyMarkdownURL` accepts any URL scheme

### Finding

The URL classifier currently returns true for any string where `URL(string:)` has a non-nil scheme:

```swift
if let url = URL(string: text), url.scheme != nil {
    return true
}
```

### Risk

For markdown editing this is not immediately dangerous, but it can classify odd strings as URLs.

Examples:

```text
foo:bar
javascript:alert(1)
file:///private/tmp/example
```

### Recommended fix

Decide what the editor should treat as a URL for insertion purposes.

A practical initial allow-list:

```text
http
https
mailto
```

Possibly also:

```text
tel
sms
```

### Done when

- URL classification matches product expectations.
- Tests cover normal URLs, `www.`, email links, and unsupported schemes.

## P2 — The project should keep `CODE_REVIEW.md` as an index and put active tasks in `PLANS.md`

### Finding

The existing `CODE_REVIEW.md` says active review findings should live in `PLANS.md`.

This new file is a point-in-time review. The actionable items should be copied into `PLANS.md` as checklists if they are accepted.

### Recommended action

Add these to `PLANS.md`:

```markdown
## P1 — Verify formatter undo/redo integration
## P1 — Extract markdown formatting plans
## P1 — Preserve CRLF in line-prefix formatting
## P1 — Improve semantic heading/task formatting
## P1 — Real-device QA for line numbers + hidden syntax
```

### Done when

- `CODE_REVIEW_2026-04-28.md` stays as review evidence.
- `PLANS.md` contains only the active work you intend to do next.

## Suggested next Codex batch

Use this prompt next:

```text
You are working in the Downward iOS project.

Read:
- CODE_REVIEW_2026-04-28.md
- PLANS.md
- ARCHITECTURE.md
- Downward/Features/Editor/MarkdownEditorTextViewCoordinator.swift
- Downward/Features/Editor/EditorKeyboardAccessoryToolbarView.swift
- Tests/EditorUndoRedoTests.swift
- Tests/LineNumberGutterViewTests.swift

Do one focused stabilization batch only.

Goals:
1. Add regression tests proving the new keyboard accessory markdown formatting commands participate correctly in undo/redo.
2. Extract the pure markdown formatting planning logic out of MarkdownEditorTextViewCoordinator.swift into a new focused file.
3. Add pure tests for the extracted formatting plans.
4. Preserve existing behaviour unless a test exposes a clear bug.
5. Do not refactor unrelated editor rendering, autosave, workspace, or settings code.

Specific requirements:
- Keep MarkdownEditorTextViewCoordinator responsible for UIKit coordination only.
- Move MarkdownInlineFormatPlan, MarkdownLinePrefixPlan, MarkdownLinkInsertionPlan, MarkdownImageInsertionPlan, and URL classification out of the coordinator file.
- Add tests for bold, italic empty insertion, link insertion, image insertion, task prefix, heading prefix, and toggling inline formatting off.
- Add undo/redo integration tests for at least bold, link insertion, and line prefix formatting.
- Keep line number behaviour unchanged in this batch.
- Update PLANS.md with completed checklist items and any new findings.
- Run the full test suite if Xcode is available and record results in RELEASE_QA.md.

Return:
- summary of changed files,
- tests run,
- any failures,
- remaining risks.
```

## Recommended next order of work

1. Run local build/tests.
2. Add formatter undo/redo tests.
3. Extract formatter planning.
4. Preserve CRLF in line-prefix formatting.
5. Improve heading/task semantic formatting.
6. Do real-device QA for line numbers plus hidden syntax.
7. Only then add more editor features.

## Final assessment

The project is in a strong state overall, but the editor coordinator is now the pressure point.

The formatting toolbar is a good feature, and the line-number tests show real progress. The next best move is not another feature batch. It is a stabilization batch that proves formatting undo/redo, extracts pure formatting logic, and protects line-number behaviour from another round of scroll/overlap regressions.