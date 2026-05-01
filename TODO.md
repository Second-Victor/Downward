# TODO.md — Downward App Store Readiness Review

Reviewed: 2026-05-01  
Repository: `Second-Victor/Downward`  
Branch: `main`  
Latest reviewed commit: `409ad5333f43e488b04ff12462d475c6cbccbc06` (`pi fixes`)  
Review type: static source review from GitHub. Xcode, Simulator, real-device QA, archive validation, TestFlight, and App Store Connect checks still need to be run locally.

## How to use this TODO

Use this as the release-fix queue for Codex and manual QA.

Priority meanings:

- **P0**: Release blocker or serious App Store submission risk.
- **P1**: Should fix before 1.0 if time allows; safe to defer only with an explicit release decision.
- **P2**: Post-release hardening or maintainability.

Codex rules:

- Work one checkbox at a time.
- Keep each PR/sweep small.
- Add or update tests for code changes.
- Do not mark an item complete until its acceptance checks pass.
- Record build/test/device evidence in `RELEASE_QA.md`.

---

## Current strengths to preserve

- [x] Scene-local app containers are used so each `WindowGroup` scene owns its own navigation/editor state.
- [x] Workspace selection, restore, refresh, and mutation are routed through domain/coordinator layers rather than raw view-level file operations.
- [x] Browser/search/recent-file opens prefer workspace-relative identity instead of raw URL-only routing.
- [x] File mutations use a workspace trust boundary and coordinated file operations.
- [x] Delete actions already use confirmation dialogs and disable full-swipe destructive delete.
- [x] StoreKit support exists for a non-consumable Supporter unlock and consumable tips.
- [x] A privacy manifest exists and declares no collected data / no tracking.
- [x] The editor uses a UIKit/TextKit bridge, which is appropriate for a serious Markdown editor.
- [x] Navigation bar title styling has a dedicated UIKit bridge; keep future chrome fixes narrow.

---

# P0 — Release blockers and App Store submission risks

## 1. Project, build, signing, and archive

### 1.1 Confirm the real minimum iOS target

Current project settings show `IPHONEOS_DEPLOYMENT_TARGET = 26.0` for project/app/test configurations. This may be intentional, but it is a major release decision.

- [x] Decide the actual minimum OS for 1.0: iOS/iPadOS 26.0 and later.
- [x] If `26.0` is intentional, record why in release notes and App Store metadata planning.
- [x] Earlier public iOS/iPadOS support is intentionally out of scope for 1.0, so no deployment-target setting changes are needed:
  - [x] Project-level Debug configuration remains `26.0`.
  - [x] Project-level Release configuration remains `26.0`.
  - [x] App target Debug configuration remains `26.0`.
  - [x] App target Release configuration remains `26.0`.
  - [x] Test target Debug configuration remains `26.0`.
  - [x] Test target Release configuration remains `26.0`.
- [x] No deployment-target change was made; current iPhone and iPad simulator suites already pass on iOS 26.4.
- [x] Verify every API used by the app is available for the chosen minimum OS, especially:
  - [x] SwiftUI navigation APIs.
  - [x] StoreKit 2 APIs.
  - [x] `registerForTraitChanges`.
  - [x] file importer / security-scoped bookmark APIs.
  - [x] privacy manifest packaging.

Acceptance checks:

- [x] `xcodebuild -list -project Downward.xcodeproj` succeeds.
- [x] Debug simulator build succeeds for iPhone.
- [x] Debug simulator build succeeds for iPad.
- [x] Release generic iOS build succeeds.
- [x] No availability warnings are introduced.

### 1.2 Create a clean release build/test/archive gate

- [ ] Delete DerivedData or build from a clean checkout.
- [x] Run the full XCTest suite on an iPhone simulator.
- [x] Run the full XCTest suite on an iPad simulator.
- [x] Run a Release configuration build.
- [ ] Archive the app in Xcode.
- [ ] Validate the archive in Xcode Organizer.
- [ ] Export an App Store/TestFlight build.
- [x] Install the exported build on a real iPhone.
- [x] Install the exported build on a real iPad if iPad support is shipping.
- [x] Record Xcode version, device/simulator names, OS versions, command lines, and pass/fail counts.

Suggested commands:

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

Acceptance checks:

- [x] All tests pass.
- [ ] Archive validation passes.
- [ ] Exported build launches on device.
- [ ] No unexpected console privacy/path logging appears in Release.

### 1.3 Verify release identity and App Store metadata readiness

Observed settings include bundle identifier `com.secondvictor.Downward`, marketing version `1.0`, build number `1`, signing team `7DHWCFL5P9`, iPhone portrait-only orientation, and iPad all orientations.

