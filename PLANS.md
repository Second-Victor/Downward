# PLANS.md

## Purpose

This is the active release plan for **Downward**.

Keep this file focused on what still needs to happen before release. Completed implementation detail belongs in git history, release notes, or `RELEASE_QA.md`, not in this plan.

Related docs:

- `AGENTS.md` — product invariants, engineering guardrails, and contribution rules.
- `ARCHITECTURE.md` — current app shape, ownership boundaries, and known scale limits.
- `CODE_REVIEW.md` — current release-readiness code review and checkable repair list.
- `RELEASE_QA.md` — build, test, simulator, real-device, Files-provider, and archive validation log.

## Current release stance

Downward is close to release. The remaining work should be **stabilisation, verification, and release cleanup**, not new feature expansion.

The highest-risk areas are:

1. real-device Files provider access and workspace restore,
2. autosave/conflict/lifecycle correctness,
3. large-document editor performance and line-number rendering,
4. keyboard accessory and formatter/undo/redo behaviour,
5. theme/status-bar/readability behaviour,
6. placeholder Settings surfaces for tips, ratings, privacy, and terms,
7. final App Store project/archive configuration.

The previous completed backlog has been compressed out of this file. The current source already includes the major stabilisation work around formatter extraction, CRLF preservation, semantic heading/task formatting, line-number viewport rendering, theme-aware chrome, and broad XCTest coverage. Keep the active plan short and current.

## Working rules

- Do not add feature work above the release gates unless it fixes a P0 release blocker.
- Every new bug found during QA should be added here as a checked-list item with a clear owner/exit condition.
- Every completed release verification item should be recorded in `RELEASE_QA.md` with device, OS, command, and result details.
- Keep `CODE_REVIEW.md` as the detailed repair checklist. Keep this file as the release plan.
- Remove or compress completed items during each release pass.

---

# P0 — Release gates

## 1. Final clean build, test, and archive evidence

- [ ] Clean DerivedData or use a clean clone/archive.
- [x] Confirm `Downward` scheme is available with `xcodebuild -list -project Downward.xcodeproj`.
- [ ] Build Debug on an iPhone simulator.
- [ ] Build Debug on an iPad simulator.
- [ ] Run the full XCTest suite on an iPhone simulator.
- [ ] Run the full XCTest suite on an iPad simulator.
- [x] Build Release for generic iOS.
- [ ] Archive the app.
- [ ] Validate the archive in Xcode Organizer.
- [ ] Install the archive/TestFlight build on a real iPhone.
- [ ] Install the archive/TestFlight build on a real iPad if iPad support is shipping.
- [ ] Record all commands, device names, OS versions, result counts, and failures in `RELEASE_QA.md`.

## 2. Project and App Store configuration

- [x] Confirm the intended minimum iOS version for 1.0.
- [x] Align project/app/test deployment targets if needed.
- [x] Confirm Swift language mode is intentional.
- [ ] Confirm bundle identifier, signing team, provisioning, marketing version, and build number.
  - Source values and the generic Release build signing profile were recorded on 2026-04-28; final App Store/archive provisioning still needs validation.
- [x] Confirm iPhone/iPad orientation support is intentional.
- [ ] Confirm app icon, display name, and bundle metadata are final.
- [ ] Confirm privacy metadata and App Store review notes are ready.

## 3. Resolve visible placeholder Settings surfaces

- [x] Decide whether Tips ships in 1.0.
- [ ] If Tips ships, implement real StoreKit products and purchase handling.
- [x] If Tips does not ship, hide the Tips page and remove visible prices from release builds.
- [x] Decide whether “Rate the App” ships in 1.0.
- [ ] If rating ships, wire it to the App Store review flow with a final App Store ID.
- [x] If rating does not ship, hide the row.
- [x] Configure final Privacy Policy and Terms URLs, or hide those rows.
- [x] Update tests so `SettingsPlaceholderFeature` matches the release decision.
- [ ] Record the final Settings walkthrough in `RELEASE_QA.md`.
  - Release Settings automated coverage and an unchecked manual walkthrough case were added on 2026-04-28; the actual release-build walkthrough still needs to be performed.

## 4. Real-device Files provider QA

- [ ] Fresh install with no workspace selected.
- [ ] Pick a local Files workspace.
- [ ] Pick an iCloud Drive workspace.
- [ ] Pick a third-party Files provider workspace if available.
- [ ] Relaunch and verify workspace restore.
- [ ] Remove or invalidate access and verify reconnect flow.
- [ ] Reconnect and verify recents/routes recover.
- [ ] Create, rename, move, and delete files/folders.
- [ ] Verify browser, editor, recents, and navigation state after each mutation.
- [ ] Record provider/device/OS/results in `RELEASE_QA.md`.

## 5. Real-device editor data-safety QA

- [ ] Type rapidly and verify autosave to disk.
- [ ] Background immediately after typing and verify no data loss.
- [ ] Relaunch and verify active document restore.
- [ ] Switch documents while typing and verify each file’s content.
- [ ] Trigger an external edit and verify conflict detection.
- [ ] Test both conflict resolution paths.
- [ ] Test app lock/unlock and app switcher lifecycle.
- [ ] Record results in `RELEASE_QA.md`.

