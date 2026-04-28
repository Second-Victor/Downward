# RELEASE_QA.md

## Purpose

This file is the release/runtime QA checklist for Downward. It records command-line smoke evidence and manual validation without treating automated XCTest coverage as a substitute for device or Files-provider QA.

## Latest QA run

- Date: 2026-04-28
- Branch/commit at start of run: `main` / working tree after `3434f2c`
- Xcode: Xcode 26.4 (17E192)
- Host environment: macOS 26.4.1 reported by XCTest result bundle
- Simulator/device:
  - iPhone 17 Pro, iOS 26.4 Simulator (`CC62C76C-307C-47B0-A4FD-B9F886C3138C`, OS build `23E244`)
- Commands run:
  - `xcodebuild test -project Downward.xcodeproj -scheme Downward -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' -derivedDataPath /tmp/DownwardDerivedData-EditorChrome -resultBundlePath /tmp/Downward-EditorChrome.xcresult -only-testing:DownwardTests/EditorAppearanceStoreTests -only-testing:DownwardTests/SettingsScreenModelTests -only-testing:DownwardTests/ThemeStoreTests -only-testing:DownwardTests/ResolvedEditorThemeChromeTests`
  - `xcodebuild test -project Downward.xcodeproj -scheme Downward -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' -derivedDataPath /tmp/DownwardDerivedData-EditorChrome2 -resultBundlePath /tmp/Downward-EditorChrome2.xcresult -only-testing:DownwardTests/EditorAppearanceStoreTests -only-testing:DownwardTests/SettingsScreenModelTests -only-testing:DownwardTests/ThemeStoreTests -only-testing:DownwardTests/ResolvedEditorThemeChromeTests`
  - `xcrun xcresulttool get test-results summary --path /tmp/Downward-EditorChrome2.xcresult --format json`
  - `xcodebuild test -project Downward.xcodeproj -scheme Downward -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' -derivedDataPath /tmp/DownwardDerivedData-EditorChromeFull -resultBundlePath /tmp/Downward-EditorChromeFull.xcresult -parallel-testing-enabled NO`
  - `xcrun xcresulttool get test-results summary --path /tmp/Downward-EditorChromeFull.xcresult --format json`
  - `git diff --check`
  - `xcodebuild test -project Downward.xcodeproj -scheme Downward -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' -derivedDataPath /tmp/DownwardDerivedData-EditorChromeNoBar -resultBundlePath /tmp/Downward-EditorChromeNoBar.xcresult -only-testing:DownwardTests/EditorAppearanceStoreTests -only-testing:DownwardTests/SettingsScreenModelTests -only-testing:DownwardTests/ThemeStoreTests -only-testing:DownwardTests/ResolvedEditorThemeChromeTests`
  - `xcrun xcresulttool get test-results summary --path /tmp/Downward-EditorChromeNoBar.xcresult --format json`
- Result:
  - Initial focused editor chrome run failed at compile because the new `ResolvedEditorThemeChromeTests` methods were nonisolated while theme helpers are main-actor isolated under the project Swift 6 settings.
  - Final focused editor chrome/settings/theme run passed: 63 passed, 0 skipped, 0 failed.
  - Full serial simulator suite passed: 503 total, 501 passed, 2 skipped, 0 failed. Four tests collected performance metrics.
  - `git diff --check` passed.
  - Follow-up focused no-bar run passed after removing the forced visible navigation toolbar background: 63 passed, 0 skipped, 0 failed.
  - The 2 skipped tests are the existing platform-gated case-only rename checks.
- Notes/failures:
  - The compile-only focused failure was fixed by marking the new chrome decision tests main-actor.
  - A visual regression was reported after the first implementation because `.toolbarBackground(.visible, for: .navigationBar)` introduced a top bar and stopped the editor from flowing underneath the controls. The implementation now avoids forcing a visible toolbar background and only requests the editor chrome color scheme.
  - `xcodebuild test` emitted recurring simulator/TextKit/AppIntents diagnostic noise, but final focused and full serial runs completed successfully.
  - No manual real-device, Files-provider, keyboard-interaction, or visual editor chrome QA was performed in this pass.

## Manual QA checklist — editor status-bar chrome

Expected result when “Match Menus to Theme” is enabled: time/battery/Wi-Fi indicators remain readable, navigation title/buttons remain readable, editor background still reaches behind the status bar, and there is no flash of wrong status-bar colour after theme changes.

Expected result when disabled: app appearance controls chrome as before.

- [ ] App Appearance = System, phone light mode, editor dark custom theme.
- [ ] App Appearance = Light, editor dark custom theme.
- [ ] App Appearance = Dark, editor light custom theme.
- [ ] App Appearance = System, phone dark mode, editor light custom theme.
- [ ] Toggle “Match Menus to Theme” on and off.
- [ ] Switch between adaptive theme, dark custom theme, and light custom theme.
- [ ] Test compact iPhone navigation.
- [ ] Test iPad split-view detail editor.
- [ ] Test after pushing editor from file list.
- [ ] Test after returning from Settings.

## Previous QA runs

- Date: 2026-04-28
- Branch/commit at start of run: `main` / working tree after `3434f2c`
- Xcode: Xcode 26.4 (17E192)
- Host environment: macOS 26.4.1 reported by XCTest result bundle
- Simulator/device:
  - iPhone 17 Pro, iOS 26.4 Simulator (`CC62C76C-307C-47B0-A4FD-B9F886C3138C`, OS build `23E244`)
