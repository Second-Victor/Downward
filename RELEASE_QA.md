# Downward Release QA

Use this file for dated build, test, archive, device, Files-provider, StoreKit, accessibility, and performance evidence for release candidates. Open work and release decisions stay in `TODO.md`.

## 2026-05-01 Local Automation Sweep

Commit: pending local changes  
Xcode: Xcode 26.4 (Build 17E192)  
Environment: local Codex workspace at `/Users/allan/Desktop/Downward`

### Commands

- `xcodebuild -version`
  - Result: passed.
  - Output: Xcode 26.4, Build 17E192.
- `xcrun simctl list devices available`
  - Result: passed.
  - Available runtime includes iOS 26.4 with iPhone 17 Pro and iPad Pro 13-inch (M5) simulators.
- `xcodebuild -list -project Downward.xcodeproj`
  - Result: passed.
  - Schemes: `Downward`.
  - Targets: `Downward`, `DownwardTests`.
  - Notes: sandboxed run printed CoreSimulator/log permission warnings before listing project data.
- `xcodebuild test -project Downward.xcodeproj -scheme Downward -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/DownwardDerivedData-TODO-iPhone`
  - Result: passed.
  - Device: iPhone 17 Pro simulator, iOS 26.4, OS build 23E244.
  - Result bundle: `/tmp/DownwardDerivedData-TODO-iPhone/Logs/Test/Test-Downward-2026.05.01_11-51-09-+0100.xcresult`.
  - XCTest summary: 615 total, 613 passed, 2 skipped, 0 failed.
- `xcodebuild build -project Downward.xcodeproj -scheme Downward -configuration Debug -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' -derivedDataPath /tmp/DownwardDerivedData-TODO-iPad`
  - Result: passed.
  - Device: iPad Pro 13-inch (M5) simulator, iOS 26.4.
- `xcodebuild test -project Downward.xcodeproj -scheme Downward -destination 'platform=iOS Simulator,name=iPad Air 11-inch (M4)' -parallel-testing-enabled NO -only-testing:DownwardTests/EditorUndoRedoTests -derivedDataPath /tmp/DownwardDerivedData-TODO-iPadAir-EditorUndo`
  - Result: passed.
  - XCTest summary from console: 70 tests, 0 failures.
  - Purpose: verified iPad-specific keyboard accessory expectations after updating the tests for the production iPad toolbar layout.
- `xcodebuild test -project Downward.xcodeproj -scheme Downward -destination 'platform=iOS Simulator,name=iPad (A16)' -parallel-testing-enabled NO -derivedDataPath /tmp/DownwardDerivedData-TODO-iPadA16-Full -resultBundlePath /tmp/Downward-TODO-iPadA16-Full.xcresult`
  - Result: passed.
  - Device: iPad (A16) simulator, iOS 26.4, OS build 23E244.
  - XCTest summary: 615 total, 613 passed, 2 skipped, 0 failed.
- `xcodebuild build -project Downward.xcodeproj -scheme Downward -configuration Release -destination 'generic/platform=iOS' -derivedDataPath /tmp/DownwardDerivedData-TODO-Release`
  - Result: passed.
  - Signing used local Apple Development identity and team provisioning profile, not App Store distribution archive signing.

### Notes

- Release decision: Downward 1.0 targets iOS/iPadOS 26.0 and later. Earlier OS support is intentionally out of scope for 1.0 so the app can ship against the current SwiftUI, StoreKit, Files, and privacy-manifest surface already used by the codebase.
- StoreKit Sandbox evidence: user reported that purchases work on a real device. Exact device, OS version, sandbox account/storefront, and product IDs tested still need to be recorded. TestFlight purchase verification remains pending.
- Earlier full-suite iPad attempts on iPad Pro 13-inch (M5) and iPad Air 11-inch (M4) hit CoreSimulator launch failures, including `NSMachErrorDomain Code=-308` and `FBSOpenApplicationServiceErrorDomain Code=1` / Busy preflight failures. A final full-suite run on iPad (A16) completed successfully after running outside the sandbox.
- The only build warnings observed were AppIntents metadata extraction notices for a target without AppIntents and a CoreImage asset catalog runtime message; no new deployment-target availability warnings were observed.