- [ ] Confirm `PRODUCT_BUNDLE_IDENTIFIER` is final.
- [ ] Confirm `MARKETING_VERSION` is final.
- [ ] Increment `CURRENT_PROJECT_VERSION` for every submitted build.
- [ ] Confirm signing team and provisioning profile are final.
- [ ] Confirm app category `public.app-category.productivity` is correct.
- [ ] Confirm iPhone portrait-only is intentional.
- [ ] Confirm iPad all-orientation support is intentional and manually tested.
- [ ] Confirm generated Info.plist contains every final App Store-visible key needed.
- [ ] Confirm app icon, display name, screenshots, subtitle, description, keywords, support URL, privacy URL, and terms URL are ready.

Acceptance checks:

- [ ] Archive uses distribution signing.
- [ ] Bundle ID matches App Store Connect.
- [ ] Version/build match the intended submission.
- [ ] App Store Connect metadata does not mention features hidden or broken in the build.

### 1.4 Restore one active release checklist/documentation source

The latest reviewed commit removed the previous root-level review/architecture docs. That may be intentional cleanup, but there should be one active release checklist that Codex and future-you can trust.

- [ ] Commit this file as `TODO.md` at the repo root.
- [x] Add or recreate `RELEASE_QA.md` if it is missing.
- [x] Use `RELEASE_QA.md` for dated build/test/device evidence.
- [ ] Keep `TODO.md` for open work only.
- [ ] Avoid multiple stale root-level checklist files with conflicting status.

Acceptance checks:

- [x] Root docs clearly show what is open and what is complete.
- [x] There is one place to record release QA evidence.
- [x] Codex can follow the checklist without needing historical deleted docs.

---

## 2. In-app purchases, Supporter unlock, and Tip Jar

Current source status:

- `SettingsReleaseConfiguration.current.tipsPurchasesEnabled` is `true`.
- The Settings home shows the Supporter row.
- The Tips row is visible when tips are enabled.
- Supporter unlock product ID: `com.secondvictor.downward.supporter`.
- Tip product IDs:
  - `com.secondvictor.downward.tip.small`
  - `com.secondvictor.downward.tip.medium`
  - `com.secondvictor.downward.tip.large`
  - `com.secondvictor.downward.tip.xlarge`
- `Downward.storekit` contains local StoreKit products, but local StoreKit configuration is not proof that App Store Connect products are ready.

### 2.1 Decide whether purchases ship in 1.0

- [x] Decide whether the Supporter unlock ships in 1.0.
- [x] Decide whether the Tip Jar ships in 1.0.
- [x] If Tip Jar is not fully ready, set `tipsPurchasesEnabled` to `false` in `SettingsReleaseConfiguration.current`.
- [x] If Supporter unlock is not fully ready, hide the Supporter purchase surface or make premium perks free until purchase infrastructure is ready.
- [x] If purchases ship, keep both purchase surfaces visible and complete all P0 purchase QA below.

Files:

- `Downward/Features/Settings/SettingsReleaseConfiguration.swift`
- `Downward/Features/Settings/SettingsHomePage.swift`
- `Downward/Features/Settings/SupporterUnlockSettingsPage.swift`
- `Downward/Features/Settings/TipsSettingsPage.swift`
- `Downward/Domain/Persistence/StoreKitThemeEntitlementStore.swift`
- `Downward/Domain/Persistence/TipJarManager.swift`
- `Downward/Downward.storekit`

Acceptance checks:

- [ ] A release reviewer never sees a visible non-functional purchase row.
- [ ] Product-unavailable states are intentional, polished, and rare.
- [ ] App Store metadata accurately describes paid perks and free functionality.

### 2.2 Verify App Store Connect product parity

For every StoreKit product in code/config:

- [ ] Create the matching product in App Store Connect.
- [ ] Confirm the product ID exactly matches code.
- [ ] Confirm product type matches code:
  - [ ] Supporter: non-consumable.
  - [ ] Tips: consumable.
- [ ] Confirm prices match intended pricing tiers.
- [ ] Confirm Supporter family sharing is intentional.
- [ ] Add required localizations, at minimum the storefronts planned for launch.
- [ ] Ensure products are cleared for review with the app submission.
- [ ] Ensure screenshots/review notes explain how to find the purchase screens.
- [ ] Add an App Review note that Supporter is optional and the app remains usable without purchase.

Acceptance checks:

- [ ] `Product.products(for:)` returns all expected products in Sandbox/TestFlight.
- [ ] Missing-product fallback is never seen in the intended release storefront.
- [ ] Product names/descriptions shown in-app match App Store Connect.

Sandbox evidence:

- [x] User verified purchases work with Sandbox on a real device.
- [ ] Record exact real device, OS version, sandbox account/storefront, and product IDs tested.
- [ ] Repeat purchase verification through TestFlight before release submission.