- Commands run:
  - `xcodebuild test -project Downward.xcodeproj -scheme Downward -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' -derivedDataPath /tmp/DownwardDerivedData-ProgrammaticEditorUndo -resultBundlePath /tmp/Downward-ProgrammaticEditorUndo.xcresult -only-testing:DownwardTests/EditorUndoRedoTests -only-testing:DownwardTests/TaskListContinuationPlanTests -only-testing:DownwardTests/MarkdownFormattingPlanTests -only-testing:DownwardTests/LineNumberGutterViewTests`
  - `xcrun xcresulttool get test-results summary --path /tmp/Downward-ProgrammaticEditorUndo.xcresult --format json`
  - `xcodebuild test -project Downward.xcodeproj -scheme Downward -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' -derivedDataPath /tmp/DownwardDerivedData-ProgrammaticEditorUndo2 -resultBundlePath /tmp/Downward-ProgrammaticEditorUndo2.xcresult -only-testing:DownwardTests/EditorUndoRedoTests -only-testing:DownwardTests/TaskListContinuationPlanTests -only-testing:DownwardTests/MarkdownFormattingPlanTests -only-testing:DownwardTests/LineNumberGutterViewTests`
  - `xcrun xcresulttool get test-results summary --path /tmp/Downward-ProgrammaticEditorUndo2.xcresult --format json`
  - `xcodebuild test -project Downward.xcodeproj -scheme Downward -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' -derivedDataPath /tmp/DownwardDerivedData-ProgrammaticEditorUndoFull -resultBundlePath /tmp/Downward-ProgrammaticEditorUndoFull.xcresult -parallel-testing-enabled NO`
  - `xcrun xcresulttool get test-results summary --path /tmp/Downward-ProgrammaticEditorUndoFull.xcresult --format json`
- Result:
  - Initial focused programmatic editor undo run failed: 98 passed, 0 skipped, 2 failed. The failures were the new semantic heading zero-length cursor tests; the implementation preserved a cursor at line start instead of moving it after the new heading marker.
  - Final focused editor/formatting/task-continuation/line-number run passed: 100 passed, 0 skipped, 0 failed.
  - Final full serial simulator suite passed: 496 total, 494 passed, 2 skipped, 0 failed. Four tests collected performance metrics.
  - The 2 skipped tests are the existing platform-gated case-only rename checks.
- Notes/failures:
  - The cursor failure was fixed by having the formatting plan map a cursor at the heading body start to the new heading marker boundary.
  - `xcodebuild test` emitted recurring simulator/TextKit/AppIntents diagnostic noise, but final focused and full serial runs completed successfully.
  - No manual real-device, Files-provider, keyboard-interaction, line-number, hidden-syntax, or visual editor QA was performed in this pass.

- Date: 2026-04-28
- Branch/commit at start of run: `main` / working tree after `3434f2c`
- Xcode: Xcode 26.4 (17E192)
- Host environment: macOS 26.4.1 reported by XCTest result bundle
- Simulator/device:
  - iPhone 17 Pro, iOS 26.4 Simulator (`CC62C76C-307C-47B0-A4FD-B9F886C3138C`, OS build `23E244`)
- Commands run:
  - `xcodebuild -list -project Downward.xcodeproj`
  - `xcodebuild -showdestinations -project Downward.xcodeproj -scheme Downward`
  - `swiftc -typecheck -module-cache-path /tmp/DownwardSwiftModuleCache Downward/Features/Editor/MarkdownFormattingPlan.swift`
  - `xcodebuild test -project Downward.xcodeproj -scheme Downward -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' -derivedDataPath /tmp/DownwardDerivedData-FormatterStabilization4 -resultBundlePath /tmp/Downward-FormatterStabilization4.xcresult -only-testing:DownwardTests/MarkdownFormattingPlanTests -only-testing:DownwardTests/EditorUndoRedoTests -only-testing:DownwardTests/LineNumberGutterViewTests`
  - `xcrun xcresulttool get test-results summary --path /tmp/Downward-FormatterStabilization4.xcresult --format json`
  - `xcodebuild test -project Downward.xcodeproj -scheme Downward -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' -derivedDataPath /tmp/DownwardDerivedData-FormatterFull -resultBundlePath /tmp/Downward-FormatterFull.xcresult`
  - `xcrun xcresulttool get test-results summary --path /tmp/Downward-FormatterFull.xcresult --format json`
  - `xcodebuild test -project Downward.xcodeproj -scheme Downward -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' -derivedDataPath /tmp/DownwardDerivedData-RendererPerfCheck2 -resultBundlePath /tmp/Downward-RendererPerfCheck2.xcresult -only-testing:DownwardTests/MarkdownRendererPerformanceTests`
  - `xcodebuild test -project Downward.xcodeproj -scheme Downward -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' -derivedDataPath /tmp/DownwardDerivedData-FormatterFullSerial2 -resultBundlePath /tmp/Downward-FormatterFullSerial2.xcresult -parallel-testing-enabled NO`
  - `xcrun xcresulttool get test-results summary --path /tmp/Downward-FormatterFullSerial2.xcresult --format json`
- Result:
  - `xcodebuild -list` completed and confirmed the `Downward` scheme.
  - Sandboxed destination discovery showed placeholder destinations because CoreSimulator access was denied; rerunning the same destination command with approved simulator access showed the iPhone 17 Pro iOS 26.4 simulator used for tests.
  - Focused formatter/editor/gutter tests passed on iPhone 17 Pro simulator: 84 passed, 0 skipped, 0 failed.
  - An initial full parallel simulator run failed: 481 passed, 2 skipped, 4 failed. The failed tests were `MarkdownRendererPerformanceTests` diagnostics that needed the test text view to report focus before asserting current-line revealed restyling.
  - Focused renderer diagnostics passed after the harness fix: 17 passed, 0 skipped, 0 failed.
  - Final full serial simulator suite passed: 487 total, 485 passed, 2 skipped, 0 failed. Four tests collected performance metrics.
- Notes/failures:
  - The skipped tests in the final full suite are the existing platform-gated case-only rename checks.
  - Intermediate failures while adding formatter tests included Swift 6 default actor-isolation annotations and CRLF parsing that initially treated `\r\n` as one Swift `Character`; both were fixed before the final runs.
  - `xcodebuild test` emitted recurring simulator/TextKit/AppIntents diagnostic noise, including CoreSimulator clone launch messages in the failed parallel run, but the final serial full run completed successfully.
  - No manual real-device, Files-provider, keyboard-interaction, line-number, hidden-syntax, or visual editor QA was performed in this pass.

- Date: 2026-04-27
- Branch/commit at start of run: `main` / working tree after `dca6d73`
- Xcode: Xcode 26.4 (17E192)
- Host environment: macOS 26.4.1 reported by XCTest result bundle
- Simulator/device:
  - iPhone 17, iOS 26.4 Simulator (`20F3A4FD-4F55-4C03-8202-AFB6445903CD`, OS build `23E244`)
