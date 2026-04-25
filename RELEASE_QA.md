# RELEASE_QA.md

## Purpose

This file is the release/runtime QA checklist for Downward. It records command-line smoke evidence and manual validation without treating automated XCTest coverage as a substitute for device or Files-provider QA.

## Latest QA run

- Date: 2026-04-25
- Branch/commit at start of run: `main` / `0b29346`
- Xcode: Xcode 26.4 (17E192)
- Host environment: macOS 26.4.1 reported by the XCTest result bundles
- Simulator/device:
  - iPhone 17, iOS 26.4 Simulator (`20F3A4FD-4F55-4C03-8202-AFB6445903CD`)
  - iPad Pro 13-inch (M5), iOS 26.4 Simulator (`D5F73BB6-613C-4740-88C3-5964993FC08B`)
- Commands run:
  - `xcodebuild -list`
  - `xcrun simctl list devices available`
  - `xcodebuild build -scheme Downward -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4' -derivedDataPath /tmp/DownwardDerivedData-QA`
  - `xcodebuild build -scheme Downward -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=26.4' -derivedDataPath /tmp/DownwardDerivedData-QA`
  - `xcodebuild test -scheme Downward -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4' -derivedDataPath /tmp/DownwardDerivedData-QA -resultBundlePath /tmp/Downward-iPhone-Smoke.xcresult -only-testing:DownwardTests/MarkdownWorkspaceAppSmokeTests -only-testing:DownwardTests/MarkdownWorkspaceAppRestoreFlowTests -only-testing:DownwardTests/MarkdownWorkspaceAppMutationFlowTests`
  - `xcodebuild test -scheme Downward -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=26.4' -derivedDataPath /tmp/DownwardDerivedData-QA -resultBundlePath /tmp/Downward-iPad-Smoke.xcresult -only-testing:DownwardTests/MarkdownWorkspaceAppSmokeTests -only-testing:DownwardTests/MarkdownWorkspaceAppRestoreFlowTests -only-testing:DownwardTests/MarkdownWorkspaceAppMutationFlowTests`
  - `xcrun xcresulttool get test-results summary --path /tmp/Downward-iPhone-Smoke.xcresult --format json`
  - `xcrun xcresulttool get test-results summary --path /tmp/Downward-iPad-Smoke.xcresult --format json`
- Result:
  - iPhone simulator build passed.
  - iPad simulator build passed.
  - iPhone focused smoke/restore/mutation tests passed: 55 passed, 0 skipped, 0 failed.
  - iPad focused smoke/restore/mutation tests passed: 55 passed, 0 skipped, 0 failed.
- Notes/failures:
  - The first sandboxed simulator discovery attempt could not reach CoreSimulator; `xcrun simctl list devices available` succeeded after running with the approved `xcrun simctl` permission.
  - `xcodebuild -list` succeeded but emitted sandbox-related CoreSimulator/log permission warnings.
  - No manual visual QA, real-device QA, Files-provider QA, or keyboard-interaction observation was performed in this run.

## Build and Automated Tests

- [x] Confirm the `Downward` scheme is available.
- [x] Build the app for an iPhone simulator.
- [x] Build the app for an iPad simulator.
- [x] Run focused app-hosted smoke, restore, and mutation tests on an iPhone simulator.
- [x] Run focused app-hosted smoke, restore, and mutation tests on an iPad simulator.
- [ ] Run the full XCTest suite after any final release-branch changes.
- [ ] Archive/sign a release candidate build.

## iPhone Simulator Smoke

- [x] Command-line build passed on iPhone 17, iOS 26.4 Simulator.
- [x] App-hosted smoke/restore/mutation tests passed on iPhone 17, iOS 26.4 Simulator.
- [ ] Manual launch with no workspace selected observed.
- [ ] Manual workspace selection and restore observed.
- [ ] Manual compact-width Settings flow observed.
- [ ] Manual editor and keyboard flow observed.

## iPad Simulator Smoke