### 2.3 Add StoreKit automated coverage

Add tests with local StoreKit configuration where practical.

- [ ] Test Supporter product loading success.
- [ ] Test Supporter product missing/unavailable error copy.
- [ ] Test Supporter purchase success unlocks `ThemeStore.hasUnlockedThemes`.
- [ ] Test Supporter purchase cancellation leaves entitlement unchanged and no scary error.
- [ ] Test Supporter pending purchase surfaces a pending state.
- [ ] Test Supporter restore with existing entitlement.
- [ ] Test Supporter restore with no entitlement.
- [ ] Test Tip products load and sort by price.
- [ ] Test Tip purchase success calls finish and shows a thank-you state.
- [ ] Test Tip purchase cancellation returns to idle.
- [ ] Test Tip pending and failure states.
- [ ] Test transaction update handling for Supporter and tips.

Acceptance checks:

- [ ] StoreKit tests pass locally.
- [x] Manual Sandbox purchase pass completed on a real device.
- [ ] Manual Sandbox purchase pass matches tests after automated StoreKit tests exist.
- [ ] Manual TestFlight purchase pass matches tests.

### 2.4 Harden entitlement edge cases

`StoreKitThemeEntitlementStore` uses `Transaction.currentEntitlements` and `Transaction.updates`. That is the right direction, but release should explicitly cover entitlement state transitions.

- [ ] Ensure refunded/revoked non-consumable entitlements remove Supporter perks.
- [ ] Explicitly ignore revoked transactions where needed.
- [ ] Surface or log unverified entitlement failures in Debug without exposing private details in Release.
- [ ] Confirm premium theme/font fallback does not happen prematurely while entitlements are still loading.
- [ ] Confirm custom theme selection falls back to Adaptive only after entitlement resolution, not during a temporary StoreKit load delay.
- [ ] Confirm imported custom fonts are hidden/disabled when Supporter is absent.
- [ ] Confirm already-selected custom fonts/themes reappear after restore.

Acceptance checks:

- [ ] Fresh install with no purchase shows built-in free features only.
- [ ] Purchase unlocks premium themes and custom fonts without restart.
- [ ] Restore unlocks premium themes and custom fonts without restart.
- [ ] Simulated revocation removes locked selections cleanly.
- [ ] No user loses a saved custom theme file when entitlement is absent.

### 2.5 Polish purchase UI copy and symbols

Current issues found in purchase UI:

- `TipsSettingsPage` footer says `maintainance`; should be `maintenance`.
- Success alert button says `You're Welcome`; this reads as if the app is thanking itself.
- The highest tip row uses `wineglass.fill`, which may distract from a productivity app and imply alcohol.

Tasks:

- [x] Change `maintainance` to `maintenance`.
- [x] Change success alert button to `Done`, `Thanks`, or `Close`.
- [x] Replace `wineglass.fill` with a neutral symbol such as `heart.fill`, `sparkles`, `gift.fill`, or `fork.knife`.
- [x] Review Supporter copy capitalization: `The App works great without it` should likely be `The app works great without it`.
- [x] Ensure purchase buttons use accessible labels that include product name and price.
- [x] Ensure loading and unavailable copy is calm and review-friendly.

Acceptance checks:

- [x] No typos in purchase screens.
- [ ] VoiceOver announces product name, description, price, and button role.
- [x] Purchase failure and unavailable states are understandable.

---

## 3. File safety, workspace trust boundary, and Files provider behavior

Current source status:

- Workspace selection is transactional: bookmark persistence happens after a usable snapshot succeeds.
- Workspace operations are actor-backed and use security-scoped access.
- Mutations validate against the workspace root and use coordinated file operations.
- Workspace UI shows destructive confirmation dialogs before delete.
- Deletes ultimately call file removal, so the user-facing meaning of “Delete” must be clear.

### 3.1 Define and test workspace trust rules

Write down the exact rules and enforce them with tests.

- [x] Decide whether hidden files are shown or hidden.
- [x] Decide whether package directories are shown as folders or excluded.
- [x] Decide whether symlinks are shown, excluded, or treated as plain references.
- [x] Decide whether aliases/bookmarks inside the workspace are followed or ignored.
- [x] Decide whether binary/source/text files outside Markdown are openable.
- [x] Decide whether unsupported file types are hidden or shown disabled.
- [x] Document the behavior in `ARCHITECTURE.md`, `TODO.md`, or a dedicated workspace rules doc.

Acceptance checks:

- [x] Enumeration and mutation rules match.
- [x] Browser UI, search, recents, and editor routing all follow the same trust boundary.
- [x] Tests describe the expected behavior for hidden files, packages, symlinks, and unsupported files.

### 3.2 Add explicit symlink and path-escape tests

This is the most important file-safety hardening item.

- [x] Add a fixture where a symlink inside the workspace points outside the workspace.
- [x] Verify enumeration does not allow editing/deleting the outside target.
- [x] Verify opening a route through that symlink fails safely or treats the symlink as unsupported.
- [x] Verify rename/move/delete never follows a symlink outside the workspace root.
- [x] Add tests for `../` path attempts.
- [x] Add tests for percent-encoded or normalized paths that could resolve outside root.
- [x] Add tests for absolute paths passed into browser/recent/trusted editor routes.
- [x] Add tests for Unicode normalization path variants if file-system behavior can differ.

Likely files/tests:

- `WorkspaceRelativePath`
- `WorkspaceSnapshot`
- `WorkspaceSnapshotPathResolver`
- `LiveWorkspaceEnumerator`
- `LiveWorkspaceManager`
- `WorkspaceManagerRestoreTests`
- `MarkdownWorkspaceAppTrustedOpenAndRecentTests`

Acceptance checks:

- [x] No raw URL route can bypass workspace-relative validation.
- [x] No workspace mutation can operate outside the selected workspace.
- [x] Tests fail if containment validation is removed.

### 3.3 Reconfirm destructive delete UX

The UI currently confirms delete, but the message says “removes from the workspace.” Since file removal may be permanent for many providers, be explicit.

- [ ] Decide whether file/folder delete should be permanent.
- [ ] If supported by iOS/provider, consider moving to trash instead of permanent deletion.
- [ ] If delete remains permanent, update confirmation copy:
  - [ ] “Delete File” / “Delete Folder”.
  - [ ] “This permanently removes …”.
  - [ ] Mention folder contents for folders.
- [ ] Add a stronger confirmation for deleting non-empty folders.
- [ ] Ensure active open document state clears safely after deleting the active file.
- [ ] Ensure deleting a folder containing the active file closes or invalidates the editor safely.
- [ ] Add tests for active-file delete and active-parent-folder delete.

Acceptance checks:

- [ ] User cannot accidentally full-swipe delete.
- [ ] Confirmation copy accurately describes permanence.
- [ ] Active editor does not keep editing a deleted file.
- [ ] Recents/routes are pruned after delete.

### 3.4 Real-device Files provider QA

Simulator tests cannot prove security-scoped Files behavior.

- [ ] Fresh install starts with no selected workspace and no stale route state.
- [ ] Select a workspace from “On My iPhone/iPad.”
- [ ] Select a workspace from iCloud Drive.
- [ ] Select a workspace from a third-party Files provider if available.
- [ ] Relaunch and confirm restore succeeds without another picker prompt.
- [ ] Move/rename/remove the selected workspace externally and confirm reconnect UI appears.
- [ ] Reconnect to the same workspace and confirm recents/routes recover.
- [ ] Reconnect to a different workspace and confirm old recents/routes do not leak.
- [ ] Create a file and folder.
- [ ] Rename a file and folder.
- [ ] Move a file and folder.
- [ ] Delete a file and folder.
- [ ] Open a recent file after workspace restore.
- [ ] Pull to refresh after external file changes.
- [ ] Record provider names, devices, OS versions, and failures.

Acceptance checks:

- [ ] Security-scoped access persists after relaunch.
- [ ] Reconnect UI appears when expected.
- [ ] App never silently edits outside the selected workspace.

### 3.5 Case-only rename and Unicode rename QA

- [ ] Rename `Draft.md` to `draft.md` on device.
- [ ] Rename `Folder` to `folder` on device.
- [ ] Rename a file using accented characters.
- [ ] Rename a file using emoji.
- [ ] Confirm browser, recents, active editor route, and disk path update.
- [ ] Confirm the operation works on normal iOS/APFS storage.
- [ ] Add or update tests that skip only when the test volume cannot support the behavior.

Acceptance checks:

- [ ] Case-only rename does not no-op incorrectly.
- [ ] Unicode names do not break relative-path identity.
- [ ] Recent files remain usable after rename.

---

## 4. Autosave, document lifecycle, and conflict safety

### 4.1 Real-device autosave and lifecycle QA

The biggest user-trust risk is lost edits.

- [ ] Open a Markdown file, type quickly for at least 30 seconds, and verify autosave.
- [ ] Background the app immediately after typing and verify disk contents after relaunch.
- [ ] Lock/unlock the device while the editor is dirty.
- [ ] Switch documents rapidly while typing.
- [ ] Open the same file in another app/provider and modify it externally.
- [ ] Confirm conflict detection appears.
- [ ] Use “keep mine” and verify saved disk contents.
- [ ] Use “use disk version” and verify editor contents.
- [ ] Delete the file externally and confirm missing-file conflict UI.
- [ ] Move/rename the file externally and confirm safe behavior.
- [ ] Repeat on iCloud Drive and at least one local workspace.

Acceptance checks:

- [ ] No typed text is lost.
- [ ] Dirty local text is never silently overwritten by disk changes.
- [ ] Clean buffers refresh from disk as expected.
- [ ] Conflict UI is understandable.

### 4.2 Same-file multi-window behavior

The app creates scene-local containers, but each scene has a single active live document session. Multi-window same-file editing must be validated.

- [ ] Open the same file in two iPad windows.
- [ ] Save a clean duplicate window after the other window edits.
- [ ] Edit both windows before autosave and confirm conflict behavior.
- [ ] Confirm one window cannot silently clobber the other.
- [ ] Add tests or manual QA notes for dirty duplicate windows.
- [ ] Decide whether collaborative same-file editing is unsupported for 1.0 and document it if needed.

Acceptance checks:

- [ ] Same-file duplicate windows either work safely or clearly surface conflicts.
- [ ] No hidden overwrite path remains.

### 4.3 Save failure and provider latency UX

- [ ] Simulate provider unavailable during save.
- [ ] Simulate permission/access loss during save.
- [ ] Simulate very slow save or file coordination delay.
- [ ] Ensure editor shows persistent save/error state.
- [ ] Ensure save retry is clear.
- [ ] Ensure app does not mark a failed save as saved.
- [ ] Ensure backgrounding during a save resolves safely.

Acceptance checks:

- [ ] Failed saves are visible.
- [ ] Dirty state remains accurate.
- [ ] User can retry or preserve edits.

---

## 5. Editor, Markdown rendering, and large-file performance

### 5.1 Real-device large-document regression pass

This remains a required manual release gate.

- [ ] Open a 1,000+ line Markdown file with line numbers enabled.
- [ ] Open a 10,000+ line Markdown file with line numbers enabled.
- [ ] Scroll near the bottom, then quickly return to the top.
- [ ] Confirm the gutter never becomes a black bar.
- [ ] Confirm line numbers never disappear after returning to the top.
- [ ] Confirm hidden syntax does not overlap line numbers after blank lines.
- [ ] Toggle line numbers off/on after deep scrolling.
- [ ] Toggle larger heading text and confirm line number behavior is intentional.
- [ ] Repeat on real iPhone.
- [ ] Repeat on real iPad if iPad support is shipping.
- [ ] Capture screenshots/video for release QA evidence.

Acceptance checks:

- [ ] No visual corruption.
- [ ] No excessive memory growth.
- [ ] Typing remains usable.

### 5.2 Add measured performance baselines

- [ ] Create standard benchmark documents:
  - [ ] Small note.
  - [ ] 1k-line Markdown file.
  - [ ] 10k-line Markdown file.
  - [ ] Stress file with headings, tasks, links, code fences, blockquotes, hidden syntax.
- [ ] Record first render time.
- [ ] Record typing latency near top/middle/bottom.
- [ ] Record scroll smoothness with line numbers on/off.
- [ ] Record memory usage during deep scroll.
- [ ] Add results to `RELEASE_QA.md`.
- [ ] Keep performance tests deterministic enough to detect regressions without making CI flaky.

Acceptance checks:

- [ ] A future Codex change can be compared to a baseline.
- [ ] Large-file regressions are caught before release.

### 5.3 Formatter, selection, undo/redo device QA

- [ ] Bold command works with selected text and empty selection.
- [ ] Italic command works with selected text and empty selection.
- [ ] Strikethrough command works.
- [ ] Inline code command works.
- [ ] Heading command works across line selections.
- [ ] Task command works and toggles correctly.
- [ ] Link command works.
- [ ] Image command works.
- [ ] Quote command works.
- [ ] Code block command works.
- [ ] Unordered list command works.
- [ ] Ordered list command works.
- [ ] Selection is preserved or intentionally moved after every command.
- [ ] Repeated undo/redo does not corrupt text or hidden syntax.
- [ ] Hardware keyboard editing remains natural.

Acceptance checks:

- [ ] No formatter corrupts the raw Markdown buffer.
- [ ] Undo/redo state matches user expectations.
- [ ] Selection changes are predictable.

### 5.4 Harden Markdown link/image parsing edge cases

- [ ] Add tests for destinations containing encoded parentheses.
- [ ] Add tests for labels containing escaped brackets.
- [ ] Add tests for empty destinations.
- [ ] Add tests for whitespace around destinations.
- [ ] Add tests for image alt text edge cases.
- [ ] Add tests for nested emphasis inside links if styled.
- [ ] Decide whether unsupported Markdown link shapes remain plain text or partially styled.
- [ ] Ensure external URL schemes remain allow-listed.
- [ ] Ensure relative links route only through workspace-local resolution.

Acceptance checks:

- [ ] `javascript:` and `file:` external URLs remain blocked.
- [ ] Relative Markdown links cannot escape the workspace.
- [ ] Unsupported Markdown shapes fail harmlessly.

---

## 6. UI consistency, navigation, and visual chrome

### 6.1 Navigation bar and rounded title consistency

Current source uses a hidden UIKit controller to reapply rounded navigation title fonts across lifecycle and Dynamic Type changes. This is a reasonable workaround, but it needs manual QA.

- [ ] Verify rounded title style on workspace root.
- [ ] Verify rounded title style on editor.
- [ ] Verify rounded title style on settings root.
- [ ] Verify rounded title style on nested settings pages.
- [ ] Verify rounded title style in iPad split sidebar.
- [ ] Verify rounded title style in iPad detail navigation stack.
- [ ] Verify after push/pop transitions.
- [ ] Verify after changing Dynamic Type.
- [ ] Verify after changing light/dark mode.
- [ ] Verify after switching app theme/chrome preferences.

Acceptance checks:

- [ ] No default-title font flashes persist after transitions.
- [ ] Navigation title color remains readable.
- [ ] Navigation bar background is not accidentally reset.

### 6.2 Theme/chrome readability pass

- [ ] Test dark editor theme while app appearance is light.
- [ ] Test light editor theme while app appearance is dark.
- [ ] Test adaptive/system theme in light mode.
- [ ] Test adaptive/system theme in dark mode.
- [ ] Test “match system chrome to theme” enabled.
- [ ] Test “match system chrome to theme” disabled.
- [ ] Confirm iPhone status bar readability.
- [ ] Confirm iPhone navigation/title readability.
- [ ] Confirm iPad sidebar/detail readability.
- [ ] Confirm keyboard accessory follows expected editor theme.
- [ ] Confirm selected text and caret contrast.

Acceptance checks:

- [ ] Every built-in theme has readable chrome.
- [ ] System UI does not become invisible against custom editor backgrounds.
- [ ] Theme changes do not require relaunch.

### 6.3 Launch/restore shell behavior

Current launch code delays the restore spinner by 300ms and shows a slow message after 1.8s.

- [ ] Verify fast restore moves straight to content without a distracting flash.
- [ ] Verify slow restore shows spinner after delay.
- [ ] Verify very slow restore shows “Still restoring workspace…”.
- [ ] Verify failed restore shows the failure state, not the quiet shell.
- [ ] Verify invalid workspace shows reconnect UI.
- [ ] Verify no workspace shows “Choose a Workspace.”
- [ ] Verify restored editor back-pop does not trigger layout/title glitches.
- [ ] Verify device launch from cold start and warm start.

Acceptance checks:

- [ ] Restore UI feels intentional.
- [ ] No blank screen persists.
- [ ] The real workspace shell is mounted only when safe.

### 6.4 Settings polish and consistency

- [ ] Review all Settings row names for consistent capitalization.
- [ ] Ensure “Supporter,” “Tips,” “Extra Themes,” and “Custom Fonts” copy explains what is free vs paid.
- [ ] Ensure locked features explain why they are locked without sounding broken.
- [ ] Ensure unavailable StoreKit states do not look like app bugs.
- [ ] Ensure all buttons have consistent placement and destructive styling.
- [ ] Ensure settings sheets look correct on compact iPhone and regular iPad.
- [ ] Ensure `Done` dismisses settings reliably in compact and regular layouts.
- [ ] Ensure reconnect/clear workspace actions in Settings are not confused with editor actions.

Acceptance checks:

- [ ] Settings reads like a finished product, not a debug surface.
- [ ] User can discover paid perks, legal links, and workspace management without confusion.

---

## 7. Accessibility and inclusive UX

### 7.1 VoiceOver pass

- [ ] Navigate launch/no-workspace screen with VoiceOver.
- [ ] Navigate workspace browser with VoiceOver.
- [ ] Verify file rows announce file/folder state clearly.
- [ ] Verify expanded/collapsed folder state is understandable.
- [ ] Verify Settings rows announce title and current value.
- [ ] Verify editor accessory buttons have useful labels and hints.
- [ ] Verify formatter buttons announce enabled/disabled state.
- [ ] Verify task checkboxes are understandable and tappable.
- [ ] Verify purchase buttons announce product name, description, and price.
- [ ] Verify alerts and conflict screens announce enough detail.

Acceptance checks:

- [ ] A VoiceOver user can select a workspace, open a file, edit, save, and use Settings.
- [ ] No critical button is announced only as an icon.

### 7.2 Dynamic Type and layout pass

- [ ] Test Settings at large accessibility sizes.
- [ ] Test workspace rows at large accessibility sizes.
- [ ] Test editor chrome at large accessibility sizes.
- [ ] Test purchase screens at large accessibility sizes.
- [ ] Test conflict/reconnect alerts at large accessibility sizes.
- [ ] Confirm line-number gutter behavior with larger editor fonts.
- [ ] Confirm toolbar/accessory controls do not clip.
- [ ] Confirm iPad split view remains usable at large sizes.

Acceptance checks:

- [ ] No important text clips.
- [ ] Controls remain tappable.
- [ ] Scroll containers allow all content to be reached.

---

## 8. Privacy, legal, and App Store review surfaces

Current manifest declares UserDefaults and file timestamp accessed API reasons, no collected data, and no tracking. Recheck this against actual code before submission.

### 8.1 Verify legal URLs and About page

Current release configuration includes project, privacy policy, and terms URLs.

- [ ] Open Website URL from About.
- [ ] Open Privacy Policy URL from About.
- [ ] Open Terms & Conditions URL from About.
- [ ] Confirm URLs are live, final, HTTPS, and not placeholder pages.
- [ ] Confirm legal pages mention local file access and StoreKit purchases accurately.
- [ ] Confirm privacy page matches the privacy manifest.
- [ ] Confirm App Store Connect privacy URL matches the in-app URL.
- [ ] Confirm support URL is available and listed in metadata.

Acceptance checks:

- [ ] App Review can reach privacy/terms/support links.
- [ ] Links do not 404, redirect strangely, or expose staging content.

### 8.2 Recheck privacy manifest against actual code

- [ ] Re-scan code for all required reason APIs.
- [ ] Confirm file timestamp access reason covers document/workspace metadata usage.
- [ ] Confirm UserDefaults reason covers app preferences/session/bookmarks as applicable.
- [ ] Confirm no crash analytics, telemetry, ad tracking, or network analytics are present.
- [ ] Confirm StoreKit usage does not require collected-data declarations beyond Apple purchase processing.
- [ ] Confirm imported fonts/themes are app-local and not uploaded.
- [ ] Confirm debug logging remains no-op in Release.

Acceptance checks:

- [ ] Privacy manifest matches real code.
- [ ] App Store privacy questionnaire matches the manifest and actual app behavior.

### 8.3 Rate the App behavior

Current configuration disables Rate the App because no App Store review URL is configured.

- [ ] Keep Rate the App hidden until the final App Store app ID exists.
- [ ] After the app ID exists, configure the final App Store write-review destination.
- [ ] Add a release configuration test for hidden vs visible Rate row.
- [ ] Ensure the row opens the review URL and does not use an unavailable placeholder.

Acceptance checks:

- [ ] No dead rating row appears in the 1.0 build.
- [ ] When enabled, the rating row opens the correct App Store review destination.

---

## 9. Testing, QA evidence, and CI

### 9.1 Rebuild test coverage around current release risks

- [ ] Add tests for StoreKit product loading and purchase state.
- [ ] Add tests for entitlement resolution and locked theme fallback.
- [ ] Add tests for tips enabled/disabled release configuration.
- [x] Add tests for symlink/path escape handling.
- [x] Add tests for active-file delete and active-folder delete.
- [x] Add tests for workspace restore after invalid bookmark.
- [x] Add tests for slow/fast restore shell behavior.
- [ ] Add tests for navigation bar appearance preservation.
- [ ] Add tests for Settings legal/rating visibility.

Acceptance checks:

- [x] P0 bug fixes have tests.
- [ ] Tests fail before the relevant fix when possible.

### 9.2 Add a small CI workflow if missing

- [x] Add GitHub Actions workflow for build/test on macOS if not already present.
- [x] Use a stable Xcode version matching release.
- [x] Run at least one simulator test destination.
- [x] Cache nothing risky at first.
- [x] Keep workflow simple and reliable.
- [x] Add a separate manual archive checklist rather than trying to automate App Store signing immediately.

Acceptance checks:

- [ ] PRs show a build/test signal.
- [ ] CI does not replace real-device QA, but catches basic regressions.

### 9.3 Maintain `RELEASE_QA.md`

For each release build, record:

- [ ] Git commit.
- [x] Xcode version.
- [ ] Build number.
- [x] Simulator names and OS versions.
- [ ] Real device names and OS versions.
- [x] Commands run.
- [x] XCTest pass/fail count.
- [x] StoreKit Sandbox purchase result.
- [ ] StoreKit TestFlight purchase result.
- [ ] Files provider results.
- [ ] Large document results.
- [ ] Accessibility results.
- [ ] Archive validation result.
- [x] Known deferred issues.

Acceptance checks:

- [ ] Anyone can see why the build is ready to submit.
- [ ] Deferred issues have an explicit owner and rationale.

---

# P1 — Should fix soon, but safe to defer only with a decision

## 10. Documentation and architecture clarity

### 10.1 Recreate a compact architecture map

Because `ARCHITECTURE.md` was removed, add a short current architecture note.

- [x] Document app layers:
  - [x] `App`
  - [x] `Domain`
  - [x] `Infrastructure`
  - [x] `Features`
  - [x] `Shared`
  - [x] `Tests`
- [x] Document the one-workspace model.
- [x] Document the one-active-document-per-scene model.
- [x] Document workspace-relative identity.
- [x] Document StoreKit entitlement ownership.
- [x] Document the file trust boundary.
- [x] Document where Codex should make future changes.

Acceptance checks:

- [x] New contributors/Codex can avoid pushing file logic into views.
- [x] Architecture doc is current and short enough to maintain.

### 10.2 Split large files after release risk drops

Do not destabilize 1.0 for this unless a bug fix naturally extracts code.

- [ ] Split `WorkspaceManager` into selection/restore, snapshot/enumeration, mutation, and path validation collaborators.
- [ ] Split `AppCoordinator` into launch/restore, document loading, mutation orchestration, and recent-file/session persistence collaborators.
- [ ] Split `WorkspaceViewModel` prompt state from mutation command routing.
- [ ] Continue extracting from `MarkdownEditorTextViewCoordinator`.
- [ ] Keep pure policy seams:
  - [ ] `WorkspaceMutationPolicy`
  - [ ] `WorkspaceNavigationPolicy`
  - [ ] `WorkspaceSessionPolicy`

Acceptance checks:

- [ ] Each extraction has focused tests.
- [ ] Public behavior does not change.
- [ ] Files become easier to review.

---

## 11. Theme and custom font UX

### 11.1 Theme export behavior

- [ ] Decide whether new unsaved themes should be exportable.
- [ ] If yes, show export for drafts and test it.
- [ ] If no, make UI copy clear that export is for saved themes only.
- [ ] Add QA coverage for import/export/share flows.
- [ ] Confirm locked users cannot import/edit/export custom themes but can still use free built-in themes.
- [ ] Confirm a user’s custom theme data is preserved when locked.

Acceptance checks:

- [ ] Users understand what requires Supporter.
- [ ] Theme data is not lost.

### 11.2 Imported font behavior

- [ ] Verify `.ttf` import.
- [ ] Verify `.otf` import.
- [ ] Verify multi-face family import.
- [ ] Verify missing bold/italic face handling.
- [ ] Verify deleting an imported family removes app-owned files and metadata.
- [ ] Verify fonts re-register on launch.
- [ ] Verify custom fonts lock/unlock with Supporter entitlement.
- [ ] Verify line numbers with imported fonts behave intentionally.

Acceptance checks:

- [ ] Imported font UI is reliable.
- [ ] Locked entitlement does not delete imported files.
- [ ] Editor falls back gracefully.

---

# P2 — Post-release hardening

## 12. Product quality improvements

- [ ] Add SwiftFormat or SwiftLint with a very small non-disruptive rule set.
- [ ] Add string catalog/localization plan if non-English support is planned.
- [ ] Add UI/snapshot tests for Settings and navigation if visual regressions recur.
- [ ] Add intentional crash/error reporting or document the privacy-first no-telemetry stance.
- [ ] Add optional onboarding/sample document only if it does not complicate Files workspace ownership.
- [ ] Document unsupported Markdown features.
- [ ] Profile search performance for very large workspaces.
- [ ] Consider content search only after workspace indexing/trust rules are designed.
- [ ] Consider multiple live document sessions only after the single-session model is redesigned.
- [ ] Consider collaborative same-file editing only after explicit conflict strategy is designed.

---

# Final release sign-off checklist

Do not submit to App Store until every P0 item is complete or explicitly deferred with a written release decision.

- [ ] `TODO.md` is committed and open items are current.
- [ ] `RELEASE_QA.md` contains automated test evidence for the exact release commit.
- [ ] `RELEASE_QA.md` contains real-device manual QA evidence.
- [ ] Deployment target is final.
- [ ] Signing/provisioning/archive validation is complete.
- [ ] StoreKit products are ready or purchase UI is hidden.
- [ ] Legal/privacy URLs are live and final.
- [ ] Privacy manifest matches actual code.
- [ ] Files provider flows are verified on real devices.
- [ ] Autosave/conflict/lifecycle flows are verified on real devices.
- [ ] Large-document editor behavior is verified on real devices.
- [ ] Keyboard accessory/formatter/undo/redo flows are verified on real devices.
- [ ] Theme/chrome readability is verified on real devices.
- [ ] Accessibility has had at least one manual pass.
- [ ] No new feature work starts until the release blockers are closed.