### Still Pending For Release

- Archive validation and App Store/TestFlight export.
- Real-device iPhone/iPad install and Files-provider QA.
- StoreKit TestFlight purchase verification and complete product metadata evidence.
- Accessibility and large-document manual passes.

## 2026-05-02 P0 Safety Automation Pass

Commit: pending local changes
Xcode: Xcode 26.4 (Build 17E192, observed from existing local QA evidence)
Environment: local Codex workspace at `/Users/allan/Desktop/Downward`

### Commands

- `xcodebuild test -scheme Downward -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:DownwardTests/DocumentOpenPolicyTests -only-testing:DownwardTests/DocumentManagerTests`
  - Result: not run.
  - Reason: no available `iPhone 16` simulator on this machine.
  - Available replacement used below: `iPhone 17`, iOS 26.4.
- `xcodebuild test -scheme Downward -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:DownwardTests/DocumentOpenPolicyTests -only-testing:DownwardTests/DocumentManagerTests`
  - Result: passed.
  - Result bundle: `/Users/allan/Library/Developer/Xcode/DerivedData/Downward-fupsxqwhshigocamtqlhwdgeozup/Logs/Test/Test-Downward-2026.05.02_17-26-18-+0100.xcresult`.
  - Coverage: document open policy below/at/above 5 MB, invalid UTF-8, missing files, save/conflict behavior.
- `xcodebuild test -scheme Downward -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:DownwardTests/WorkspaceDeleteConfirmationPresentationTests -only-testing:DownwardTests/MarkdownWorkspaceAppMutationFlowTests/testDeleteActiveOpenDocumentClosesEditorAndShowsExplicitMessage -only-testing:DownwardTests/MarkdownWorkspaceAppMutationFlowTests/testDeleteAncestorFolderOfOpenDocumentClosesEditorClearsRestoreStateAndRecents`
  - Result: passed.
  - Result bundle: `/Users/allan/Library/Developer/Xcode/DerivedData/Downward-fupsxqwhshigocamtqlhwdgeozup/Logs/Test/Test-Downward-2026.05.02_17-28-10-+0100.xcresult`.
  - Coverage: permanent delete copy for files/folders, stronger non-empty folder dialog copy, and editor cleanup after deleting active documents/ancestor folders.
- `xcodebuild test -scheme Downward -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:DownwardTests/DocumentManagerTests/testSaveWriteFailureThrowsDocumentSaveFailedAndLeavesFileUnchanged -only-testing:DownwardTests/EditorAutosaveTests/testSaveFailureKeepsRedDotVisible`
  - Result: passed.
  - Result bundle: `/Users/allan/Library/Developer/Xcode/DerivedData/Downward-fupsxqwhshigocamtqlhwdgeozup/Logs/Test/Test-Downward-2026.05.02_17-29-44-+0100.xcresult`.
  - Coverage: direct write failure on a read-only file throws `documentSaveFailed`, leaves disk text unchanged, and editor autosave failure keeps dirty state with visible error copy.
- `xcodebuild test -scheme Downward -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO -only-testing:DownwardTests/StoreProductIdentifiersTests -only-testing:DownwardTests/SettingsScreenModelTests/testReleaseConfigurationShowsImplementedSettingsSurfaces -only-testing:DownwardTests/SettingsScreenModelTests/testConfiguredReleaseSurfacesCanBeReenabled -only-testing:DownwardTests/SettingsScreenModelTests/testSettingsHomeReleaseSurfacesFollowConfiguration`
  - Result: failed before XCTest due to simulator launch failure.
  - Result bundle: `/Users/allan/Library/Developer/Xcode/DerivedData/Downward-fupsxqwhshigocamtqlhwdgeozup/Logs/Test/Test-Downward-2026.05.02_17-36-17-+0100.xcresult`.
  - Error: `FBSOpenApplicationServiceErrorDomain Code=1`, simulator preflight `Busy`.
  - Note: earlier attempt with parallel testing also hit simulator launch service failures and was interrupted after stalling. The code compiled far enough to catch Swift compile errors; the StoreKit parity XCTest still needs a clean simulator run.