- [x] Command-line build passed on iPad Pro 13-inch (M5), iOS 26.4 Simulator.
- [x] App-hosted smoke/restore/mutation tests passed on iPad Pro 13-inch (M5), iOS 26.4 Simulator.
- [ ] Manual launch with no workspace selected observed.
- [ ] Manual workspace selection and restore observed.
- [ ] Manual regular-width Settings flow observed.
- [ ] Manual editor, split-view, and keyboard flow observed.

## Workspace and Files Providers

- [ ] Select a local Files workspace.
- [ ] Select an iCloud Drive workspace.
- [ ] Select a third-party provider workspace if available.
- [ ] Relaunch and confirm workspace restore.
- [ ] Reconnect after stale or missing workspace access.
- [ ] Open nested documents through the browser.
- [ ] Reopen documents from recents.
- [ ] Rename a file outside the app while it is open.
- [ ] Rename a folder outside the app while a child document is open.
- [ ] Move a file outside the app while it is open.
- [ ] Move a folder outside the app while a child document is open.
- [ ] Delete an open document outside the app.
- [ ] Delete an ancestor folder of an open document outside the app.

## Editor, Autosave, and Navigation

- [ ] Type long edits and confirm quiet autosave.
- [ ] Close and reopen an edited document after autosave.
- [ ] Switch rapidly between files while edits and loads are in flight.
- [ ] Background and foreground the app with an open document.
- [ ] Confirm first visible line placement below top chrome on iPhone portrait.
- [ ] Confirm first visible line placement below top chrome on iPhone landscape.
- [ ] Confirm first visible line placement below top chrome on iPad full screen.
- [ ] Confirm first visible line placement below top chrome on iPad split view.

## Keyboard Accessory

- [ ] First keyboard presentation does not show a white band.
- [ ] Interactive keyboard dismissal behaves correctly.
- [ ] Accessory controls remain visible and correctly tinted after scrolling.
- [ ] Accessory controls remain visible and correctly tinted after theme changes.
- [ ] Light, dark, and at least one custom non-standard theme have been observed.

## Settings and Themes

- [ ] Settings sheet hierarchy inspected on compact width.
- [ ] Settings sheet hierarchy inspected on regular width.
- [ ] Built-in theme switching observed.
- [ ] Custom theme create/edit/delete observed.
- [ ] Low-contrast theme warning observed.
- [ ] Placeholder-backed StoreKit, review, and legal actions remain visibly non-final.

## Theme Import/Export

- [ ] Import a theme from local Files storage.
- [ ] Import a theme from iCloud Drive.
- [ ] Import a theme from a third-party provider if available.
- [ ] Export a theme to local Files storage.
- [ ] Export a theme to iCloud Drive.
- [ ] Re-import exported JSON successfully.
- [ ] Confirm import errors remain user-readable for invalid or unsupported files.

## JSON Document Handling

- [ ] Open an ordinary workspace `.json` file as a text document.
- [ ] Confirm ordinary `.json` open does not trigger theme import.
- [ ] Confirm explicit Settings import remains the only theme-import path.

## Regression Guardrails

- [ ] No app-owned mirrored document store was introduced.
- [ ] Workspace-relative identity remains the preferred routing model.
- [ ] Raw URL-only document opens remain compatibility paths.
- [ ] Normal autosave remains quiet.
- [ ] Conflict UI appears only for exceptional states.
- [ ] The editor remains the SwiftUI-hosted `UITextView` boundary, not `TextEditor`.
- [ ] Keyboard host/container backgrounds are not painted without device QA evidence.

## Known Limitations and Deferred Future Features

- [ ] StoreKit tips are still placeholder-backed.
- [ ] App Store review/rating routing is still placeholder-backed.
- [ ] Legal/privacy URLs are still placeholder-backed.
- [ ] Line numbers remain future work.
- [ ] Larger heading text remains future work.
- [ ] Richer markdown constructs such as tables and footnotes remain future work.
- [ ] Deeper theme marketplace/sharing behavior remains future work.