## 6. Large-document editor and line-number QA

- [ ] Test at least one 1,000+ line Markdown document on device.
- [ ] Test at least one 10,000+ line Markdown document on device.
- [ ] With line numbers enabled, scroll near the bottom and back to the top repeatedly.
- [ ] Verify the gutter never turns black or loses numbers.
- [ ] Verify hidden syntax does not overlap line numbers after blank lines.
- [ ] Toggle line numbers off/on after deep scrolling.
- [ ] Verify larger heading text disables line numbers as intended.
- [ ] Record screenshots/performance notes in `RELEASE_QA.md`.

## 7. Keyboard accessory, formatter, undo/redo QA

- [ ] Keyboard accessory appears without a white flash or incorrect background.
- [ ] Accessory tint follows theme changes.
- [ ] Undo/redo state updates after typing.
- [ ] Undo/redo state updates after formatter commands.
- [ ] Formatter commands work for bold, italic, strikethrough, inline code, heading, quote, code block, ordered list, unordered list, task, link, and image.
- [ ] Task checkbox tap-to-toggle works and participates in undo/redo.
- [ ] Selection/cursor placement feels correct after each command.
- [ ] Hardware keyboard editing still works naturally.
- [ ] Record results in `RELEASE_QA.md`.

## 8. Theme and chrome QA

- [ ] Test light app appearance with dark editor theme.
- [ ] Test dark app appearance with light editor theme.
- [ ] Test adaptive/system editor theme in light and dark mode.
- [ ] Test “match system chrome to theme” enabled and disabled.
- [ ] Verify status bar, navigation titles, sheets, keyboard accessory, and editor overlay are readable.
- [ ] Test iPhone and iPad layouts.
- [ ] Record results in `RELEASE_QA.md`.

## 9. Release logging decision

- [x] Decide whether `DebugLogger` is no-op in Release.
- [ ] If release logging remains enabled, audit every message for privacy and usefulness.
  - Not applicable for the current release decision because `DebugLogger` is no-op outside `DEBUG`.
- [x] Document the decision in `RELEASE_QA.md` or `ARCHITECTURE.md`.

## 10. Relative Markdown links decision

- [x] Decide whether tapping relative links such as `[Note](notes.md)` is supported in 1.0.
- [ ] If unsupported, document the limitation.
  - Not applicable for 1.0 because safe workspace-local relative links are supported.
- [x] If supported, implement a workspace-relative internal link resolver separate from the external URL allow-list.
- [x] Add tests for the selected behaviour.

---

# P1 — Stabilisation backlog after P0 is green

## Editor maintainability

- [ ] Keep shrinking `MarkdownEditorTextViewCoordinator.swift` by extracting accessory/menu, link tap, task checkbox, and render-scheduler helpers.
- [ ] Keep formatter string transformations in `MarkdownFormattingPlan.swift`.
- [ ] Add more plan tests for escaped brackets, parentheses in destinations, empty selections, mixed line endings, and repeated toggling.
- [ ] Add a repeatable large-document performance baseline for first render, typing, deep scroll, and line-number toggling.

## Workspace/app maintainability

- [ ] Split `WorkspaceManager` into smaller selection/restore/enumeration/mutation collaborators.
- [ ] Split `AppCoordinator` by launch/restore, document loading, mutation orchestration, and recent-file handling.
- [ ] Split `WorkspaceViewModel` presentation state from mutation command routing where it reduces risk.
- [ ] Keep existing pure policy seams covered by tests.

## Theme/settings polish

- [ ] Clarify whether new unsaved custom themes can be exported.
- [ ] Add import/export/share manual QA cases for custom themes.
- [ ] Review Settings copy for final release tone and grammar.
- [ ] Add VoiceOver and Dynamic Type QA for Settings, workspace browser, conflict UI, editor accessory, and theme editor.

## Files edge cases

- [ ] Manually verify case-only file rename on real case-insensitive iOS storage.
- [ ] Manually verify case-only folder rename on real case-insensitive iOS storage.
- [ ] Verify large workspace enumeration with unreadable folders, packages, hidden files, and symlinks.

---

# P2 — Post-release backlog

- [ ] Add SwiftFormat or SwiftLint with a minimal non-disruptive rule set.
- [ ] Create a localisation/String Catalog plan if non-English support is planned.
- [ ] Add UI/snapshot tests for high-risk Settings and navigation surfaces.
- [ ] Decide on crash/error reporting, or explicitly document a no-telemetry privacy stance.
- [ ] Consider an onboarding/sample-document flow only if it does not complicate Files workspace ownership.
- [ ] Document unsupported Markdown features.
- [ ] Profile workspace search/enumeration for very large folders.
- [ ] Consider internal relative Markdown link navigation after the 1.0 external-link policy is settled.

---

# Completed work compressed out of the active plan

The previous plan contained long completed checklists for formatter extraction, undo/redo integration, CRLF preservation, semantic heading/task formatting, theme-aware chrome, line-number stabilisation, async-task ownership, and workspace mutation policy. Those details are no longer useful as active planning items. Keep their evidence in git history, tests, and `RELEASE_QA.md` rather than re-expanding this file.