- `xcodebuild test -scheme Downward -destination 'platform=iOS Simulator,name=iPad (A16)' -parallel-testing-enabled NO -only-testing:DownwardTests/StoreProductIdentifiersTests -only-testing:DownwardTests/SettingsScreenModelTests/testReleaseConfigurationShowsImplementedSettingsSurfaces -only-testing:DownwardTests/SettingsScreenModelTests/testConfiguredReleaseSurfacesCanBeReenabled -only-testing:DownwardTests/SettingsScreenModelTests/testSettingsHomeReleaseSurfacesFollowConfiguration`
  - Result: failed before XCTest due to simulator launch failure.
  - Result bundle: `/Users/allan/Library/Developer/Xcode/DerivedData/Downward-fupsxqwhshigocamtqlhwdgeozup/Logs/Test/Test-Downward-2026.05.02_17-39-47-+0100.xcresult`.
  - Error: `FBSOpenApplicationServiceErrorDomain Code=1`, simulator preflight `Busy`.
  - Note: this repeated the launch-service failure on a separate simulator after the app and tests had compiled, so StoreKit parity/release-configuration XCTest still needs a clean run.
- `xcodebuild build -scheme Downward -destination 'generic/platform=iOS Simulator'`
  - Result: passed.
  - Coverage: app target compiles, links, copies `Downward.storekit` and `PrivacyInfo.xcprivacy`, signs for local simulator run, and validates the simulator bundle.

### Static Findings Recorded

- Large document open policy: 5 MB maximum for 1.0, enforced before full `Data(contentsOf:)` reads. Missing/unverifiable size metadata is rejected with user-facing open-failure copy.
- Delete copy: dialogs now say items are permanently deleted from Files and the underlying workspace; non-empty folders use stronger title/button/copy that explicitly names contents.
- StoreKit IDs: code now centralizes Supporter and Tip product IDs in `StoreProductIdentifiers`; Tips were temporarily hidden until device testing, then re-enabled after local device validation.
- Privacy manifest static scan: current manifest declares UserDefaults and file timestamp access. Static code scan found UserDefaults stores and file timestamp reads in workspace/document enumeration/versioning, matching those declarations. No data collection/tracking declarations were added.
- URL force unwrap scan: replaced the production force-unwrapped Second Victor URL in `AboutSettingsPage` with a safe optional path.

## 2026-05-03 P0 Release Hardening Pass

Commit: pending local changes
Xcode: Xcode 26.4 (Build 17E192, observed from existing local QA evidence)
Environment: local Codex workspace at `/Users/allan/Desktop/Downward`

### Commands

- `xcodebuild build -scheme Downward -destination 'generic/platform=iOS Simulator'`
  - Result: passed before the Supporter release-gate edit.
  - Coverage: app target compiled, linked, copied `PrivacyInfo.xcprivacy` and `Downward.storekit`, signed the simulator build, and validated the app bundle.
- `xcrun simctl list devices available`
  - Result: passed.
  - Note: no `iPhone 16` simulator was available. Replacement used for focused tests: `iPhone 17`, iOS 26.4.
- `xcodebuild test -scheme Downward -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO -only-testing:DownwardTests/DocumentOpenPolicyTests -only-testing:DownwardTests/DocumentManagerTests -only-testing:DownwardTests/EditorAutosaveTests -only-testing:DownwardTests/WorkspaceDeleteConfirmationPresentationTests -only-testing:DownwardTests/WorkspaceEnumeratorTests -only-testing:DownwardTests/StoreProductIdentifiersTests -only-testing:DownwardTests/SettingsScreenModelTests`
  - Result: passed before the Supporter release-gate edit.
  - Result bundle: `/Users/allan/Library/Developer/Xcode/DerivedData/Downward-fupsxqwhshigocamtqlhwdgeozup/Logs/Test/Test-Downward-2026.05.03_08-06-31-+0100.xcresult`.
  - XCTest summary: 107 tests, 0 failures, 0 unexpected.
- `xcodebuild test -scheme Downward -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO -only-testing:DownwardTests/SettingsScreenModelTests`
  - Result: interrupted after producing no additional output for several minutes after invocation.
  - Reason recorded: local simulator/test-runner hang during targeted rerun after adding the Supporter release gate. This is not counted as a pass.
