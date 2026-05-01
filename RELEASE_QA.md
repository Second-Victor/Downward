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

- Earlier full-suite iPad attempts on iPad Pro 13-inch (M5) and iPad Air 11-inch (M4) hit CoreSimulator launch failures, including `NSMachErrorDomain Code=-308` and `FBSOpenApplicationServiceErrorDomain Code=1` / Busy preflight failures. A final full-suite run on iPad (A16) completed successfully after running outside the sandbox.
- The only build warnings observed were AppIntents metadata extraction notices for a target without AppIntents and a CoreImage asset catalog runtime message; no new deployment-target availability warnings were observed.

### Still Pending For Release

- Archive validation and App Store/TestFlight export.
- Real-device iPhone/iPad install and Files-provider QA.
- StoreKit Sandbox/TestFlight purchase verification.
- Accessibility and large-document manual passes.
