# CODE_REVIEW.md — Release Readiness Review

## Scope

Reviewed the uploaded `Downward copy.zip` archive on 2026-04-28.

This is a static source review. I could inspect the code, tests, project settings, and documentation, but I could not run Xcode, the iOS simulator, UIKit/TextKit runtime tests, signing, archiving, or App Store validation from this Linux environment. Treat this file as the current release review checklist, then record the local build/test/manual-device evidence in `RELEASE_QA.md`.

Reviewed source shape:

```text
134 Swift files
43,183 total Swift lines across Downward/ and Tests/
```

Largest current files:

```text
2,353 Tests/EditorUndoRedoTests.swift
1,889 Downward/Features/Editor/MarkdownEditorTextViewCoordinator.swift
1,563 Downward/Domain/Workspace/WorkspaceManager.swift
1,471 Tests/DocumentManagerTests.swift
1,467 Tests/WorkspaceManagerRestoreTests.swift
1,363 Downward/App/AppCoordinator.swift
1,316 Tests/EditorAutosaveTests.swift
1,191 Tests/MarkdownWorkspaceAppMutationFlowTests.swift
1,124 Tests/MarkdownWorkspaceAppTrustedOpenAndRecentTests.swift
1,063 Downward/Features/Workspace/WorkspaceViewModel.swift
1,060 Tests/MarkdownStyledTextRendererTests.swift
1,022 Downward/Domain/Document/PlainTextDocumentSession.swift
  993 Downward/Features/Editor/EditorViewModel.swift
  792 Downward/Features/Editor/MarkdownFormattingPlan.swift
  694 Downward/Features/Editor/MarkdownStyledTextRenderer.swift
  587 Downward/Features/Editor/LineNumberGutterView.swift
```

## Executive summary

Downward is in a much stronger state than a prototype. The app has clear domain/features/platform separation, broad unit and app-hosted test coverage, a real `UITextView` editor boundary, explicit workspace/session/navigation policies, and a thoughtful security-scoped Files workflow.

The main release risk is now concentrated in runtime behaviours that static tests cannot fully prove:

1. real-device TextKit/editor behaviour with very large files,
2. Files provider access, restore, and reconnect flows,
3. autosave/conflict handling during app lifecycle changes,
4. keyboard accessory and status-bar chrome presentation on real iPhone/iPad hardware,
5. visible placeholder monetisation/legal surfaces,
6. final App Store project configuration and archive validation.

The recent line-number gutter failure appears to have been fixed in the right way. `LineNumberGutterView` now keeps the gutter viewport-sized and converts TextKit document coordinates into local viewport coordinates for drawing. Keep that invariant. Do not reintroduce a document-height gutter layer.

The recent markdown formatter work also moved in the right direction. Pure planning now lives in `MarkdownFormattingPlan.swift`, with tests for line endings, heading/task formatting, link/image insertion, and URL classification. The coordinator still remains large, but the most urgent extraction work is done. Do not start a large coordinator rewrite before release unless a release blocker requires it.

## Things that are already in good shape

- [x] The editor is still backed by UIKit/TextKit, which is appropriate for large editable Markdown documents.
- [x] The line-number gutter is viewport-sized instead of content-height-sized.
- [x] The line-number tests cover large documents, hidden syntax, blank lines, setext headings, code fences, horizontal rules, and scroll-local drawing.
- [x] Markdown formatter planning has been extracted from the coordinator into pure testable plan types.
- [x] Line-prefix formatting preserves LF, CRLF, and CR line endings in the covered cases.
- [x] Heading and task-list formatting now use semantic plan logic instead of only raw prefix toggling.
- [x] URL creation for newly inserted links/images has a scheme allow-list and rejects dangerous schemes such as `javascript:` and `file:` in the covered cases.
- [x] Workspace-relative identity, recents, restore, stale-item cleanup, and route/session policy have substantial test coverage.
- [x] The project has no obvious `TODO`/`FIXME` debt markers in source.
- [x] `fatalError` usage is limited to test helpers, invalid hard-coded regex construction, and a programmatic UIKit view `init(coder:)` guard.
- [x] `try!` usage appears limited to tests.

---

# P0 — Must fix or verify before release

## 1. Run a final clean Xcode build, test, archive, and install pass

Static review cannot replace this. Make this the first release gate after applying any final documentation cleanup.