- `xcodebuild build -scheme Downward -destination 'generic/platform=iOS Simulator'`
  - Result: interrupted after producing no additional output for several minutes after invocation.
  - Reason recorded: local `xcodebuild` invocation hang after the targeted settings run stalled. This is not counted as a pass.
- `xcodebuild build -scheme Downward -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/DownwardDerivedData-P0Hardening-20260503`
  - Result: passed after the Supporter release-gate edit.
  - Coverage: app target compiled, linked, signed for simulator, copied `PrivacyInfo.xcprivacy` and `Downward.storekit`, and validated the app bundle.
- `xcodebuild test -scheme Downward -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO -derivedDataPath /tmp/DownwardDerivedData-P0HardeningTests-20260503 -only-testing:DownwardTests/DocumentOpenPolicyTests -only-testing:DownwardTests/DocumentManagerTests -only-testing:DownwardTests/EditorAutosaveTests -only-testing:DownwardTests/WorkspaceDeleteConfirmationPresentationTests -only-testing:DownwardTests/WorkspaceEnumeratorTests -only-testing:DownwardTests/StoreProductIdentifiersTests -only-testing:DownwardTests/SettingsScreenModelTests`
  - Result: failed before XCTest due to simulator launch failure after compiling the app and tests.
  - Result bundle: `/tmp/DownwardDerivedData-P0HardeningTests-20260503/Logs/Test/Test-Downward-2026.05.03_08-21-28-+0100.xcresult`.
  - Error: `FBSOpenApplicationServiceErrorDomain Code=1`; simulator preflight `Busy`.
- `xcrun simctl shutdown "iPhone 17"`
  - Result: no-op; simulator already shut down.
- `xcodebuild test -scheme Downward -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO -derivedDataPath /tmp/DownwardDerivedData-P0HardeningTests-iPhone17Pro-20260503 -only-testing:DownwardTests/SettingsScreenModelTests -only-testing:DownwardTests/StoreProductIdentifiersTests`
  - Result: failed before XCTest due to simulator launch failure after compiling the app and tests.
  - Result bundle: `/tmp/DownwardDerivedData-P0HardeningTests-iPhone17Pro-20260503/Logs/Test/Test-Downward-2026.05.03_08-22-17-+0100.xcresult`.
  - Error: `FBSOpenApplicationServiceErrorDomain Code=1`; simulator preflight `Busy`.

### Static Findings Recorded

- Large document open policy: `DocumentOpenPolicy.maximumReadableFileSize` remains the single 5 MB threshold. Normal document opening validates size before `PlainTextDocumentSession.readUTF8TextContents(from:)` performs a full `Data(contentsOf:)` read. Missing or unverifiable size metadata is rejected.
- Delete protection: non-empty folder presentation now uses `WorkspaceNode.Folder.containsAnyFilesystemItems`, which is populated by `LiveWorkspaceEnumerator` from real directory contents before hidden, unsupported, package, or skipped children are filtered from the visible snapshot.
- StoreKit product identifiers: code IDs match local `.storekit` IDs in the focused P0 test run. Tips are enabled after local device validation, but still require TestFlight evidence. Supporter is explicitly gated by `SettingsReleaseConfiguration.supporterPurchasesEnabled` and remains enabled for Sandbox/TestFlight validation; App Store submission remains blocked until product loading, purchase, restore, relaunch persistence, and revocation/missing-entitlement behavior are recorded.
- Release URLs: production URL force unwrap scan found no `URL(string: ...)!` in `Downward/`; one force-unwrapped URL remains in tests only.
- Privacy manifest static scan:
  - UserDefaults usage exists in bookmark/session/recent/theme/editor-appearance/supporter entitlement persistence and matches `NSPrivacyAccessedAPICategoryUserDefaults`.
  - File timestamp/resource-value usage exists in document versioning, workspace enumeration, and workspace validation and matches `NSPrivacyAccessedAPICategoryFileTimestamp`.
  - Pasteboard usage found: `MarkdownEditorTextViewCoordinator` writes to `UIPasteboard.general.string` for the user-initiated code-copy gesture. No pasteboard reads were found.
  - No static references were found for tracking/ad APIs, analytics/telemetry SDKs, network collection APIs, CoreLocation, camera capture, Photos library, microphone, or Contacts.
  - `print(` usage was found only in `DebugLogger`, guarded by `#if DEBUG`.