- Commands run:
  - `xcodebuild test -project Downward.xcodeproj -scheme Downward -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4' -derivedDataPath /tmp/DownwardDerivedData-LargerHeadings -resultBundlePath /tmp/Downward-LargerHeadings-3.xcresult -only-testing:DownwardTests/EditorAppearanceStoreTests -only-testing:DownwardTests/SettingsScreenModelTests -only-testing:DownwardTests/MarkdownStyledTextRendererTests -only-testing:DownwardTests/MarkdownSyntaxStyleApplicatorTests -only-testing:DownwardTests/EditorUndoRedoTests -only-testing:DownwardTests/MarkdownEditorTextViewSizingTests`
  - `xcrun xcresulttool get test-results summary --path /tmp/Downward-LargerHeadings-3.xcresult --format json`
  - `xcodebuild test -project Downward.xcodeproj -scheme Downward -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4' -derivedDataPath /tmp/DownwardDerivedData-LineNumberOverlap -resultBundlePath /tmp/Downward-LineNumberOverlap-5.xcresult -only-testing:DownwardTests/LineNumberGutterViewTests -only-testing:DownwardTests/EditorUndoRedoTests -only-testing:DownwardTests/MarkdownStyledTextRendererTests`
  - `xcrun xcresulttool get test-results summary --path /tmp/Downward-LineNumberOverlap-5.xcresult --format json`
  - `xcodebuild test -project Downward.xcodeproj -scheme Downward -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4' -derivedDataPath /tmp/DownwardDerivedData-LineNumberScroll -resultBundlePath /tmp/Downward-LineNumberScroll.xcresult -only-testing:DownwardTests/LineNumberGutterViewTests -only-testing:DownwardTests/EditorUndoRedoTests -only-testing:DownwardTests/MarkdownStyledTextRendererTests`
  - `xcrun xcresulttool get test-results summary --path /tmp/Downward-LineNumberScroll.xcresult --format json`
  - `xcodebuild test -project Downward.xcodeproj -scheme Downward -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4' -derivedDataPath /tmp/DownwardDerivedData-LineNumberGutterFix -resultBundlePath /tmp/Downward-LineNumberGutterFix.xcresult -only-testing:DownwardTests/LineNumberGutterViewTests -only-testing:DownwardTests/TextLineMetricsTests -only-testing:DownwardTests/MarkdownEditorTextViewSizingTests -only-testing:DownwardTests/EditorUndoRedoTests`
  - `xcrun xcresulttool get test-results summary --path /tmp/Downward-LineNumberGutterFix.xcresult --format json`
  - `git diff --check`
- Result:
  - Targeted larger-heading/editor/settings/renderer tests passed on iPhone 17 simulator: 91 passed, 0 skipped, 0 failed. One existing renderer performance test collected metrics.
  - Covered default larger-heading preference false, old preference decoding, persistence, renderer heading-size gating, setext/ATX heading scaling when enabled, line-number disabling when larger headings are enabled, Settings placeholder status, and editor bridge rerendering when the setting changes.
  - Targeted line-number overlap regression tests passed on iPhone 17 simulator: 64 passed, 0 skipped, 0 failed. One existing renderer performance test collected metrics.
  - Covered hidden markdown formatting with blank lines before headings so adjacent line numbers do not draw on the same y-position.
  - Targeted line-number scroll regression tests passed on iPhone 17 simulator: 65 passed, 0 skipped, 0 failed. One existing renderer performance test collected metrics.
  - Follow-up targeted gutter/metrics/editor bridge regression tests passed on iPhone 17 simulator: 43 passed, 0 skipped, 0 failed.
  - Covered keeping the gutter in text-view content coordinates while invalidating and drawing only the scrolled visible content slice.
  - `git diff --check` passed.
  - Full suite and app-hosted smoke/restore/mutation tests were not run in this pass.
- Notes/failures:
  - An earlier targeted run failed because one existing setext heading test still expected larger heading text without enabling the new preference. The final targeted run passed after updating that expectation.
  - The first overlap regression run reproduced the screenshot issue by placing line numbers for a blank line and the following hidden-syntax heading line at the same vertical position. The final targeted run passed after the gutter started anchoring to the first non-hidden character in each logical line.
  - The scroll regression shown in the provided screen recording was fixed by updating the gutter display when `UITextView.contentOffset` changes without moving the gutter frame out of content coordinates.
  - `xcodebuild test` emitted `IDERunDestination: Supported platforms for the buildables in the current scheme is empty.`, but the final targeted run completed successfully.
  - No manual real-device, Files-provider, keyboard-interaction, line-number, or larger-heading visual QA was performed in this pass.

- Date: 2026-04-27
- Branch/commit at start of run: `main` / working tree after `b35bdb3`
- Xcode: Xcode 26.4 (17E192)
- Host environment: macOS 26.4.1 reported by prior XCTest result bundles
- Simulator/device:
  - iPhone 17, iOS 26.4 Simulator (`20F3A4FD-4F55-4C03-8202-AFB6445903CD`, OS build `23E244`)
- Commands run:
  - `xcodebuild test -project Downward.xcodeproj -scheme Downward -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4' -derivedDataPath /tmp/DownwardDerivedData-LineNumbers -resultBundlePath /tmp/Downward-LineNumbers-5.xcresult -only-testing:DownwardTests/TextLineMetricsTests -only-testing:DownwardTests/LineNumberGutterViewTests -only-testing:DownwardTests/MarkdownEditorTextViewSizingTests -only-testing:DownwardTests/EditorAppearanceStoreTests -only-testing:DownwardTests/SettingsScreenModelTests -only-testing:DownwardTests/MarkdownStyledTextRendererTests -only-testing:DownwardTests/EditorUndoRedoTests`
  - `xcrun xcresulttool get test-results summary --path /tmp/Downward-LineNumbers-5.xcresult --format json`
  - `xcodebuild test -project Downward.xcodeproj -scheme Downward -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4' -derivedDataPath /tmp/DownwardDerivedData-LineNumbersSmoke -resultBundlePath /tmp/Downward-LineNumbersSmoke.xcresult -only-testing:DownwardTests/MarkdownWorkspaceAppSmokeTests -only-testing:DownwardTests/MarkdownWorkspaceAppRestoreFlowTests -only-testing:DownwardTests/MarkdownWorkspaceAppMutationFlowTests`
  - `xcrun xcresulttool get test-results summary --path /tmp/Downward-LineNumbersSmoke.xcresult --format json`
  - `git diff --check`
  - `rg -n "[T]ASKS\.md|[T]ASKS" . AGENTS.md ARCHITECTURE.md PLANS.md CODE_REVIEW.md RELEASE_QA.md .codex 2>/dev/null`
- Result:
  - Targeted line-number/editor/settings/renderer tests passed on iPhone 17 simulator: 91 passed, 0 skipped, 0 failed. One existing renderer performance test collected metrics.
  - Covered cached line metrics, gutter visibility/insets/width, visible-line-only gutter drawing, empty files, font/theme gutter updates, non-render-affecting line-number toggle, settings persistence, monospaced-only normalization, old preference decoding, and hidden-syntax line-number suppression for fenced-code delimiters and setext underline lines.
  - Focused app-hosted smoke/restore/mutation tests passed on iPhone 17 simulator: 58 passed, 0 skipped, 0 failed.
  - `git diff --check` passed.
  - Static retired task-file search passed: no retired task-file references remain.
  - Full suite was not run in this pass.
- Notes/failures:
  - Earlier iterations in this pass failed while adapting the pure line-metrics type to the project default actor isolation, while ensuring cached gutter width reapplied the text inset when toggled on, and while avoiding eager `UITextView.font` resets before viewport preservation. The final targeted run passed.
  - `xcodebuild test` emitted `IDERunDestination: Supported platforms for the buildables in the current scheme is empty.`, but the final targeted run completed successfully.
  - No manual real-device, Files-provider, keyboard-interaction, or visual line-number QA was performed in this pass.

- Date: 2026-04-27
- Branch/commit at start of run: `main` / `23496b7`
- Xcode: Xcode 26.4 (17E192)
- Host environment: macOS 26.4.1 reported by the XCTest result bundle
- Simulator/device:
  - iPhone 17 Pro, iOS 26.4 Simulator (`CC62C76C-307C-47B0-A4FD-B9F886C3138C`, OS build `23E244`)
- Commands run:
  - `xcrun simctl list devices available`
  - `xcodebuild -version`
  - `git status --short`
  - `git rev-parse --abbrev-ref HEAD`
  - `git rev-parse --short HEAD`
  - `xcodebuild test -scheme Downward -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' -derivedDataPath /tmp/DownwardDerivedData-ThemeImportExport -resultBundlePath /tmp/Downward-ThemeImportExport.xcresult -only-testing:DownwardTests/ThemeStoreTests -only-testing:DownwardTests/ThemeEditorSettingsPageTests -only-testing:DownwardTests/SettingsScreenModelTests -only-testing:DownwardTests/AppSessionSettingsPresentationTests -only-testing:DownwardTests/WorkspaceNavigationModeTests -only-testing:DownwardTests/MarkdownWorkspaceAppTrustedOpenAndRecentTests -only-testing:DownwardTests/MarkdownWorkspaceAppSmokeTests`
  - `rm -rf /tmp/Downward-ThemeImportExport.xcresult /tmp/DownwardDerivedData-ThemeImportExport`
  - `xcodebuild test -scheme Downward -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' -derivedDataPath /tmp/DownwardDerivedData-ThemeImportExport -resultBundlePath /tmp/Downward-ThemeImportExport.xcresult -only-testing:DownwardTests/ThemeStoreTests -only-testing:DownwardTests/ThemeEditorSettingsPageTests -only-testing:DownwardTests/SettingsScreenModelTests -only-testing:DownwardTests/AppSessionSettingsPresentationTests -only-testing:DownwardTests/WorkspaceNavigationModeTests -only-testing:DownwardTests/MarkdownWorkspaceAppTrustedOpenAndRecentTests -only-testing:DownwardTests/MarkdownWorkspaceAppSmokeTests`
  - `xcrun xcresulttool get test-results summary --path /tmp/Downward-ThemeImportExport.xcresult --format json`
  - `git diff --check`
  - `rg -n "[T]ASKS\.md|[T]ASKS" . AGENTS.md ARCHITECTURE.md PLANS.md CODE_REVIEW.md RELEASE_QA.md .codex 2>/dev/null`
  - `rg -n "importThemes\(" Downward -g '*.swift'`
  - `xcodebuild test -scheme Downward -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' -derivedDataPath /tmp/DownwardDerivedData-ThemeImportExportSmoke -resultBundlePath /tmp/Downward-ThemeImportExportSmoke.xcresult -only-testing:DownwardTests/MarkdownWorkspaceAppSmokeTests -only-testing:DownwardTests/MarkdownWorkspaceAppRestoreFlowTests -only-testing:DownwardTests/MarkdownWorkspaceAppMutationFlowTests`
  - `xcrun xcresulttool get test-results summary --path /tmp/Downward-ThemeImportExportSmoke.xcresult --format json`
- Result:
  - Initial targeted theme/settings/workspace JSON command failed at compile because new tests awaited actor/main-actor state inside XCTest autoclosures. The tests were adjusted to read async results into local values before assertion.
  - Final targeted theme/settings/workspace JSON tests passed on iPhone 17 Pro simulator: 105 passed, 0 skipped, 0 failed.
  - Covered theme draft export label/static helper, draft export round-trip import, filename sanitization, invalid/non-theme/empty JSON errors, unsupported schema, oversized file, duplicate import names, invalid themes inside arrays and bundles, ignored user cancellation, Settings-only import handler, workspace/browser `.json` open, recent `.json` open, stale recent `.json` handling, and last-open `.json` restore as an editor document.
  - Focused app-hosted smoke/restore/mutation tests passed on iPhone 17 Pro simulator: 58 passed, 0 skipped, 0 failed.
  - Static `importThemes(` search showed only `ThemeStore` and `ThemeSettingsPage` as production call sites.
  - `git diff --check` passed.
  - Static retired task-file search passed: no retired task-file references remain.
  - Full suite was not run in this pass.
- Notes/failures:
  - `xcodebuild test` emitted `IDERunDestination: Supported platforms for the buildables in the current scheme is empty.`, but the final targeted run completed successfully.
  - AppIntents metadata extraction/training was skipped because there is no AppIntents framework dependency.
  - No manual local Files, iCloud Drive, third-party Files-provider, real-device, keyboard, or manual theme import/export QA was performed in this pass.

- Date: 2026-04-27
- Branch/commit at start of run: `main` / `23496b7`
- Xcode: Xcode 26.4 (17E192)
- Host environment: macOS 26.4.1 reported by the XCTest result bundles
- Simulator/device:
  - iPhone 17, iOS 26.4 Simulator (`20F3A4FD-4F55-4C03-8202-AFB6445903CD`, OS build `23E244`)
- Commands run:
  - `xcrun simctl list devices available`
  - `git branch --show-current`
  - `git rev-parse --short HEAD`
  - `xcodebuild -version`
  - `xcodebuild test -scheme Downward -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4' -derivedDataPath /tmp/DownwardDerivedData-AsyncLifecycle -resultBundlePath /tmp/Downward-AsyncLifecycle.xcresult -only-testing:DownwardTests/DocumentManagerTests -only-testing:DownwardTests/EditorAutosaveTests -only-testing:DownwardTests/EditorUndoRedoTests -only-testing:DownwardTests/MarkdownRendererPerformanceTests -only-testing:DownwardTests/MarkdownStyledTextRendererTests`
  - `rm -rf /tmp/Downward-AsyncLifecycle.xcresult /tmp/DownwardDerivedData-AsyncLifecycle`
  - `xcodebuild test -scheme Downward -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4' -derivedDataPath /tmp/DownwardDerivedData-AsyncLifecycle -resultBundlePath /tmp/Downward-AsyncLifecycle.xcresult -only-testing:DownwardTests/DocumentManagerTests -only-testing:DownwardTests/EditorAutosaveTests -only-testing:DownwardTests/EditorUndoRedoTests -only-testing:DownwardTests/MarkdownRendererPerformanceTests -only-testing:DownwardTests/MarkdownStyledTextRendererTests`
  - `xcrun xcresulttool get test-results summary --path /tmp/Downward-AsyncLifecycle.xcresult --format json`
  - `xcodebuild test -scheme Downward -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4' -derivedDataPath /tmp/DownwardDerivedData-AsyncLifecycleSmoke -resultBundlePath /tmp/Downward-AsyncLifecycleSmoke.xcresult -only-testing:DownwardTests/MarkdownWorkspaceAppSmokeTests -only-testing:DownwardTests/MarkdownWorkspaceAppRestoreFlowTests -only-testing:DownwardTests/MarkdownWorkspaceAppMutationFlowTests`
  - `xcrun xcresulttool get test-results summary --path /tmp/Downward-AsyncLifecycleSmoke.xcresult --format json`
  - `git diff --check`
  - `rg -n "[T]ASKS\.md|[T]ASKS" . AGENTS.md ARCHITECTURE.md PLANS.md CODE_REVIEW.md RELEASE_QA.md .codex 2>/dev/null`
- Result:
  - Initial targeted lifecycle/editor/document test command failed at compile because the new XCTest assertions tried to `await` actor state inside XCTest autoclosures. The assertions were fixed to read actor state into local values before the final run.
  - A subsequent targeted run exposed one new viewport lifecycle test that depended on a single scheduler yield. The test was adjusted to wait briefly for the coordinator-owned task to finish before the final run.
  - Final targeted lifecycle/editor/document tests passed on iPhone 17 simulator: 124 passed, 0 skipped, 0 failed. Four tests collected performance metrics.
  - Focused app-hosted smoke/restore/mutation tests passed on iPhone 17 simulator: 57 passed, 0 skipped, 0 failed.
  - `git diff --check` passed.
  - Static retired task-file search passed: no retired task-file references remain.
  - Full suite was not run in this pass.
- Notes/failures:
  - `xcodebuild test` emitted `IDERunDestination: Supported platforms for the buildables in the current scheme is empty.`, but the final targeted and focused smoke runs completed successfully.
  - AppIntents metadata extraction was skipped because there is no AppIntents framework dependency.
  - The failed intermediate targeted run emitted CoreSimulator clone launch `NSMachErrorDomain Code=-308` messages after the test failure.
  - No manual visual QA, real-device QA, Files-provider QA, keyboard-interaction observation, or theme UX QA was performed in this pass.

- Date: 2026-04-27
- Branch/commit at start of run: `main` / `23496b7`
- Xcode: Xcode 26.4 (17E192)
- Host environment: macOS 26.4.1 reported by the XCTest result bundles
- Simulator/device:
  - iPhone 17, iOS 26.4 Simulator (`20F3A4FD-4F55-4C03-8202-AFB6445903CD`, OS build `23E244`)
- Commands run:
  - `xcrun simctl list devices available`
  - `git branch --show-current`
  - `git rev-parse --short HEAD`
  - `xcodebuild -version`
  - `xcodebuild test -scheme Downward -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4' -derivedDataPath /tmp/DownwardDerivedData-RendererScalability -resultBundlePath /tmp/Downward-RendererScalability.xcresult -only-testing:DownwardTests/MarkdownRendererPerformanceTests -only-testing:DownwardTests/MarkdownStyledTextRendererTests -only-testing:DownwardTests/MarkdownSyntaxScannerTests -only-testing:DownwardTests/MarkdownSyntaxStyleApplicatorTests -only-testing:DownwardTests/MarkdownEditorTextViewSizingTests`
  - `xcrun xcresulttool get test-results summary --path /tmp/Downward-RendererScalability.xcresult --format json`
  - `rm -rf /tmp/Downward-RendererScalability.xcresult /tmp/DownwardDerivedData-RendererScalability`
  - `xcodebuild test -scheme Downward -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4' -derivedDataPath /tmp/DownwardDerivedData-RendererScalability -resultBundlePath /tmp/Downward-RendererScalability.xcresult -only-testing:DownwardTests/MarkdownRendererPerformanceTests -only-testing:DownwardTests/MarkdownStyledTextRendererTests -only-testing:DownwardTests/MarkdownSyntaxScannerTests -only-testing:DownwardTests/MarkdownSyntaxStyleApplicatorTests -only-testing:DownwardTests/MarkdownEditorTextViewSizingTests`
  - `xcrun xcresulttool get test-results summary --path /tmp/Downward-RendererScalability.xcresult --format json`
  - `xcodebuild test -scheme Downward -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4' -derivedDataPath /tmp/DownwardDerivedData-RendererScalabilitySmoke -resultBundlePath /tmp/Downward-RendererScalabilitySmoke.xcresult -only-testing:DownwardTests/MarkdownWorkspaceAppSmokeTests -only-testing:DownwardTests/MarkdownWorkspaceAppRestoreFlowTests -only-testing:DownwardTests/MarkdownWorkspaceAppMutationFlowTests`
  - `xcrun xcresulttool get test-results summary --path /tmp/Downward-RendererScalabilitySmoke.xcresult --format json`
  - `git diff --check`
  - `rg -n "[T]ASKS\.md|[T]ASKS" . AGENTS.md ARCHITECTURE.md PLANS.md CODE_REVIEW.md RELEASE_QA.md .codex 2>/dev/null`
- Result:
  - Initial targeted renderer/scanner/style run failed after new tests exposed three current-line fallback gaps: same-line link/image fixture adjacent to a fence, removing an existing blockquote marker in the test simulation, and setext underline role detection after mutation. The fixture/simulation were corrected where appropriate, and setext underline role tracking plus horizontal-rule current-line gating were added before the final run.
  - Final targeted renderer/scanner/style tests passed on iPhone 17 simulator: 65 passed, 0 skipped, 0 failed. Four tests collected performance metrics.
  - Focused app-hosted smoke/restore/mutation tests passed on iPhone 17 simulator: 57 passed, 0 skipped, 0 failed.
  - 50k-line coverage is diagnostic line-scanning coverage only; normal XCTest does not perform a full 50k-line TextKit render in this pass.
  - `git diff --check` passed.
  - Static retired task-file search passed: no retired task-file references remain.
- Notes/failures:
  - `xcodebuild test` emitted `IDERunDestination: Supported platforms for the buildables in the current scheme is empty.`, but final test runs completed successfully.
  - The failed first targeted run also emitted CoreSimulator clone launch `NSMachErrorDomain Code=-308` messages after the test failures.
  - AppIntents metadata extraction was skipped because there is no AppIntents framework dependency.
  - No manual visual QA, real-device QA, Files-provider QA, keyboard-interaction observation, or theme UX QA was performed in this pass.

- Date: 2026-04-27
- Branch/commit at start of run: `main` / `23496b7`
- Xcode: Xcode 26.4 (17E192)
- Host environment: macOS 26.4.1 reported by the XCTest result bundles
- Simulator/device:
  - iPhone 17, iOS 26.4 Simulator (`20F3A4FD-4F55-4C03-8202-AFB6445903CD`, OS build `23E244`)
- Commands run:
  - `rg -n "\bTask\s*\{" Downward`
  - `xcrun simctl list devices available`
  - `git status --short`
  - `git branch --show-current`
  - `git rev-parse --short HEAD`
  - `xcodebuild -version`
  - `rm -rf /tmp/Downward-RemainingAsync.xcresult /tmp/DownwardDerivedData-RemainingAsync`
  - `xcodebuild test -scheme Downward -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4' -derivedDataPath /tmp/DownwardDerivedData-RemainingAsync -resultBundlePath /tmp/Downward-RemainingAsync.xcresult -only-testing:DownwardTests/WorkspaceSearchTests -only-testing:DownwardTests/WorkspaceNavigationModeTests -only-testing:DownwardTests/MarkdownWorkspaceAppMutationFlowTests -only-testing:DownwardTests/MarkdownWorkspaceAppTrustedOpenAndRecentTests -only-testing:DownwardTests/ThemeStoreTests -only-testing:DownwardTests/ThemeEditorSettingsPageTests -only-testing:DownwardTests/SettingsScreenModelTests -only-testing:DownwardTests/AppSessionSettingsPresentationTests`
  - `xcrun xcresulttool get test-results summary --path /tmp/Downward-RemainingAsync.xcresult --format json`
  - `xcodebuild test -scheme Downward -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4' -derivedDataPath /tmp/DownwardDerivedData-RemainingAsyncSmoke -resultBundlePath /tmp/Downward-RemainingAsyncSmoke.xcresult -only-testing:DownwardTests/MarkdownWorkspaceAppSmokeTests -only-testing:DownwardTests/MarkdownWorkspaceAppRestoreFlowTests -only-testing:DownwardTests/MarkdownWorkspaceAppMutationFlowTests`
  - `xcrun xcresulttool get test-results summary --path /tmp/Downward-RemainingAsyncSmoke.xcresult --format json`
  - `git diff --check`
  - `rg -n "[T]ASKS\.md|[T]ASKS" . AGENTS.md ARCHITECTURE.md PLANS.md CODE_REVIEW.md RELEASE_QA.md .codex 2>/dev/null`
- Result:
  - Initial targeted test command failed at compile after the first local edit because `ThemeStore` and `WorkspaceViewModel` deinitializers needed Swift 6 isolated deinit syntax to cancel main-actor task state. That was fixed before the final run.
  - Targeted async/settings/workspace tests passed on iPhone 17 simulator: 99 passed, 0 skipped, 0 failed.
  - Focused app-hosted smoke/restore/mutation tests passed on iPhone 17 simulator: 57 passed, 0 skipped, 0 failed.
  - `git diff --check` passed.
  - Static retired task-file search passed: no retired task-file references remain.