- [ ] Delete DerivedData or use a clean clone/archive of the project.
- [x] Confirm the expected scheme appears with `xcodebuild -list -project Downward.xcodeproj`.
- [ ] Build Debug for an iPhone simulator.
- [ ] Build Debug for an iPad simulator.
- [ ] Run the full XCTest suite on an iPhone simulator.
- [ ] Run the full XCTest suite on an iPad simulator.
- [x] Run a Release configuration build.
- [ ] Archive the app locally.
- [ ] Validate the archive in Xcode Organizer.
- [ ] Install the archive/TestFlight build on a real iPhone.
- [ ] Install the archive/TestFlight build on a real iPad if iPad support is intended for 1.0.
- [ ] Record command lines, devices, OS versions, pass/fail counts, and archive validation results in `RELEASE_QA.md`.

Suggested command pattern:

```bash
xcodebuild -list -project Downward.xcodeproj

xcodebuild test \
  -project Downward.xcodeproj \
  -scheme Downward \
  -destination 'platform=iOS Simulator,name=<iPhone simulator name>'

xcodebuild test \
  -project Downward.xcodeproj \
  -scheme Downward \
  -destination 'platform=iOS Simulator,name=<iPad simulator name>'

xcodebuild build \
  -project Downward.xcodeproj \
  -scheme Downward \
  -configuration Release \
  -destination 'generic/platform=iOS'
```

## 2. Verify deployment target and project settings for the intended App Store release

Current project settings were aligned on 2026-04-28 so the project, app target, and test target all use iOS `26.0`.

- [x] Confirm the intended minimum iOS version for 1.0.
- [x] Align project, app target, and test target deployment targets where appropriate.
- [x] Confirm Swift language mode `6.0` is intentional.
- [x] Confirm bundle identifier `com.secondvictor.Downward` is final.
- [x] Confirm marketing version `1.0` and build number `1` are correct for the first archive.
- [x] Confirm supported orientations are intentional: iPhone portrait only; iPad all orientations.
- [ ] Confirm signing team and provisioning profile are correct for release.
- [x] Record the final project settings in `RELEASE_QA.md`.
  - The generic Release build used the current automatic Apple Development signing profile; archive/App Store provisioning still needs final validation.

## 3. Decide what to do with visible placeholder monetisation and legal surfaces

The Settings UI now gates unfinished placeholder-like surfaces through `SettingsReleaseConfiguration.current`:

- `TipsSettingsPage` remains in source for later StoreKit work, but the Settings home entry and destination are hidden for 1.0 while purchases are disabled.
- `InformationSettingsPage` only shows “Rate the App” when an App Store review URL is configured.
- `AboutSettingsPage` only shows Privacy Policy / Terms & Conditions rows when URLs are configured.
- `SettingsPlaceholderFeature` still marks `.tipsPurchases`, `.rateTheApp`, and `.legalLinks` as not implemented, and tests cover that the current release configuration hides them.

For a release build, visible non-functional monetisation/legal rows can confuse users and may create review friction.

- [x] Either hide the Tips page for 1.0 or implement real StoreKit products and receipt-safe purchase handling.
- [x] Either hide “Rate the App” or wire it to the App Store review flow only when an App Store ID is available.
- [x] Either hide Privacy Policy / Terms rows or configure final URLs.
- [ ] Confirm App Store metadata includes any required privacy/legal links.
- [ ] Add a release QA case that visits Settings > Tips and Settings > Information/About in the release build.
- [x] Update tests so placeholder expectations match the intended release behaviour.
  - An unchecked manual QA case was added to `RELEASE_QA.md`; the actual release-build Settings walkthrough still needs to be performed.

## 4. Perform real-device Files provider QA

The app’s value depends on security-scoped Files access. Simulator and unit tests are not enough here.

- [ ] Fresh install starts with no selected workspace and no stale route state.
- [ ] Select a folder from “On My iPhone/iPad”.
- [ ] Select a folder from iCloud Drive.
- [ ] Select a folder from a third-party Files provider if one is available.
- [ ] Relaunch and confirm workspace restore succeeds without another picker prompt.
- [ ] Revoke/move/remove the folder and confirm reconnect UI appears.
- [ ] Reconnect to the same workspace and confirm recents/routes recover.
- [ ] Open a recently used file by workspace-relative path.
- [ ] Rename a file and confirm editor title, browser, recents, and route state update.
- [ ] Move a file and confirm editor title, browser, recents, and route state update.
- [ ] Delete the active file and confirm editor/session state clears safely.
- [ ] Create a new file and folder from the workspace UI.
- [ ] Confirm hidden files/packages/symlinks behave according to the documented workspace rules.
- [ ] Record provider names, device models, OS versions, and failures in `RELEASE_QA.md`.

## 5. Perform real-device editor lifecycle QA

The most important user-trust risk is losing edits or showing stale text.

- [ ] Open a Markdown file, type quickly for at least 30 seconds, and verify autosave.
- [ ] Background the app immediately after typing and verify the file on disk after relaunch.
- [ ] Switch documents rapidly while typing and verify the correct file receives each save.
- [ ] Edit the same file externally and verify conflict detection/resolution.
- [ ] Use “keep mine” conflict resolution and verify saved disk contents.
- [ ] Use “use disk version” conflict resolution and verify editor contents.
- [ ] Put the app through lock/unlock, app switcher, and low-memory-style relaunch if possible.
- [ ] Record each lifecycle result in `RELEASE_QA.md`.

## 6. Regression-test very large Markdown files on device

The black/missing gutter bug was a Core Animation/TextKit-style runtime failure. Keep the tests, but also prove the fix on actual hardware.

- [ ] Open a 1,000+ line Markdown file with line numbers enabled.
- [ ] Open a 10,000+ line Markdown file with line numbers enabled.
- [ ] Scroll near the bottom, then quickly return to the top.
- [ ] Confirm the gutter never becomes a black bar.
- [ ] Confirm line numbers never disappear after returning to the top.
- [ ] Confirm hidden syntax does not overlap line numbers after blank lines.
- [ ] Toggle line numbers off/on after deep scrolling.
- [ ] Toggle larger heading text and confirm line numbers are disabled as intended.
- [ ] Repeat on at least one real iPhone and one iPad if iPad support is shipping.
- [ ] Record performance notes and screenshots in `RELEASE_QA.md`.

## 7. Verify keyboard accessory, selection, undo/redo, and formatting commands on device

The tests are strong here, but accessory input views and TextKit selection can behave differently on hardware.

- [ ] Keyboard accessory appears with no white flash or incorrect background.
- [ ] Accessory remains tinted correctly after theme changes.
- [ ] Undo/redo buttons enable and disable correctly after typing.
- [ ] Undo/redo buttons enable and disable correctly after formatter commands.
- [ ] Bold, italic, strikethrough, inline code, heading, task, link, image, quote, code block, unordered list, and ordered list commands behave as expected.
- [ ] Selection is preserved or moved intentionally after each command.
- [ ] Repeated undo/redo does not corrupt hidden syntax attributes.
- [ ] Tap-to-toggle task checkboxes can be undone and redone.
- [ ] Hardware keyboard users can still edit naturally.

## 8. Verify theme/chrome readability on real devices

Theme-aware chrome is a release-quality feature only if the system UI remains readable.

- [ ] Test a dark editor theme while the app appearance is light.
- [ ] Test a light editor theme while the app appearance is dark.
- [ ] Test adaptive/system theme in light and dark mode.
- [ ] Test “match system chrome to theme” enabled and disabled.
- [ ] Confirm status bar readability on iPhone.
- [ ] Confirm navigation/title readability on iPhone.
- [ ] Confirm status/sidebar/detail readability on iPad.
- [ ] Confirm the keyboard accessory follows the expected editor theme.

## 9. Disable or intentionally gate release logging

`Downward/Infrastructure/Logging/DebugLogger.swift` logs with a `[Downward]` prefix only when `DEBUG` is defined. Release builds are intentionally no-op to avoid console noise and accidental path/provider diagnostics.

- [x] Decide whether `DebugLogger` should be no-op outside DEBUG.
- [ ] If logging remains in Release, audit every message for privacy and usefulness.
  - Not applicable for the current release decision because Release logging is no-op.
- [x] Add a tiny test or code review note proving the release behaviour.
- [x] Record the decision in `ARCHITECTURE.md` or `RELEASE_QA.md`.

Suggested shape:

```swift
struct DebugLogger: Sendable {
    nonisolated func log(_ message: String) {
#if DEBUG
        print("[Downward] \(message)")
#endif
    }
}
```

## 10. Confirm relative Markdown link behaviour is intentional

Downward 1.0 supports tapping relative Markdown links to workspace files through a separate internal resolver. External URL handling remains scheme-allow-listed, while raw relative destinations are routed to the editor view model for workspace-relative resolution.

- [x] Decide whether Downward 1.0 should support tapping relative links such as `[Note](notes.md)`, `[Section](#heading)`, or `[Doc](../folder/doc.md)`.
- [ ] If relative links are intentionally unsupported, keep the current behaviour and add a user-facing or architecture note.
  - Not applicable for 1.0 because relative links are now supported for safe workspace-local documents.
- [x] If relative links should open workspace files, implement a separate internal-link resolver instead of relaxing the external URL allow-list.
- [x] Add renderer/app tests for the selected behaviour.

---

# P1 — Should fix soon, but not at the cost of destabilising release

## 1. Keep shrinking `MarkdownEditorTextViewCoordinator.swift`

The coordinator is still the largest production file at 1,889 lines. Recent extraction helped, but the file still owns too much behaviour.

Recommended extraction order after the release gate is green:

- [ ] Move keyboard accessory/menu construction into a small `EditorFormattingAccessoryController` or equivalent.
- [ ] Move link tap hit-testing/opening into a small helper.
- [ ] Move task checkbox tap hit-testing/toggling into a small helper.
- [ ] Move deferred render scheduling/viewport reset policy into a small helper.
- [ ] Keep the coordinator as the place that applies plans to `UITextView`, syncs SwiftUI bindings, and handles TextKit delegate callbacks.
- [ ] After each extraction, run focused editor, undo/redo, renderer, and gutter tests.

Do not perform this as a giant rewrite immediately before release.

## 2. Add a measured large-document performance baseline

The renderer and coordinator include incremental/deferred work, but there should be a repeatable performance baseline before further optimisation.

- [ ] Define standard files: small, 1k lines, 10k lines, and a stress file with headings/tasks/code/link blocks.
- [ ] Record first render time on simulator and one real device.
- [ ] Record typing latency in the middle and near the bottom of large documents.
- [ ] Record deep scroll memory behaviour with line numbers on/off.
- [ ] Keep the existing `MarkdownRendererPerformanceTests`, but do not rely on them as the only signal.
- [ ] Add results to `RELEASE_QA.md`.

## 3. Harden Markdown link/image parsing edge cases

The current regex-style parsed link destination handling is acceptable for a small Markdown editor, but it will not cover every CommonMark edge case.

- [ ] Add tests for destinations containing encoded parentheses.
- [ ] Add tests for titles/labels containing escaped brackets.
- [ ] Add tests for empty destinations.
- [ ] Add tests for whitespace around destinations if supported.
- [ ] Decide whether unsupported Markdown link shapes should remain plain text or partially styled.

## 4. Clarify Theme export UX

`ThemeEditorSettingsPage.exportTheme()` can build a theme for a new draft because it uses a generated UUID when `editing == nil`, but the export button is only visible when editing an existing theme.

- [ ] Decide whether new unsaved themes should be exportable.
- [ ] If yes, show the export action for new drafts and test it.
- [ ] If no, rename UI/copy so users do not expect “Export Draft” before saving.
- [ ] Add release QA coverage for import/export/share flows.

## 5. Accessibility pass

The project has some accessibility labels/hints, but release should include a full manual pass.

- [ ] Navigate the full app with VoiceOver.
- [ ] Verify Settings rows announce title and current value.
- [ ] Verify workspace rows announce file/folder state clearly.
- [ ] Verify editor accessory buttons have useful labels and hints.
- [ ] Verify task checkboxes are understandable to VoiceOver users.
- [ ] Verify Dynamic Type in Settings, workspace browser, and conflict UI.
- [ ] Verify editor font scaling behaviour is intentional.
- [ ] Verify theme contrast for built-in themes.

## 6. Case-only rename coverage on real case-insensitive storage

There are tests for case-only file/folder rename, but they skip on case-sensitive volumes. That is reasonable in CI, but a release QA pass should cover the normal iOS/APFS user case.

- [ ] Rename `Draft.md` to `draft.md` on device.
- [ ] Rename `Folder` to `folder` on device.
- [ ] Verify browser, recents, active editor route, and underlying file path update correctly.
- [ ] Record the result in `RELEASE_QA.md`.

## 7. Split large domain/app files once release risk drops

The largest domain/app files are stable enough for release if tests stay green, but they are long-term maintenance risks.

- [ ] Split `WorkspaceManager` into selection/restore, enumeration/snapshot, mutation, and identity/path-resolution collaborators.
- [ ] Split `AppCoordinator` into launch/restore, document loading, mutation orchestration, and recent-file handling collaborators.
- [ ] Split `WorkspaceViewModel` presentation state from mutation command routing.
- [ ] Keep `WorkspaceMutationPolicy`, `WorkspaceNavigationPolicy`, and `WorkspaceSessionPolicy` as pure policy seams.

---

# P2 — Post-release hardening and quality improvements

- [ ] Add SwiftFormat or SwiftLint only if the rule set is small and non-disruptive.
- [ ] Add a String Catalog/localisation plan if non-English support is planned.
- [ ] Add UI/snapshot tests for Settings and main navigation if the project starts accepting broader UI changes.
- [ ] Add crash/error reporting intentionally, or document why the app is privacy-first and local-only with no telemetry.
- [ ] Add an in-app sample document or onboarding only if it does not complicate Files workspace ownership.
- [ ] Document unsupported Markdown features so users understand the editor’s scope.
- [ ] Consider workspace search performance profiling for very large folders.
- [ ] Consider internal relative Markdown link navigation after the external-link policy is settled.

---

# File-level notes

## `Downward/Features/Editor/LineNumberGutterView.swift`

Current status: good direction.

The gutter now follows the viewport instead of the full document height. Preserve this invariant:

```text
gutter height == visible viewport height
gutter y == textView.contentOffset.y
line positions == TextKit document coordinates converted into gutter-local coordinates
```

Do not change the gutter back to `height: contentHeight`; that is the failure mode that produced black/missing gutter tiles after deep scrolling.

## `Downward/Features/Editor/MarkdownEditorTextViewCoordinator.swift`

Current status: release-acceptable if tests and manual QA pass, but still the highest-risk production file.

Main risks:

- TextKit delegate callbacks,
- incremental/deferred rendering,
- hidden syntax invalidation,
- line-number invalidation,
- formatting application,
- task checkbox taps,
- link taps,
- keyboard accessory state,
- undo/redo availability,
- SwiftUI binding sync.

Keep fixes small until after release. Prefer pure helper extraction with tests over behavioural rewrites.

## `Downward/Features/Editor/MarkdownFormattingPlan.swift`

Current status: good improvement.

This file is now the right home for pure formatting transformations. Continue moving formatter edge-case behaviour here rather than into the coordinator.

Recommended additional tests:

- nested/escaped brackets in labels,
- parentheses in link destinations,
- empty selected text for every block/inline formatter,
- selection spanning partial first/last lines,
- mixed line endings in one selection,
- idempotence of applying/removing prefixes repeatedly.

## `Downward/Features/Editor/MarkdownStyledTextRenderer.swift` and `MarkdownSyntaxStyleApplicator.swift`

Current status: functional, but keep performance under observation.

The renderer is central to hidden syntax and visual markdown styling. Avoid adding more parser features until performance and correctness are proven on large documents. For any future Markdown parsing complexity, prefer scanner/state-machine helpers over growing regex logic in place.

## `Downward/Domain/Document/PlainTextDocumentSession.swift`

Current status: strong concept, must be proven on real providers.

The file presenter / fallback polling / local save-notification approach is appropriate, but the release risk is provider behaviour. Real iCloud and third-party Files provider QA is mandatory.

## `Downward/Domain/Workspace/WorkspaceManager.swift`

Current status: well-tested but large.

Workspace operations have good policy/test coverage. Post-release, split by responsibility to reduce mutation/regression risk.

## `Downward/App/AppCoordinator.swift`

Current status: well-covered but large.

The coordinator is doing a lot of orchestration. Keep it stable for release; split after release behind existing tests.

## `Downward/Features/Settings/*`

Current status: visually useful, but release gating needed.

Settings now hides placeholder purchase/review/legal surfaces for the 1.0 release unless their backing StoreKit, App Store review URL, or legal URLs are configured.

## `Downward/Infrastructure/Logging/DebugLogger.swift`

Current status: useful for development.

Release logging is gated behind `#if DEBUG`; Release builds are no-op.

## `Downward.xcodeproj/project.pbxproj`

Current status: likely valid for the current development environment, but verify before archive.

Review deployment targets, signing, version/build number, supported orientations, and release configuration.

---

# Release sign-off checklist

Use this as the final “ready to submit” list.

- [ ] `PLANS.md` contains only active release work and no stale completed backlog.
- [ ] This `CODE_REVIEW.md` is the only active code review checklist.
- [ ] Old dated code-review files have either been deleted or explicitly archived outside the active root docs.
- [x] `RELEASE_QA.md` contains current automated test evidence for this exact source state.
- [ ] `RELEASE_QA.md` contains current real-device manual QA evidence.
- [x] P0 settings/legal/monetisation placeholders are resolved.
- [x] Release logging decision is made.
- [ ] Deployment target and archive validation are complete.
- [ ] Large-document line-number regression is manually verified on device.
- [ ] Files provider flows are manually verified on device.
- [ ] Autosave/conflict/lifecycle flows are manually verified on device.
- [ ] Keyboard accessory/formatter/undo/redo flows are manually verified on device.
- [ ] Theme/chrome readability is manually verified on device.
- [ ] No new feature work is started until every P0 item is either complete or intentionally deferred with a release decision.