## Legal / Support URL Verification QA

Device:
OS:
Build:
Date:
Tester:

Rows to verify:
- Project URL in Settings/About: `https://secondvictor.com/public/projects/downward/downward.html`
- Privacy Policy URL in Settings/About and App Store Connect metadata: `https://secondvictor.com/public/projects/downward/downward-policy.html`
- Terms and Conditions URL in Settings/About: `https://secondvictor.com/public/projects/downward/downward-terms.html`
- App Store Connect Support URL:
- App Store Connect Marketing URL:

Steps:
- Open each URL from the installed release candidate where it is visible.
- Open the same URLs directly in Safari.
- Confirm every URL uses HTTPS, loads without authentication, and shows final Downward-specific content.
- Compare the Privacy Policy and Support URL against App Store Connect metadata.
- Confirm no placeholder, draft, or unrelated Second Victor page is linked from the release candidate.

Expected results:
- All visible legal/support/marketing links open successfully.
- App Store Connect metadata matches the app-visible privacy/support links.
- Any missing App Store Connect URL is filled before archive submission.

Result:
Evidence:
Notes:

## Release Identity Checklist

Status: manual App Store submission evidence still required.

- [ ] Bundle ID confirmed in Apple Developer/App Store Connect: `com.secondvictor.Downward`
- [ ] Marketing version confirmed: `1.0`
- [ ] Build number confirmed/incremented for submission: `1`
- [ ] Team ID confirmed: `7DHWCFL5P9`
- [ ] Signing mode confirmed for archive/export: project currently uses Automatic signing
- [ ] Supported devices confirmed: iPhone and iPad (`TARGETED_DEVICE_FAMILY = 1,2`)
- [ ] iPhone orientations confirmed: portrait
- [ ] iPad orientations confirmed: portrait, portrait upside down, landscape left, landscape right
- [ ] Archive created from a clean commit
- [ ] Archive validation passed
- [ ] App Store/TestFlight export/upload completed
- [ ] App Store Connect privacy answers match `Downward/PrivacyInfo.xcprivacy`
- [ ] Legal/support/marketing URLs open and match App Store metadata

## Manual File Save / Provider Failure QA

Device:
OS:
Build:
Workspace provider: Local Files / iCloud Drive / other:
Date:
Tester:

Steps:
- Install the release candidate on a real iPhone or iPad.
- Choose a local Files workspace containing a small Markdown file.
- Open the file, type for at least 30 seconds, then wait for autosave.
- Force quit and relaunch.
- Confirm the workspace and last document restore, and the typed text is still on disk.
- Repeat the same flow in an iCloud Drive workspace.
- While editing an iCloud Drive file, toggle Airplane Mode or otherwise make iCloud unavailable if safely reproducible.
- Type a change and wait for autosave.
- Confirm failed saves keep the editor dirty, show a clear save failure, and do not show a saved state.
- Restore connectivity and confirm a later save writes the latest editor buffer.

Expected results:
- Normal saves remain quiet.
- Failed saves keep the editor buffer dirty and do not report saved.
- No editor text is lost when backgrounding, force quitting, or restoring connectivity.

Result:
Evidence:
Notes:

## StoreKit Sandbox / TestFlight QA

Device:
OS:
Build:
Storefront:
Sandbox Apple ID:
Date:
Tester:

Products to verify:
- Supporter visible when `SettingsReleaseConfiguration.supporterPurchasesEnabled` is true: `com.secondvictor.downward.supporter`
- Tips visible after local device validation; TestFlight still pending: `com.secondvictor.downward.tip.small`, `com.secondvictor.downward.tip.medium`, `com.secondvictor.downward.tip.large`, `com.secondvictor.downward.tip.xlarge`