- Notes/failures:
  - `xcodebuild test` emitted `IDERunDestination: Supported platforms for the buildables in the current scheme is empty.`, but both final test runs completed successfully.
  - Asset catalog processing emitted the existing simulator CoreImage `CIPortraitEffectSpillCorrection` filter warning.
  - AppIntents metadata extraction was skipped because there is no AppIntents framework dependency.
  - No manual visual QA, real-device QA, Files-provider QA, keyboard-interaction observation, or theme UX QA was performed in this pass.

- Date: 2026-04-27
- Branch/commit at start of run: `main` / `23496b7`
- Xcode: Xcode 26.4 (17E192)
- Host environment: macOS 26.4.1 reported by the XCTest result bundles
- Simulator/device:
  - iPhone 17, iOS 26.4 Simulator (`20F3A4FD-4F55-4C03-8202-AFB6445903CD`, OS build `23E244`)
- Commands run:
  - `git branch --show-current`
  - `git rev-parse --short HEAD`
  - `xcodebuild -version`
  - `xcrun simctl list devices available`
  - `rm -rf /tmp/Downward-MutationRecents.xcresult /tmp/DownwardDerivedData-MutationRecents`
  - `xcodebuild test -scheme Downward -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4' -derivedDataPath /tmp/DownwardDerivedData-MutationRecents -resultBundlePath /tmp/Downward-MutationRecents.xcresult -only-testing:DownwardTests/MarkdownWorkspaceAppMutationFlowTests -only-testing:DownwardTests/MarkdownWorkspaceAppTrustedOpenAndRecentTests -only-testing:DownwardTests/RecentFilesStoreTests -only-testing:DownwardTests/WorkspaceCoordinatorPolicyTests -only-testing:DownwardTests/WorkspaceManagerRestoreTests -only-testing:DownwardTests/WorkspaceSnapshotPathResolverTests`
  - `xcrun xcresulttool get test-results summary --path /tmp/Downward-MutationRecents.xcresult --format json`
  - `rm -rf /tmp/Downward-MutationRecentsSmoke.xcresult /tmp/DownwardDerivedData-MutationRecentsSmoke`
  - `xcodebuild test -scheme Downward -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4' -derivedDataPath /tmp/DownwardDerivedData-MutationRecentsSmoke -resultBundlePath /tmp/Downward-MutationRecentsSmoke.xcresult -only-testing:DownwardTests/MarkdownWorkspaceAppSmokeTests -only-testing:DownwardTests/MarkdownWorkspaceAppRestoreFlowTests -only-testing:DownwardTests/MarkdownWorkspaceAppMutationFlowTests`
  - `xcrun xcresulttool get test-results summary --path /tmp/Downward-MutationRecentsSmoke.xcresult --format json`
  - `git diff --check`
  - `rg -n "[T]ASKS\.md|[T]ASKS" . AGENTS.md ARCHITECTURE.md PLANS.md CODE_REVIEW.md RELEASE_QA.md .codex 2>/dev/null`
- Result:
  - Targeted mutation/recents suite passed on iPhone 17 simulator: 103 passed, 2 skipped, 0 failed.
  - The 2 skipped tests were platform-gated live case-only rename checks that require a case-insensitive volume.
  - Focused app-hosted smoke/restore/mutation tests passed on iPhone 17 simulator: 57 passed, 0 skipped, 0 failed.
  - `git diff --check` passed.
  - Static retired task-file search passed: no retired task-file references remain.
- Notes/failures:
  - `xcodebuild test` emitted `IDERunDestination: Supported platforms for the buildables in the current scheme is empty.`, but both final test runs completed successfully.
  - AppIntents metadata extraction was skipped because there is no AppIntents framework dependency.
  - No manual visual QA, real-device QA, Files-provider QA, or keyboard-interaction observation was performed in this pass.

- Date: 2026-04-26
- Branch/commit at start of run: `main` / `23496b7`
- Xcode: Xcode 26.4 (17E192)
- Host environment: macOS 26.4.1 reported by the XCTest result bundles
- Simulator/device:
  - iPhone 17, iOS 26.4 Simulator (`20F3A4FD-4F55-4C03-8202-AFB6445903CD`)
- Commands run:
  - `rg -n "\bTask\s*\{" Downward`
  - `xcrun simctl list devices available`
  - `xcodebuild test -scheme Downward -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4' -derivedDataPath /tmp/DownwardDerivedData-AsyncOwnership -resultBundlePath /tmp/Downward-AsyncOwnership.xcresult -only-testing:DownwardTests/EditorAutosaveTests -only-testing:DownwardTests/EditorConflictTests`
  - `rm -rf /tmp/Downward-AsyncOwnership.xcresult /tmp/DownwardDerivedData-AsyncOwnership`
  - `xcodebuild test -scheme Downward -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4' -derivedDataPath /tmp/DownwardDerivedData-AsyncOwnership -resultBundlePath /tmp/Downward-AsyncOwnership.xcresult -only-testing:DownwardTests/EditorAutosaveTests -only-testing:DownwardTests/EditorConflictTests`
  - `xcrun xcresulttool get test-results summary --path /tmp/Downward-AsyncOwnership.xcresult --format json`
  - `xcodebuild test -scheme Downward -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4' -derivedDataPath /tmp/DownwardDerivedData-AsyncOwnershipSmoke -resultBundlePath /tmp/Downward-AsyncOwnershipSmoke.xcresult -only-testing:DownwardTests/MarkdownWorkspaceAppSmokeTests -only-testing:DownwardTests/MarkdownWorkspaceAppRestoreFlowTests -only-testing:DownwardTests/MarkdownWorkspaceAppMutationFlowTests`
  - `xcrun xcresulttool get test-results summary --path /tmp/Downward-AsyncOwnershipSmoke.xcresult --format json`
  - `git diff --check`
  - `rg -n "[T]ASKS\.md|[T]ASKS" . AGENTS.md ARCHITECTURE.md PLANS.md CODE_REVIEW.md RELEASE_QA.md .codex 2>/dev/null`
  - `git branch --show-current`
  - `git rev-parse --short HEAD`
  - `xcodebuild -version`
- Result:
  - Initial targeted editor test command failed at compile after the first local edit because `handleTextChange(_:)` still passed an optional route document into the identity helper. That was fixed before the final run.
  - Targeted editor autosave/conflict tests passed on iPhone 17 simulator: 28 passed, 0 skipped, 0 failed.
  - Focused app-hosted smoke/restore/mutation tests passed on iPhone 17 simulator: 55 passed, 0 skipped, 0 failed.
  - Static task audit command completed and still shows the remaining production `Task { ... }` sites documented in `PLANS.md`.
  - Static retired task-file search passed: no retired task-file references remain.
  - `git diff --check` passed.
- Notes/failures:
  - `xcodebuild test` emitted `IDERunDestination: Supported platforms for the buildables in the current scheme is empty.`, but both final test runs completed successfully.
  - AppIntents metadata extraction was skipped because there is no AppIntents framework dependency.
  - No manual visual QA, real-device QA, Files-provider QA, or keyboard-interaction observation was performed in this pass.

- Date: 2026-04-26
- Branch/commit at start of run: `main` / `23496b7`
- Xcode: Xcode 26.4 (17E192)
- Host environment: macOS 26.4.1 reported by the XCTest result bundles
- Simulator/device:
  - iPhone 17, iOS 26.4 Simulator (`20F3A4FD-4F55-4C03-8202-AFB6445903CD`)
  - iPad Pro 13-inch (M5), iOS 26.4 Simulator (`D5F73BB6-613C-4740-88C3-5964993FC08B`)
- Commands run:
  - `xcrun simctl list devices available`
  - `rm -rf /tmp/Downward-iPhone-FocusedP0.xcresult /tmp/Downward-iPad-FocusedP0.xcresult /tmp/DownwardDerivedData-FocusedP0-iPhone /tmp/DownwardDerivedData-FocusedP0-iPad`
  - `xcodebuild test -scheme Downward -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4' -derivedDataPath /tmp/DownwardDerivedData-FocusedP0-iPhone -resultBundlePath /tmp/Downward-iPhone-FocusedP0.xcresult -only-testing:DownwardTests/MarkdownWorkspaceAppSmokeTests -only-testing:DownwardTests/MarkdownWorkspaceAppRestoreFlowTests -only-testing:DownwardTests/MarkdownWorkspaceAppMutationFlowTests`
  - `xcodebuild test -scheme Downward -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=26.4' -derivedDataPath /tmp/DownwardDerivedData-FocusedP0-iPad -resultBundlePath /tmp/Downward-iPad-FocusedP0.xcresult -only-testing:DownwardTests/MarkdownWorkspaceAppSmokeTests -only-testing:DownwardTests/MarkdownWorkspaceAppRestoreFlowTests -only-testing:DownwardTests/MarkdownWorkspaceAppMutationFlowTests`
  - `xcrun xcresulttool get test-results summary --path /tmp/Downward-iPhone-FocusedP0.xcresult --format json`
  - `xcrun xcresulttool get test-results summary --path /tmp/Downward-iPad-FocusedP0.xcresult --format json`
  - `rg -n "[T]ASKS\.md|[T]ASKS" . AGENTS.md ARCHITECTURE.md PLANS.md CODE_REVIEW.md RELEASE_QA.md .codex 2>/dev/null`
  - `git diff --check`
  - `xcodebuild build -scheme Downward -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4' -derivedDataPath /tmp/DownwardDerivedData-BoundaryComments`
- Result:
  - iPhone focused smoke/restore/mutation tests passed: 55 passed, 0 skipped, 0 failed.
  - iPad focused smoke/restore/mutation tests passed: 55 passed, 0 skipped, 0 failed.
  - Static search passed: no retired task-file references remain.
  - `git diff --check` passed.
  - Comment/doc build sanity passed on iPhone 17 simulator.
- Notes/failures:
  - `xcodebuild test` and the final build sanity pass emitted `IDERunDestination: Supported platforms for the buildables in the current scheme is empty.`, but all runs completed successfully.
  - Asset catalog processing emitted the existing CoreImage `CIPortraitEffectSpillCorrection` simulator filter warning during simulator build phases.
  - No manual visual QA, real-device QA, Files-provider QA, or keyboard-interaction observation was performed in this pass.

- Date: 2026-04-26
- Branch/commit at start of run: `main` / `23496b7`
- Xcode: Xcode 26.4 (17E192)
- Host environment: macOS 26.4.1 reported by the XCTest result bundle
- Simulator/device:
  - iPhone 17, iOS 26.4 Simulator (`20F3A4FD-4F55-4C03-8202-AFB6445903CD`)
  - iPad Pro 13-inch (M5), iOS 26.4 Simulator (`D5F73BB6-613C-4740-88C3-5964993FC08B`)
- Commands run:
  - `rg -n "[T]ASKS\.md|[T]ASKS" . AGENTS.md ARCHITECTURE.md PLANS.md CODE_REVIEW.md RELEASE_QA.md .codex 2>/dev/null`
  - `xcodebuild -list`
  - `xcrun simctl list devices available`
  - `xcodebuild build -scheme Downward -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4' -derivedDataPath /tmp/DownwardDerivedData-DocsPass`
  - `xcodebuild build -scheme Downward -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=26.4' -derivedDataPath /tmp/DownwardDerivedData-DocsPass`
  - `xcodebuild test -scheme Downward -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4' -derivedDataPath /tmp/DownwardDerivedData-DocsPass -resultBundlePath /tmp/Downward-FullTests-DocsPass.xcresult`
  - `xcrun xcresulttool get test-results summary --path /tmp/Downward-FullTests-DocsPass.xcresult --format json`
- Result:
  - Static search passed: no retired task-file references remain.
  - `xcodebuild -list` passed and confirmed the `Downward` scheme.
  - iPhone simulator build passed.
  - iPad simulator build passed.
  - Full XCTest suite passed on iPhone 17 simulator: 354 passed, 2 skipped, 0 failed.
- Notes/failures:
  - `xcodebuild -list` emitted sandbox-related CoreSimulator/log permission warnings but still returned the project, targets, and scheme.
  - No manual visual QA, real-device QA, Files-provider QA, or keyboard-interaction observation was performed in this documentation pass.

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
- [ ] Richer markdown constructs such as tables and footnotes remain future work.
- [ ] Deeper theme marketplace/sharing behavior remains future work.