Steps:
- Install a TestFlight or sandbox-ready build.
- Launch fresh with no prior Supporter entitlement.
- Open Settings > Supporter.
- Confirm the Supporter product loads with the expected localized name and price.
- Tap purchase and complete the Sandbox purchase.
- Confirm premium themes/fonts unlock immediately.
- Force quit and relaunch.
- Confirm premium themes/fonts remain unlocked.
- Tap Restore Purchases.
- Confirm restored state remains correct.
- Revoke/refund the sandbox transaction if available, or use StoreKit/TestFlight tooling to simulate missing entitlement.
- Relaunch and run Restore Purchases.
- Confirm explicit restore/revocation handling does not incorrectly re-unlock revoked purchases.
- Confirm Tips row is visible in Settings for this release build.
- Confirm each Tip product loads with the expected localized name and price.
- Complete a Sandbox/TestFlight purchase for each Tip tier or record any tier intentionally deferred.
- If any Supporter product-loading, purchase, restore, relaunch persistence, or revocation/missing-entitlement check fails, set `supporterPurchasesEnabled` to `false` before App Store submission and rerun Settings visibility tests.

Expected results:
- Supporter success, cancellation, pending, restore, and revocation/missing-entitlement paths are recorded.
- Tips remain visible only if TestFlight product loading and purchase behavior are recorded before App Store submission.
- Supporter is hidden before App Store submission if TestFlight product readiness is not proven.

Result:
Evidence:
Notes:

## VoiceOver Core Workflow QA

Device:
OS:
Build:
Date:
Tester:

Steps:
- Enable VoiceOver.
- Launch fresh with no workspace selected.
- Select a workspace folder from Files.
- Navigate the browser, expand/collapse a folder, and open a document.
- Type text in the editor and confirm save/failure indicators are announced meaningfully.
- Use the editor toolbar/accessory controls that are visible on the device.
- Trigger a conflict/missing-file recovery flow if practical.
- Open Settings, Supporter, Theme settings, About, and workspace settings.
- Confirm destructive delete actions announce the same permanent-delete meaning as the visible copy.

Expected results:
- A VoiceOver user can complete the core workspace/open/edit/save/settings flow without unlabeled critical controls.
- Critical destructive and purchase actions have clear labels/hints.

Result:
Evidence:
Notes:

## Dynamic Type Critical Screens QA

Device:
OS:
Build:
Date:
Tester:

Steps:
- Set Dynamic Type to largest accessibility size.
- Check workspace browser, editor, Settings home, Supporter page, Theme settings, About, delete dialogs, and save failure chrome.
- Rotate iPad through supported orientations.

Expected results:
- Text does not overlap or become clipped in critical workflows.
- Buttons and dialogs remain understandable and tappable.

Result:
Evidence:
Notes:

## Large-File Editor Benchmark QA

Device:
OS:
Build:
Date:
Tester:

Steps:
- Create or import supported text files at approximately 4.9 MB, 5.0 MB, and 5.1 MB.
- Open the 4.9 MB file.
- Open the 5.0 MB file.
- Attempt to open the 5.1 MB file.
- In the largest allowed file, scroll, type near the top and bottom, and wait for autosave.
- Background/foreground and force quit/relaunch.

Expected results:
- Files at or below 5 MB open.
- Files above 5 MB refuse before loading, with clear copy explaining the 5 MB limit.
- The largest allowed file remains usable enough for 1.0 and saves without data loss.

Result:
Evidence:
Notes:

## Restore / Conflict Resolution QA

Device:
OS:
Build:
Workspace provider:
Date:
Tester:

Steps:
- Choose a workspace and open a document.
- Type and allow autosave.
- Force quit and relaunch; confirm workspace and document restore.
- Edit the same file outside Downward while the editor is clean; foreground Downward.
- Confirm clean external changes reload calmly.
- Edit the same file outside Downward while Downward has dirty unsaved edits; foreground Downward.
- Confirm local dirty text stays authoritative and no routine autosave conflict prompt appears.
- Delete or rename the open file outside Downward; foreground Downward.
- Confirm missing/moved file recovery is clear and no text is silently discarded.

Expected results:
- Restore uses workspace-relative identity.
- Own saves do not self-conflict.
- Dirty editor text is not clobbered by late external refreshes.

Result:
Evidence:
Notes:
