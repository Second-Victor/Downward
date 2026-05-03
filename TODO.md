# Project Review TODO

Reviewed: 2026-05-02
Scope: static review of `Downward/`, `Tests/`, project settings, root docs, StoreKit configuration, privacy manifest, and existing release QA notes.

## Executive Summary

Downward has a strong foundation: the app has a clear folder-based product model, a real workspace-relative trust boundary, a UIKit/TextKit editor bridge where it matters, and a healthy XCTest suite around many file-safety and editor behaviors. The biggest release risks are not from obvious missing architecture, but from a few high-impact areas that need proof on real devices: Files provider behavior, direct in-place saves, destructive delete wording/protection, StoreKit product readiness, entitlement edge cases, archive/signing, and privacy/legal evidence.

The biggest maintainability issue is file size and responsibility density. Several files are understandable only after reading a lot of surrounding code: `MarkdownEditorTextViewCoordinator.swift`, `WorkspaceManager.swift`, `AppCoordinator.swift`, `WorkspaceViewModel.swift`, `EditorViewModel.swift`, `EditorSettingsPage.swift`, `WorkspaceFolderScreen.swift`, and `ThemeEditorSettingsPage.swift`. The user-facing SwiftUI views should be made more pleasant to edit by extracting focused sections, view state structs, and shared row/action components without changing behavior.

This TODO is intentionally a backlog, not a completion report. Do not mark items complete until the acceptance criteria are true and any required evidence is added to `RELEASE_QA.md`.

## Priority Key

- P0: Critical issue that could cause data loss, crashes, broken purchases, broken file access, App Store rejection, privacy/security problems, or serious user harm.
- P1: Important issue that affects maintainability, user experience, reliability, architecture, or future development.
- P2: Nice-to-have cleanup, polish, simplification, consistency improvement, or future-proofing.

## Highest Priority Fixes

- [ ] P0: Verify file save/delete/restore behavior on real iPhone and iPad with local Files and iCloud Drive.
- [x] P0: Add a document size policy before opening arbitrary supported text/source files.
- [x] P0: Make destructive delete copy explicit and add stronger protection for non-empty folder deletion.
- [ ] P0: Prove StoreKit products and purchases in Sandbox/TestFlight, or hide incomplete purchase surfaces.
- [ ] P0: Complete archive validation, export, signing, and App Store Connect product/legal/privacy evidence.
- [ ] P1: Split the largest user-facing SwiftUI views into focused sections and components.
- [ ] P1: Split the largest coordination/editor bridge files along existing responsibility boundaries.
- [ ] P1: Add cleanup/deinit paths for model-owned tasks and observers where missing.

## 1. File Safety and Data Persistence

- [x] P0: Define and enforce a large-document open policy
  - File path(s): `Downward/Domain/Document/PlainTextDocumentSession.swift`, `Downward/Domain/Workspace/SupportedFileType.swift`, `Downward/Features/Editor/EditorScreen.swift`, `Tests/DocumentManagerTests.swift`
  - Problem: `readUTF8TextContents(from:)` reads the full file into memory, while `SupportedFileType` allows many text/source/log-like files that may be very large.
  - Why it matters: Opening a huge log, JSON, CSV, or source dump can stall the UI, spike memory, or terminate the app on device.
  - Suggested fix: Add a max-size policy before full `Data(contentsOf:)` reads. For files above the limit, show a calm refusal or warning flow. Keep the threshold documented and covered by tests.
  - Acceptance criteria: Oversized files do not load into memory, the user sees clear copy, normal files still open, and tests cover below-limit, at-limit, and above-limit files.
  - P0 pass note: Completed on 2026-05-02. Added a 5 MB `DocumentOpenPolicy`, enforced it before full UTF-8 reads, rejected unverifiable file sizes calmly, and added below-limit, at-limit, above-limit, and missing-size tests. Targeted document tests passed on iPhone 17 simulator.

- [ ] P0: Validate direct in-place saves under provider failure and latency
  - File path(s): `Downward/Domain/Document/PlainTextDocumentSession.swift`, `Tests/EditorAutosaveTests.swift`, `RELEASE_QA.md`
  - Problem: Saves intentionally write directly to the coordinated file URL without an additional temp-file replacement step.
  - Why it matters: This may be the right Files-provider tradeoff, but provider failures or interruptions could leave a partial/truncated file depending on the provider.
  - Suggested fix: Keep the current approach unless device evidence proves it unsafe, but add failure/latency tests or fakes around `writeUTF8Data`, and run real-device QA on local Files and iCloud Drive.
  - Acceptance criteria: Failed saves keep the editor dirty, do not report `.saved`, surface a useful error, and `RELEASE_QA.md` records provider-specific save behavior.
  - P0 pass note: Partially completed on 2026-05-02. Added automated direct write failure coverage with a read-only file, plus editor autosave failure assertions for dirty state and error copy. Real-device Local Files/iCloud/provider latency evidence is still required, so this remains unchecked.

- [x] P0: Make delete confirmation copy explicitly permanent
  - File path(s): `Downward/Features/Workspace/WorkspaceFolderScreen.swift`, `Downward/Features/Workspace/WorkspaceViewModel.swift`, `Downward/Domain/Workspace/WorkspaceManager.swift`
  - Problem: Delete messages say an item is removed "from the workspace," while `LiveWorkspaceManager.deleteFile(at:)` calls `FileManager.removeItem`.
  - Why it matters: Users may think files are only removed from Downward's browser, not deleted from the real Files provider.
  - Suggested fix: Change delete copy to say "permanently deletes" or "deletes from Files" where true. Mention that folder deletion includes contents.
  - Acceptance criteria: File and folder dialogs accurately describe the destructive operation, accessibility hints match the visible copy, and tests or UI assertions cover the final strings.
  - P0 pass note: Completed on 2026-05-02. Added shared delete confirmation presentation copy that explicitly says items are permanently deleted from Files and the underlying workspace, and tests cover file/folder strings and accessibility hints.

- [x] P0: Add stronger confirmation for non-empty folder deletion
  - File path(s): `Downward/Features/Workspace/WorkspaceFolderScreen.swift`, `Downward/Features/Workspace/WorkspaceViewModel.swift`, `Downward/Domain/Workspace/WorkspaceNode.swift`, `Tests/MarkdownWorkspaceAppMutationFlowTests.swift`
  - Problem: Empty and non-empty folders use the same one-step destructive confirmation.
  - Why it matters: A folder tree can contain many real user files. A single tap after opening a context menu is too easy to regret.
  - Suggested fix: Detect non-empty folders from the snapshot and require either a second confirmation, typed folder name, or a clearly stronger dialog.
  - Acceptance criteria: Empty folder deletion remains quick, non-empty folder deletion requires stronger confirmation, active editor/recents/routes are correct after deleting a parent folder, and tests cover both paths.
  - P0 pass note: Completed on 2026-05-02. Non-empty folders now use stronger title, message, destructive button, and accessibility hint naming folder contents; existing active-document and ancestor-folder delete cleanup tests passed. Follow-up completed on 2026-05-03: folder non-empty detection now records real filesystem contents before filtering visible/supported children, so folders containing only hidden or unsupported items still get the stronger warning. Focused enumerator and delete-presentation tests passed.

- [ ] P1: Add a file-operation policy type for create/rename/move/delete naming rules
  - File path(s): `Downward/Domain/Workspace/WorkspaceManager.swift`, `Tests/WorkspaceManagerRestoreTests.swift`
  - Problem: Filename normalization, duplicate naming, extension preservation, move destination validation, and case-only rename helpers all live inside `WorkspaceManager.swift`.
  - Why it matters: The manager is already over 1,500 lines, and file-safety rules are hard to review when mixed with bookmark restore and snapshot loading.
  - Suggested fix: Extract pure helpers into `WorkspaceMutationNamePolicy` and `WorkspaceMoveValidationPolicy` or similar domain types.
  - Acceptance criteria: `WorkspaceManager` remains the mutation owner, pure policy tests still pass, and the extracted files can be understood without reading workspace restore code.

- [ ] P1: Add a size policy for imported custom fonts
  - File path(s): `Downward/Domain/Persistence/ImportedFontManager.swift`, `Downward/Features/Settings/EditorSettingsPage.swift`, `Tests/ImportedFontManagerTests.swift`
  - Problem: Font import checks file extension but not file size before copy and CoreText metadata extraction.
  - Why it matters: Large or malformed font files can waste storage, stall import, or make CoreText work harder than expected.
  - Suggested fix: Add a maximum imported font size, check attributes before copy, and present calm user-facing copy for oversize files.
  - Acceptance criteria: Oversize fonts are rejected before copy, valid fonts still import, and tests cover oversize, valid, duplicate, and malformed font files.

- [ ] P1: Record case-only rename coverage on a case-insensitive volume
  - File path(s): `Downward/Domain/Workspace/WorkspaceManager.swift`, `Tests/WorkspaceManagerRestoreTests.swift`, `RELEASE_QA.md`
  - Problem: Case-only rename support exists, but CI/local runs may skip coverage on case-sensitive volumes.
  - Why it matters: iOS/APFS user storage is a key target, and case-only renames are easy to regress.
  - Suggested fix: Run the relevant tests or manual QA on a suitable device/volume and record evidence.
  - Acceptance criteria: File and folder case-only rename are proven on a real target, and skipped automated tests explain why they skipped.

- [ ] P1: Make restorable session persistence failures more observable in Debug
  - File path(s): `Downward/App/AppCoordinator.swift`, `Downward/Domain/Persistence/SessionStore.swift`, `Downward/Infrastructure/Logging/DebugLogger.swift`
  - Problem: Session-store save/clear failures are intentionally ignored with Debug logging only.
  - Why it matters: That is calm for users, but debugging launch restore problems later may be difficult.
  - Suggested fix: Add structured debug diagnostics for restorable session load/save/clear without surfacing noisy UI.
  - Acceptance criteria: Release remains quiet, Debug logs include enough context to diagnose bad session data, and no file path privacy leak is introduced in Release.

## 2. In-App Purchases / StoreKit / Entitlements

- [ ] P0: Prove App Store Connect product parity before shipping visible purchase surfaces
  - File path(s): `Downward/Domain/Persistence/StoreKitThemeEntitlementStore.swift`, `Downward/Domain/Persistence/TipJarManager.swift`, `Downward/Downward.storekit`, `RELEASE_QA.md`
  - Problem: Code references one Supporter product and four Tip products. The local `.storekit` file is not proof that App Store Connect/TestFlight products load.
  - Why it matters: Missing or mismatched products can break visible purchase screens and create App Review risk.
  - Suggested fix: Verify every product ID in Sandbox/TestFlight, or hide purchase surfaces until verified.
  - Acceptance criteria: `Product.products(for:)` returns every intended product in the release environment, product type/pricing/localization match App Store Connect, and `RELEASE_QA.md` records device, storefront, account type, and product IDs.
  - P0 pass note: Partially completed on 2026-05-02. Centralized product identifiers and temporarily disabled the Tips row until Tip readiness was tested. Added a local `.storekit` parity test.
  - 2026-05-03 note: Focused P0 tests, including `StoreProductIdentifiersTests`, passed on the iPhone 17 simulator. Supporter visibility is now controlled by `SettingsReleaseConfiguration.supporterPurchasesEnabled`; Supporter and Tips are intentionally enabled after local device testing. App Store Connect/TestFlight product-loading evidence is still required, so this remains unchecked.

- [ ] P0: Add StoreKit automated or controlled-device coverage for Supporter unlock
  - File path(s): `Downward/Domain/Persistence/StoreKitThemeEntitlementStore.swift`, `Tests/ThemeStoreTests.swift`, `Downward/Downward.storekit`
  - Problem: Existing tests cover local cache/entitlement state helpers, but not full StoreKit product loading, purchase result, restore, pending, cancellation, or revocation with `SKTestSession`.
  - Why it matters: Recent regressions involved entitlement timing and persistence. This flow needs guardrails.
  - Suggested fix: Add StoreKit tests where practical, or add a repeatable manual device script in `RELEASE_QA.md` if framework limits block automation.
  - Acceptance criteria: Purchase success unlocks themes/fonts, relaunch preserves access, cancellation leaves state unchanged, restore works, no-entitlement restore shows calm copy, and revocation behavior is documented.
  - P0 pass note: Manual Sandbox/TestFlight script added to `RELEASE_QA.md` on 2026-05-02. This remains unchecked until the script is run on device/TestFlight or equivalent StoreKit automation is added and passing.

- [ ] P0: Decide and document the offline revocation tradeoff for Supporter access
  - File path(s): `Downward/Domain/Persistence/StoreKitThemeEntitlementStore.swift`, `Downward/App/AppContainer.swift`, `RELEASE_QA.md`
  - Problem: Launch intentionally keeps the cached Supporter unlock when StoreKit is temporarily quiet, while explicit restore/revocation paths may clear it.
  - Why it matters: This protects paying users from false lockouts, but refunds/revocations while the app is closed may not clear immediately.
  - Suggested fix: Keep the current user-friendly behavior unless device testing proves a stronger signal is safe. Document the policy and test transaction updates plus Restore Purchases.
  - Acceptance criteria: Paid users are not relocked on ordinary relaunch, StoreKit updates do not re-unlock revoked purchases, explicit restore can clear missing entitlements, and the tradeoff is written down.
  - P0 pass note: Existing code policy was documented in `RELEASE_QA.md` StoreKit script expectations on 2026-05-02. This remains unchecked until revocation/missing-entitlement behavior is verified with StoreKit Sandbox/TestFlight.

- [ ] P1: Add a dedicated pending state for Tip Jar purchases
  - File path(s): `Downward/Domain/Persistence/TipJarManager.swift`, `Downward/Features/Settings/TipsSettingsPage.swift`, `Tests/SettingsScreenModelTests.swift`
  - Problem: `.pending` is mapped to `.failed("Purchase is pending approval.")`.
  - Why it matters: Ask-to-Buy and pending approvals are not failures; presenting them as failures is confusing.
  - Suggested fix: Add `PurchaseState.pending(String?)` or similar, render a neutral pending alert/state, and test it.
  - Acceptance criteria: Pending tips show pending copy, not failure copy, and resetting the pending state behaves like success/failure alerts.

- [ ] P1: Map StoreKit and persistence errors to calm app copy
  - File path(s): `Downward/Domain/Persistence/StoreKitThemeEntitlementStore.swift`, `Downward/Domain/Persistence/TipJarManager.swift`, `Downward/Domain/Persistence/ThemeStore.swift`, `Downward/Domain/Persistence/ImportedFontManager.swift`
  - Problem: Several purchase and persistence paths expose `error.localizedDescription` directly.
  - Why it matters: StoreKit/localized system strings can be technical, inconsistent, or scary in user-facing purchase UI.
  - Suggested fix: Add small error mappers for purchase load, purchase failure, restore failure, verification failure, font import, and theme persistence. Keep detailed diagnostics Debug-only.
  - Acceptance criteria: Common errors have product-quality copy, user cancellation stays quiet, and tests cover representative error mappings.

- [ ] P1: Centralize StoreKit product identifiers and release toggles
  - File path(s): `Downward/Domain/Persistence/StoreKitThemeEntitlementStore.swift`, `Downward/Domain/Persistence/TipJarManager.swift`, `Downward/Features/Settings/SettingsReleaseConfiguration.swift`, `Downward/Downward.storekit`
  - Problem: Product IDs are hard-coded in separate StoreKit managers and release surfaces are configured separately.
  - Why it matters: Product ID drift is an App Store failure mode and makes TestFlight checks harder.
  - Suggested fix: Add a small `StoreKitProductCatalog` or release configuration namespace used by both managers and tests.
  - Acceptance criteria: Each product ID is defined once, tests assert catalog IDs match `.storekit`, and Settings release toggles are easy to audit.

- [ ] P1: Make purchase managers more testable without real `Product`
  - File path(s): `Downward/Domain/Persistence/StoreKitThemeEntitlementStore.swift`, `Downward/Domain/Persistence/TipJarManager.swift`, `Tests/ThemeStoreTests.swift`
  - Problem: Live StoreKit calls are directly embedded in the managers, limiting unit coverage for result handling.
  - Why it matters: Purchase state machines should be testable without relying only on StoreKit integration tests.
  - Suggested fix: Introduce minimal closure seams or tiny adapters for product loading, purchase execution, transaction updates, and current entitlements.
  - Acceptance criteria: Unit tests can simulate success, pending, cancellation, unverified transaction, missing product, restore/no restore, and revoked transactions.

## 3. SwiftUI Views and UI Maintainability

- [ ] P1: Split `EditorSettingsPage` into focused settings sections
  - File path(s): `Downward/Features/Settings/EditorSettingsPage.swift`
  - Problem: The page owns font category state, built-in font options, custom font import, custom font detail sheets, line number controls, bindings, deletion, and helper copy in one 700+ line file.
  - Why it matters: Small visual changes to a Settings row require scanning import and persistence behavior.
  - Suggested refactor: Keep `EditorSettingsPage` as composition only. Extract `BuiltInFontSection`, `ImportedFontsSection`, `EditorFontSizeSection`, `LineNumberSettingsSection`, `HeadingTextSettingsSection`, and `ReopenLastDocumentSection`.
  - Suggested target structure: `Features/Settings/Editor/EditorSettingsPage.swift`, `EditorFontSection.swift`, `ImportedFontsSection.swift`, `EditorDisplaySections.swift`, `ImportedFontDetailSheet.swift`, `SettingsFontOption.swift`.
  - Acceptance criteria: `EditorSettingsPage.body` is a short list of sections, import/delete logic is isolated, and previews cover locked/unlocked fonts, imported families, line numbers disabled by larger headings, and error state.

- [ ] P1: Move `ThemeEditorSettingsPage` draft state into a model
  - File path(s): `Downward/Features/Settings/ThemeEditorSettingsPage.swift`
  - Problem: The view owns more than ten color `@State` properties, draft construction, contrast checks, export filenames, save state, and UI layout.
  - Why it matters: Theme editing is visually sensitive; editing one color row or preview layout is harder than it should be.
  - Suggested refactor: Add `ThemeEditorDraft` with fields, bindings, contrast, `makeTheme`, and export filename helpers. Extract `ThemeEditorPreviewHeader`, `ThemeColorListSection`, `ThemeContrastWarningRow`, and `ThemeEditorToolbar`.
  - Suggested target structure: `Features/Settings/ThemeEditor/ThemeEditorSettingsPage.swift`, `ThemeEditorDraft.swift`, `ThemeEditorPreviewHeader.swift`, `ThemeColorListSection.swift`, `ThemeEditorExport.swift`.
  - Acceptance criteria: The page body reads top-to-bottom, color fields are data-driven, save/export logic is testable without SwiftUI, and previews cover new/edit/locked/low-contrast states.

- [ ] P1: Remove duplicated row action UI from `WorkspaceFolderScreen`
  - File path(s): `Downward/Features/Workspace/WorkspaceFolderScreen.swift`
  - Problem: File/folder context menus, swipe actions, delete dialogs, and navigation variants duplicate similar action definitions.
  - Why it matters: Future changes to Delete, Rename, or Move copy/styling can easily update one path but miss another.
  - Suggested refactor: Extract `WorkspaceRowActions`, `WorkspaceDeleteConfirmation`, and a row container that receives `WorkspaceRowActionSet` from the view model.
  - Suggested target structure: `Features/Workspace/WorkspaceFolderScreen.swift`, `WorkspaceTreeRows.swift`, `WorkspaceTreeRow.swift`, `WorkspaceRowActions.swift`, `WorkspaceDeleteConfirmation.swift`.
  - Acceptance criteria: Context menu and swipe action behavior remain identical, delete copy is defined once, and stack/split navigation differences are isolated.

- [ ] P1: Split purchase rendering from purchase actions in `SupporterUnlockSettingsPage`
  - File path(s): `Downward/Features/Settings/SupporterUnlockSettingsPage.swift`
  - Problem: The page mixes marketing copy, theme preview lookup, StoreKit load/purchase/restore tasks, unlock state, and bottom purchase bar.
  - Why it matters: Paywall-like UI needs careful copy and state handling; coupling the view to StoreKit actions makes visual tweaking risky.
  - Suggested refactor: Add `SupporterUnlockViewState` and extract `SupporterIntroSection`, `SupporterThemePreviewSection`, `SupporterBenefitsSection`, `SupporterRestoreSection`, and `SupporterPurchaseBar`.
  - Suggested target structure: `Features/Settings/Supporter/SupporterUnlockSettingsPage.swift`, `SupporterUnlockViewState.swift`, `SupporterSections.swift`, `SupporterPurchaseBar.swift`.
  - Acceptance criteria: The view can be previewed in loading, unavailable, locked, purchasing, restored, and purchased states without live StoreKit.

- [ ] P1: Make `TipsSettingsPage` render a simple view state
  - File path(s): `Downward/Features/Settings/TipsSettingsPage.swift`, `Downward/Domain/Persistence/TipJarManager.swift`
  - Problem: The view directly reads StoreKit `Product` values and purchase state, decides loading/empty/error/success UI, and starts purchase tasks.
  - Why it matters: Tips are low-risk financially but high-risk for App Review polish.
  - Suggested refactor: Add `TipJarViewState` or formatter helpers for rows, alerts, and accessibility labels. Keep live `Product` purchase behind manager methods.
  - Suggested target structure: `Features/Settings/Tips/TipsSettingsPage.swift`, `TipProductRow.swift`, `TipJarViewState.swift`.
  - Acceptance criteria: Loading, empty, product list, purchasing, pending, success, and failed states are previewable/testable.

- [ ] P1: Extract editor chrome bridge code out of `EditorScreen`
  - File path(s): `Downward/Features/Editor/EditorScreen.swift`
  - Problem: `EditorScreen` includes the actual editor layout plus status/navigation bar UIKit bridge types.
  - Why it matters: Editor layout and system chrome behavior are separate concerns and both are fragile.
  - Suggested refactor: Move `EditorStatusBarChromeConfigurator`, `EditorStatusBarChromeViewController`, and view extensions into `EditorSystemChrome.swift`.
  - Suggested target structure: `Features/Editor/EditorScreen.swift`, `EditorContentView.swift`, `EditorSavedDateHeader.swift`, `EditorSystemChrome.swift`.
  - Acceptance criteria: `EditorScreen` remains the routing/composition view, chrome bridge has dedicated tests or previews where practical, and behavior is unchanged.

- [ ] P1: Replace unused custom Settings component layer or adopt it consistently
  - File path(s): `Downward/Features/Settings/SettingsComponents.swift`, `Downward/Features/Settings/*.swift`
  - Problem: `SettingsShell`, `SettingsPageHeader`, `SettingsCard`, `SettingsNavigationRow`, `SettingsStepperRow`, `SettingsToggleRow`, and related types appear unused while actual settings pages use native `Form`/`List`.
  - Why it matters: Dead or abandoned UI systems confuse future visual work.
  - Suggested refactor: Either delete unused components after verifying no previews/tests need them, or intentionally migrate a small subset if they are the preferred design system.
  - Suggested target structure: Keep only shared components actively used by settings pages, such as `SettingsHomeLabel`, `ThemePreviewSwatch`, and footer styling.
  - Acceptance criteria: No unused settings component remains, and Settings visual conventions are documented by actual code rather than dormant alternatives.

- [ ] P2: Make `PaletteColorPicker` easier to test and tweak
  - File path(s): `Downward/Features/Settings/PaletteColorPicker.swift`
  - Problem: Color conversion, swatch data, selected grid state, hex validation, and brightness control live in one view file.
  - Why it matters: Theme editing is likely to receive visual tweaks, and color math should be testable.
  - Suggested refactor: Extract `PaletteColor`, `PaletteSwatchSet`, and hex conversion helpers into pure types. Keep `PaletteColorPicker` focused on layout.
  - Suggested target structure: `PaletteColorPicker.swift`, `PaletteColorPickerModel.swift`, `PaletteSwatches.swift`, `HexColorField.swift`.
  - Acceptance criteria: Hex parsing/formatting has tests, invalid hex UI remains clear, and swatch/brightness interactions are previewable.

- [ ] P2: Bring `AboutSettingsPage` into the Settings visual system
  - File path(s): `Downward/Features/Settings/AboutSettingsPage.swift`
  - Problem: About uses a full-screen gradient and force-unwrapped company URL while other settings use `Form`/`List` styling.
  - Why it matters: It may feel disconnected from the rest of Settings and is harder to adapt to Dynamic Type.
  - Suggested refactor: Use a small About header plus grouped rows for website, privacy, terms, version, and company. Replace force unwrap with a static optional or validated configuration.
  - Suggested target structure: `AboutSettingsPage.swift`, `AboutHeader.swift`, `AboutLinkRows.swift`.
  - Acceptance criteria: About works at large Dynamic Type, links are reachable, and there are no force unwraps for URLs.

## 4. Architecture and State Management

- [ ] P1: Add `deinit` cleanup to `EditorViewModel`
  - File path(s): `Downward/Features/Editor/EditorViewModel.swift`, `Tests/EditorAutosaveTests.swift`
  - Problem: `EditorViewModel` owns `autosaveTask`, `flushSaveTask`, `loadTask`, `conflictResolutionTask`, `focusRevalidationTask`, `documentObservationTask`, and a notification observer, but has no cleanup path.
  - Why it matters: Scene teardown or model replacement can leave tasks/observers alive longer than intended.
  - Suggested fix: Add `isolated deinit` that cancels all model-owned tasks and removes the observer. Add a focused lifecycle test or debug instrumentation.
  - Acceptance criteria: All tasks are canceled on deinit, the notification observer is removed, and tests/diagnostics verify observation cleanup.

- [ ] P1: Add `deinit` cleanup to `RootViewModel`
  - File path(s): `Downward/Features/Root/RootViewModel.swift`
  - Problem: `RootViewModel` owns `restorePresentationTask` and has no deinit cancellation.
  - Why it matters: Delayed restore UI updates can retain or mutate a root model after scene teardown.
  - Suggested fix: Add `isolated deinit { restorePresentationTask?.cancel() }`.
  - Acceptance criteria: Restore presentation task is canceled when the root model deinitializes, and no delayed spinner update happens after teardown.

- [ ] P1: Split `MarkdownEditorTextViewCoordinator` by behavior cluster
  - File path(s): `Downward/Features/Editor/MarkdownEditorTextViewCoordinator.swift`
  - Problem: The coordinator is over 2,000 lines and owns rendering, selection, viewport anchoring, gestures, task toggles, link opening, code copying, keyboard accessory commands, formatting, undo registration, and scroll header state.
  - Why it matters: Editor bugs are hard to isolate, and future human edits risk accidental regressions.
  - Suggested fix: Extract focused collaborators such as `EditorRenderScheduler`, `EditorViewportCoordinator`, `MarkdownGestureController`, `MarkdownFormattingCommandController`, and `EditorKeyboardAccessoryCoordinator`.
  - Acceptance criteria: The representable coordinator remains the delegate/composition point, each extracted type has focused tests where practical, and no editing behavior changes.

- [ ] P1: Split `AppCoordinator` along existing policies
  - File path(s): `Downward/App/AppCoordinator.swift`, `Downward/App/WorkspaceNavigationPolicy.swift`, `Downward/App/WorkspaceSessionPolicy.swift`, `Downward/App/WorkspaceMutationPolicy.swift`
  - Problem: `AppCoordinator` still owns launch restore, workspace refresh, mutation application, document loading/saving, recent-file pruning, navigation state, and session persistence.
  - Why it matters: The policy seams are good, but the coordinator remains the hardest app-level file to edit.
  - Suggested fix: Extract `WorkspaceRestoreCoordinator`, `DocumentPresentationCoordinator`, and `WorkspaceMutationResultApplier` as concrete collaborators only where they reduce file size and testing cost.
  - Acceptance criteria: Public app behavior is unchanged, policy tests remain green, and mutation/navigation result handling can be reviewed in smaller files.

- [ ] P1: Split `WorkspaceManager` into restore, snapshot, mutation, and validation helpers
  - File path(s): `Downward/Domain/Workspace/WorkspaceManager.swift`
  - Problem: Bookmark restore, snapshot loading, create/rename/move/delete, name normalization, path validation, file coordination, and stubs are in one file.
  - Why it matters: This file is central to data safety, so it should be easy to review in small, named pieces.
  - Suggested fix: Move pure mutation naming/validation helpers and `LiveWorkspaceFileCoordinator` into separate files first. Keep the actor as the single owner of selected workspace state.
  - Acceptance criteria: No new abstractions without payoff, tests still target the same behavior, and file-safety logic is easier to audit.

- [ ] P1: Split `WorkspaceViewModel` prompt/action state from tree/search state
  - File path(s): `Downward/Features/Workspace/WorkspaceViewModel.swift`
  - Problem: The view model owns loading, refreshing, search, expansion, create/rename/delete/move prompt state, recent files, and mutation command routing.
  - Why it matters: Browser UI changes currently require reading lots of unrelated action state.
  - Suggested fix: Extract `WorkspacePromptState`, `WorkspaceExpansionState`, and `WorkspaceMoveDestinationBuilder` as value/helper types.
  - Acceptance criteria: `WorkspaceViewModel` remains the UI model, but prompt copy/state and move destination construction can be tested separately.

- [ ] P1: Audit unstructured `Task` ownership in views and models
  - File path(s): `Downward/Features/**/*.swift`, `Downward/App/*.swift`, `Downward/Domain/Persistence/*.swift`
  - Problem: Many view button handlers start `Task { ... }`; some are appropriate fire-and-forget actions, but ownership is not always obvious.
  - Why it matters: Async work can outlive the view that triggered it, and future changes may accidentally apply stale results.
  - Suggested fix: Classify each task as view-owned, model-owned, app-owned, or explicit fire-and-forget. Add short comments only where stale-result suppression lives elsewhere.
  - Acceptance criteria: Long-running UI tasks either cancel with owner lifetime or are generation-gated by a coordinator/store.

## 5. Navigation and App Flow

- [ ] P1: Reduce duplicate compact/regular settings presentation code
  - File path(s): `Downward/Features/Root/RootScreen.swift`
  - Problem: Compact and regular shells both build nearly identical `SettingsScreen` sheets and bindings.
  - Why it matters: Future changes to Settings injection or dismissal can drift between iPhone and iPad.
  - Suggested fix: Extract a `SettingsSheet` view/modifier that receives `RootViewModel` and handles the binding once.
  - Acceptance criteria: Compact and regular Settings presentation still work, but settings dependencies are wired in one place.

- [ ] P1: Add manual QA for restored-editor navigation transitions
  - File path(s): `Downward/Features/Root/RootScreen.swift`, `Downward/App/WorkspaceNavigationPolicy.swift`, `RELEASE_QA.md`
  - Problem: Restore shell logic intentionally mounts workspace content behind the loading shell to avoid navigation title/list glitches.
  - Why it matters: This is subtle UI state that can regress after navigation changes.
  - Suggested fix: Add a release QA script for cold launch restore into editor, back navigation, compact/regular layout changes, and settings presentation.
  - Acceptance criteria: `RELEASE_QA.md` includes screenshots/notes for restored editor on iPhone and iPad.

- [ ] P1: Document same-file multi-window behavior
  - File path(s): `AGENTS.md`, `ARCHITECTURE.md`, `RELEASE_QA.md`, `Downward/App/AppContainer.swift`
  - Problem: Each scene has one active document session, but same-file editing across multiple iPad windows is a release-sensitive scenario.
  - Why it matters: Two windows can represent independent scenes and need clear conflict behavior.
  - Suggested fix: Manually test same-file edits across two windows. Document supported behavior or known limitations.
  - Acceptance criteria: Duplicate-window edits either conflict safely or are explicitly unsupported for 1.0 with user-safe behavior.

## 6. Error Handling and User Feedback

- [ ] P1: Replace generic file operation fallback messages with action-specific recovery
  - File path(s): `Downward/App/WorkspaceMutationErrorPresenter.swift`, `Downward/Domain/Errors/ErrorReporter.swift`, `Downward/Domain/Workspace/WorkspaceManager.swift`
  - Problem: Some file operation failures collapse into generic "could not be created/renamed/moved/deleted" copy.
  - Why it matters: Users need to know whether to reconnect the workspace, choose a different name, wait for iCloud, or retry.
  - Suggested fix: Preserve more error categories from validation/coordination where useful, while keeping raw filesystem details out of Release UI.
  - Acceptance criteria: Common failures have actionable copy, tests cover at least duplicate name, unsupported extension, inaccessible workspace, missing file, and provider failure.

- [ ] P1: Avoid user-facing raw localized errors from import/export flows
  - File path(s): `Downward/Features/Settings/ThemeEditorSettingsPage.swift`, `Downward/Features/Settings/ThemeSettingsPage.swift`, `Downward/Domain/Persistence/ImportedFontManager.swift`, `Downward/Domain/Persistence/ThemeImportErrorFormatter.swift`
  - Problem: Some theme export and font import paths append `error.localizedDescription` directly.
  - Why it matters: System errors can be technical and inconsistent with the rest of the app.
  - Suggested fix: Add small mappers for cancelled, permission denied, unreadable, invalid file, too large, and save/export failure.
  - Acceptance criteria: User-facing import/export errors are calm and consistent, while Debug logs preserve details.

- [ ] P1: Make conflict resolution actions safer and more descriptive
  - File path(s): `Downward/Features/Editor/ConflictResolutionView.swift`, `Downward/Features/Editor/EditorViewModel.swift`
  - Problem: The conflict sheet has three important actions but no preview of current vs disk text.
  - Why it matters: "Reload From Disk" and "Overwrite Disk" can lose one side of a conflict if the user misunderstands.
  - Suggested fix: Add clearer explanatory copy and consider showing metadata or short previews for "Your edits" and "Disk version" before destructive resolution.
  - Acceptance criteria: Users can understand what each action keeps/discards, and VoiceOver announces the same intent.

- [ ] P2: Replace force-unwrapped static URLs
  - File path(s): `Downward/Features/Settings/AboutSettingsPage.swift`
  - Problem: `companyURL` is force-unwrapped from a string literal.
  - Why it matters: It is low crash risk, but it violates the repo style and sets a pattern.
  - Suggested fix: Move URLs into `SettingsReleaseConfiguration` or use a non-optional validated static initializer pattern that fails tests instead of production.
  - Acceptance criteria: Production code has no URL force unwraps.

## 7. Performance

- [ ] P0: Measure large-file editor behavior on device
  - File path(s): `Downward/Features/Editor/MarkdownEditorTextViewCoordinator.swift`, `Downward/Features/Editor/LineNumberGutterView.swift`, `Tests/MarkdownRendererPerformanceTests.swift`, `RELEASE_QA.md`
  - Problem: Renderer performance tests exist, but release evidence does not include real-device first render, typing, scroll, and memory baselines.
  - Why it matters: Large markdown/source files are plausible for this app, and simulator performance is not enough.
  - Suggested fix: Create standard benchmark documents and record device measurements for line numbers on/off, hidden syntax on/off, and larger headings.
  - Acceptance criteria: `RELEASE_QA.md` includes device, OS, file sizes, timing/memory notes, and any acceptable limits.
  - P0 pass note: Manual benchmark script added to `RELEASE_QA.md` on 2026-05-02. This remains unchecked until real-device measurements are recorded.

- [ ] P1: Harden Markdown link parsing beyond the simple regex
  - File path(s): `Downward/Features/Editor/MarkdownStyledTextRenderer.swift`, `Downward/Features/Editor/MarkdownSyntaxScanner.swift`, `Tests/MarkdownStyledTextRendererTests.swift`, `Tests/MarkdownLocalLinkResolverTests.swift`
  - Problem: Link/image styling uses simple regular expressions that do not cover escaped brackets, nested/encoded parentheses, empty destinations, or many valid Markdown link shapes.
  - Why it matters: Hidden syntax ranges, tap targets, and local/external routing can become wrong.
  - Suggested fix: Move link/image recognition into scanner-style tokenization or add a small parser for balanced destinations and escaped labels.
  - Acceptance criteria: Tests cover escaped labels, encoded/nested parentheses, whitespace, empty destinations, images, unsupported shapes, and blocked schemes.

- [ ] P1: Profile workspace search on large trees
  - File path(s): `Downward/Features/Workspace/WorkspaceSearchEngine.swift`, `Downward/Features/Workspace/WorkspaceViewModel.swift`, `Tests/WorkspaceSearchTests.swift`
  - Problem: Search updates synchronously from snapshot/query changes.
  - Why it matters: A large workspace may make search typing feel sticky.
  - Suggested fix: Add measured tests/QA for large snapshots. If needed, debounce search or move search computation off the main actor with stale-result suppression.
  - Acceptance criteria: Search remains responsive on a large synthetic workspace and tests cover stale query/snapshot updates.

## 8. Accessibility

- [ ] P0: Complete a VoiceOver pass for core workflows
  - File path(s): `Downward/Features/Root`, `Downward/Features/Workspace`, `Downward/Features/Editor`, `Downward/Features/Settings`, `RELEASE_QA.md`
  - Problem: There is no recorded end-to-end VoiceOver pass for launch, browser, editor, settings, purchases, and conflict UI.
  - Why it matters: App Store readiness and basic usability require critical workflows to be navigable without sight.
  - Suggested fix: Run and record a manual VoiceOver pass. Fix any icon-only or unclear controls found.
  - Acceptance criteria: A VoiceOver user can select/reconnect a workspace, open/edit a file, use formatter/accessory controls, resolve a conflict, and manage settings/purchases.
  - P0 pass note: Manual VoiceOver script added to `RELEASE_QA.md` on 2026-05-02. Delete accessibility hints found during this pass were updated. This remains unchecked until the device VoiceOver pass is complete.

- [ ] P1: Improve accessibility labels for color and theme controls
  - File path(s): `Downward/Features/Settings/PaletteColorPicker.swift`, `Downward/Features/Settings/ThemeSettingsPage.swift`, `Downward/Features/Settings/ThemeEditorSettingsPage.swift`
  - Problem: Swatches and theme color rows are visual-first and may not announce color values or selected state clearly.
  - Why it matters: Theme editing should be understandable with VoiceOver and Switch Control.
  - Suggested fix: Add labels/values such as color property name, hex value, selected state, and action.
  - Acceptance criteria: VoiceOver announces each color row/swatch with name, value, and selected state.

- [ ] P1: Complete Dynamic Type pass for Settings and editor chrome
  - File path(s): `Downward/Features/Settings/*.swift`, `Downward/Features/Editor/*.swift`, `Downward/Features/Workspace/*.swift`, `RELEASE_QA.md`
  - Problem: There are previews for some large type cases, but no complete recorded pass.
  - Why it matters: Settings, purchase bars, row metadata, and editor toolbar controls can clip at accessibility sizes.
  - Suggested fix: Test large accessibility Dynamic Type on iPhone and iPad. Add previews for the most complex settings pages.
  - Acceptance criteria: No critical text clips, all controls remain reachable, and screenshots/notes are in `RELEASE_QA.md`.

## 9. App Store Readiness

- [ ] P0: Complete archive validation and TestFlight export
  - File path(s): `Downward.xcodeproj/project.pbxproj`, `RELEASE_QA.md`
  - Problem: Existing evidence is simulator-heavy; archive validation and export remain unproven for the current commit.
  - Why it matters: Signing, provisioning, App Store metadata, privacy manifests, and StoreKit products can fail after code freeze.
  - Suggested fix: Archive in Xcode, validate in Organizer, export/upload to TestFlight, install on real devices, and record exact identity.
  - Acceptance criteria: `RELEASE_QA.md` records Xcode version, commit hash, marketing/build version, signing mode, archive validation, export/upload result, and device launch result.
  - P0 pass note: Release identity checklist added to `RELEASE_QA.md` on 2026-05-02. This remains unchecked until archive validation/export/TestFlight upload are actually performed.

- [ ] P0: Confirm purchase surfaces are either fully ready or hidden
  - File path(s): `Downward/Features/Settings/SettingsReleaseConfiguration.swift`, `Downward/Features/Settings/SettingsHomePage.swift`, `Downward/Features/Settings/SupporterUnlockSettingsPage.swift`, `Downward/Features/Settings/TipsSettingsPage.swift`
  - Problem: Supporter, Tips, and Rate the App are visible in current configuration. App Store/TestFlight purchase and rating readiness still need final proof before submission.
  - Why it matters: Visible nonfunctional purchase/rating surfaces can frustrate users and risk review issues.
  - Suggested fix: Keep visible only after StoreKit/TestFlight and App Store ID evidence is recorded; otherwise disable release flags.
  - Acceptance criteria: A release reviewer never sees a placeholder or missing-product purchase/rating surface.
  - P0 pass note: Tips were hidden by release configuration on 2026-05-02, then re-enabled on 2026-05-03 after local device testing. Supporter and Tips still require Sandbox/TestFlight/App Store Connect evidence, so this remains unchecked.
  - 2026-05-03 note: Added an explicit Supporter release gate in `SettingsReleaseConfiguration` and added settings model assertions for it. Current configuration keeps Supporter and Tips visible for purchase validation builds; flip purchase visibility off before App Store submission if TestFlight product loading, purchase, restore, and relaunch persistence are not proven. A post-edit generic simulator build passed, but the post-edit XCTest rerun was blocked by simulator preflight `Busy`, so manual/TestFlight evidence remains required.

- [ ] P0: Verify legal, privacy, support, and marketing URLs
  - File path(s): `Downward/Features/Settings/SettingsReleaseConfiguration.swift`, `Downward/Features/Settings/AboutSettingsPage.swift`, `RELEASE_QA.md`
  - Problem: URLs exist in configuration, but live/final App Store evidence is not recorded.
  - P0 pass note: Removed a production force-unwrapped URL on 2026-05-02 and added URL verification to `RELEASE_QA.md`. This remains unchecked until live URL/App Store metadata evidence is recorded.
  - Why it matters: App Review requires reachable privacy/support metadata and consistent privacy disclosures.
  - Suggested fix: Open each URL, verify HTTPS/final content, and compare to App Store Connect metadata.
  - Acceptance criteria: `RELEASE_QA.md` records website, privacy, terms, support URL, status, and final App Store Connect values.

- [ ] P1: Decide whether iPhone portrait-only orientation is intentional
  - File path(s): `Downward.xcodeproj/project.pbxproj`, `RELEASE_QA.md`
  - Problem: iPhone supports portrait only, while iPad supports all orientations.
  - Why it matters: Hardware keyboard and landscape editing on iPhone may be expected by some users.
  - Suggested fix: Confirm this is a product decision or enable landscape on iPhone and test the editor/settings layouts.
  - Acceptance criteria: Orientation choice is documented and tested; App Store screenshots/metadata match the supported orientation.

- [ ] P1: Add or correct CI workflow status
  - File path(s): `.github/workflows/*.yml`, `RELEASE_QA.md`
  - Problem: No `.github` workflow directory is present.
  - Why it matters: PRs and future maintenance lack a basic automated build/test signal.
  - Suggested fix: Add a small GitHub Actions workflow for `xcodebuild test` on a stable macOS/Xcode image, or explicitly document no CI for 1.0.
  - Acceptance criteria: PRs show at least one build/test signal, or the absence of CI is an explicit release decision.

## 10. Privacy and Security

- [ ] P0: Re-scan privacy manifest before submission
  - File path(s): `Downward/PrivacyInfo.xcprivacy`, `Downward/Domain/Persistence`, `Downward/Domain/Workspace`, `Downward/Domain/Document`, `RELEASE_QA.md`
  - Problem: The manifest declares UserDefaults and file timestamp reasons. The app also uses Files access, bookmarks, StoreKit, pasteboard copy, and custom font registration.
  - Why it matters: App Store privacy answers and required-reason API declarations must match real behavior.
  - Suggested fix: Run a pre-submit privacy scan, compare to Apple's current required-reason API list, and update manifest/App Store privacy answers if needed.
  - Acceptance criteria: Manifest, App Store privacy questionnaire, and actual code behavior are consistent.
  - P0 pass note: Static scan evidence added to `RELEASE_QA.md` on 2026-05-02 for UserDefaults and file timestamp usage. This remains unchecked until the final pre-submit scan and App Store privacy questionnaire are completed.
  - 2026-05-03 note: Re-scanned UserDefaults, resource-value/timestamp access, pasteboard usage, tracking/ad/analytics/network/location/camera/photos/microphone/contacts APIs, and production logging. Findings are recorded in `RELEASE_QA.md`; no obvious new required-reason mismatch was found. This remains unchecked until the final App Store privacy questionnaire is completed.

- [ ] P1: Audit pasteboard use for user expectation and privacy
  - File path(s): `Downward/Features/Editor/MarkdownEditorTextViewCoordinator.swift`
  - Problem: Long-press code copy writes to `UIPasteboard.general`.
  - Why it matters: This is user-initiated and reasonable, but should be documented and kept clearly intentional.
  - Suggested fix: Ensure the copy gesture cannot trigger accidentally, haptic/visual feedback confirms the action, and no background pasteboard reads exist.
  - Acceptance criteria: Only user-initiated copy writes to pasteboard, no pasteboard reads exist, and release privacy notes are accurate.

- [ ] P1: Keep Debug logging free of sensitive paths in Release
  - File path(s): `Downward/Infrastructure/Logging/DebugLogger.swift`, `Downward/App/AppCoordinator.swift`, `Downward/Domain/Document/PlainTextDocumentSession.swift`
  - Problem: Debug logs include relative paths and operation context, guarded by `#if DEBUG`.
  - Why it matters: This is probably safe, but privacy review should confirm no Release logging path leaks user filenames.
  - Suggested fix: Verify Release compiles logging out and avoid adding direct `print` calls elsewhere.
  - Acceptance criteria: `rg "print\\(" Downward` finds only debug-gated logging or intentional test code.

## 11. Testing

- [ ] P0: Add StoreKit purchase tests or a repeatable manual StoreKit QA script
  - File path(s): `Tests/ThemeStoreTests.swift`, `Tests/SettingsScreenModelTests.swift`, `Downward/Downward.storekit`, `RELEASE_QA.md`
  - Problem: StoreKit flow coverage is mostly manual/state-helper based.
  - Why it matters: Purchase regressions are expensive and have already happened.
  - Suggested fix: Prefer `SKTestSession` tests for product load/purchase/restore/revocation. If not feasible, write exact device/TestFlight QA steps in `RELEASE_QA.md`.
  - Acceptance criteria: Every purchase result state has either automated coverage or repeatable recorded manual coverage.
  - P0 pass note: Repeatable StoreKit Sandbox/TestFlight QA script added to `RELEASE_QA.md` on 2026-05-02. This remains unchecked until the script is executed or automated StoreKit tests cover every result state.

- [ ] P1: Add tests for model cleanup/lifecycle
  - File path(s): `Downward/Features/Editor/EditorViewModel.swift`, `Downward/Features/Root/RootViewModel.swift`, `Tests/EditorAutosaveTests.swift`, `Tests/MarkdownWorkspaceAppSmokeTests.swift`
  - Problem: Task/observer cleanup is hard to prove today.
  - Why it matters: Lifecycle leaks are subtle in multi-scene iPad apps.
  - Suggested fix: Add test seams or debug snapshots to prove tasks/observers cancel when models deinit or documents change.
  - Acceptance criteria: Tests fail if observation or delayed restore tasks keep running after teardown.

- [ ] P1: Add focused tests for UI state formatters extracted from views
  - File path(s): `Downward/Features/Settings/*`, `Downward/Features/Workspace/*`, `Tests/SettingsScreenModelTests.swift`, `Tests/WorkspaceNavigationModeTests.swift`
  - Problem: Several display strings and visibility rules are embedded in SwiftUI bodies or private computed properties.
  - Why it matters: Extracting them during refactors should make UI states testable.
  - Suggested fix: Add tests for settings summary rows, purchase state view models, delete confirmation copy, theme editor draft/export state, and imported font section state.
  - Acceptance criteria: Visual refactors preserve strings/states because tests pin the important behavior.

- [ ] P1: Add UI/previews coverage for common empty/loading/error/success states
  - File path(s): `Downward/Features/**/*.swift`
  - Problem: Some screens have good previews, but purchase, locked, loading, empty, error, and large Dynamic Type states are uneven.
  - Why it matters: The goal is a codebase that is pleasant for humans to visually tweak.
  - Suggested fix: For each major view, add previews or preview factories for normal, empty, error, loading, locked, purchased, and large type where relevant.
  - Acceptance criteria: A developer can open previews for the expected screen states without live StoreKit or real Files access.

## 12. Build Settings, Configuration, and Project Structure

- [ ] P0: Record release identity and signing decisions
  - File path(s): `Downward.xcodeproj/project.pbxproj`, `RELEASE_QA.md`
  - Problem: Bundle ID, marketing version, build number, team ID, signing style, category, and supported orientations need final confirmation.
  - Why it matters: These affect App Store submission and review.
  - Suggested fix: Record final values, increment build number for each submission, and verify archive uses distribution signing.
  - Acceptance criteria: `RELEASE_QA.md` contains the exact release commit and identity values for the submitted build.
  - P0 pass note: Current project identity/signing values were recorded in `RELEASE_QA.md` on 2026-05-02. This remains unchecked until the exact submitted commit/archive/export evidence is recorded.

- [ ] P1: Resolve root documentation source-of-truth drift
  - File path(s): `AGENTS.md`, `ARCHITECTURE.md`, `TODO.md`, `RELEASE_QA.md`
  - Problem: `AGENTS.md` names `PLANS.md` and `CODE_REVIEW.md`, while `ARCHITECTURE.md` says update `TODO.md` and `RELEASE_QA.md`.
  - Why it matters: Future agents may update the wrong planning file.
  - Suggested fix: Decide whether `TODO.md` is the active backlog or create the named docs. Update root docs consistently.
  - Acceptance criteria: There is one obvious active backlog/review document and one QA evidence document.

- [ ] P1: Decide whether to add formatter/lint tooling
  - File path(s): repo root, `Downward.xcodeproj`
  - Problem: No SwiftFormat/SwiftLint configuration is present.
  - Why it matters: Large SwiftUI/TextKit files are easier to review when formatting is predictable.
  - Suggested fix: Add a minimal formatter config, or document that Xcode formatting is the deliberate convention for 1.0.
  - Acceptance criteria: Contributors know how to format code and reviews do not accumulate style-only churn.

- [ ] P2: Add localization/string catalog plan
  - File path(s): `Downward/Features/**/*.swift`, project resources
  - Problem: UI strings are inline and there are no string catalogs.
  - Why it matters: Localization later will be harder if every copy string remains embedded in views and stores.
  - Suggested fix: Record English-only as a 1.0 decision or create an incremental string-catalog plan.
  - Acceptance criteria: Product language scope is explicit.

## 13. Dead Code, Duplication, and Cleanup

- [ ] P1: Remove or revive unused settings design components
  - File path(s): `Downward/Features/Settings/SettingsComponents.swift`
  - Problem: Several custom settings shell/card/row components appear unused.
  - Why it matters: Dead UI abstractions make future settings work confusing.
  - Suggested fix: Delete unused components after confirming no previews/tests depend on them, or adopt them intentionally in a narrow pass.
  - Acceptance criteria: `rg` confirms remaining settings components are actively used.

- [ ] P1: Remove or repurpose `SettingsPlaceholderFeature`
  - File path(s): `Downward/Features/Settings/SettingsScreen.swift`, `Tests/SettingsScreenModelTests.swift`
  - Problem: The enum says placeholder features are implemented and is only referenced by tests.
  - Why it matters: It reads like legacy placeholder tracking rather than production configuration.
  - Suggested fix: Delete it and replace tests with direct release-configuration tests, or rename it to a real feature-visibility model.
  - Acceptance criteria: Tests still cover Settings feature visibility without a misleading placeholder type.

- [ ] P1: Resolve unused `appStoreReviewURL`
  - File path(s): `Downward/Features/Settings/SettingsReleaseConfiguration.swift`, `Downward/Features/Settings/RateTheAppSettingsSection.swift`, `Tests/SettingsScreenModelTests.swift`
  - Problem: Configuration stores `appStoreReviewURL`, but the row uses SwiftUI `requestReview()` and never reads the URL.
  - Why it matters: It is unclear whether the app should request in-app review or open an App Store write-review page.
  - Suggested fix: Choose one behavior. Either delete the URL field/tests or wire URL-opening intentionally once the App Store ID exists.
  - Acceptance criteria: Configuration matches runtime behavior and tests describe the chosen rating flow.

- [ ] P2: Consolidate repeated preview container setup
  - File path(s): `Downward/Features/**/*.swift`, `Downward/Shared/PreviewSupport/PreviewSampleData.swift`
  - Problem: Many previews repeat `AppContainer.preview(...)` blocks with similar setup.
  - Why it matters: Previews are valuable here, but repeated boilerplate makes adding new states tiresome.
  - Suggested fix: Add small preview factory helpers for common workspace/editor/settings states.
  - Acceptance criteria: New previews for common states require only a few lines.

## 14. Refactor Map

### `Downward/Features/Settings/EditorSettingsPage.swift`

Current problems:

- The body mixes built-in font selection, custom font entitlement, import sheet, detail sheet, deletion, font size, line numbers, heading behavior, and reopen behavior.
- `SettingsFontOption`, imported font rows, detail views, import handlers, and helper strings all live together.
- Previewing specific states requires constructing real stores/managers.

Recommended target structure:

```text
Features/Settings/Editor/
  EditorSettingsPage.swift
  EditorSettingsViewState.swift
  BuiltInFontSection.swift
  ImportedFontsSection.swift
  ImportedFontFamilyDetailSheet.swift
  EditorDisplaySettingsSections.swift
  SettingsFontOption.swift
```

Specific TODOs:

- [ ] P1: Extract built-in font picker and rows into `BuiltInFontSection`.
- [ ] P1: Extract custom font import/list/detail UI into `ImportedFontsSection` and `ImportedFontFamilyDetailSheet`.
- [ ] P1: Move line-number opacity row into `LineNumberSettingsSection`.
- [ ] P1: Move helper copy into a small view state/formatter.
- [ ] P2: Add previews for locked fonts, no imported fonts, imported family selected, import error, and large Dynamic Type.

### `Downward/Features/Settings/ThemeEditorSettingsPage.swift`

Current problems:

- Many individual `@State` color properties make the editor hard to scan.
- Draft conversion, contrast warning, preview, export, and save behavior are coupled to view layout.
- The fixed preview overlay and content margins are fragile to visual tweaks.

Recommended target structure:

```text
Features/Settings/ThemeEditor/
  ThemeEditorSettingsPage.swift
  ThemeEditorDraft.swift
  ThemeEditorPreviewHeader.swift
  ThemeColorListSection.swift
  ThemeContrastWarningRow.swift
  ThemeEditorToolbarActions.swift
```

Specific TODOs:

- [ ] P1: Replace individual color state with `ThemeEditorDraft`.
- [ ] P1: Extract preview overlay into `ThemeEditorPreviewHeader`.
- [ ] P1: Extract color rows into `ThemeColorListSection`.
- [ ] P1: Unit test draft-to-`CustomTheme`, contrast, and export filename logic.
- [ ] P2: Add previews for low contrast, locked, new theme, edit theme, and long theme name.

### `Downward/Features/Workspace/WorkspaceFolderScreen.swift`

Current problems:

- Tree rendering, row navigation, context menus, swipe actions, delete dialogs, create/rename alerts, move sheet, and empty/search switching are in one file.
- File/folder actions are duplicated between context menus and swipe actions.
- Delete copy is duplicated and currently understates permanence.

Recommended target structure:

```text
Features/Workspace/
  WorkspaceFolderScreen.swift
  WorkspaceTreeRows.swift
  WorkspaceTreeRow.swift
  WorkspaceRowActions.swift
  WorkspaceDeleteConfirmation.swift
  WorkspaceMoveSheet.swift
  WorkspaceCreateRenamePrompts.swift
```

Specific TODOs:

- [ ] P1: Extract tree recursion into `WorkspaceTreeRows`.
- [ ] P1: Extract file/folder row action definitions into `WorkspaceRowActions`.
- [ ] P1: Extract delete confirmation copy and presentation into `WorkspaceDeleteConfirmation`.
- [ ] P1: Extract move destination sheet into `WorkspaceMoveSheet`.
- [ ] P2: Add previews for empty, search, nested, destructive dialogs, and move sheet.

### `Downward/Features/Editor/MarkdownEditorTextViewCoordinator.swift`

Current problems:

- One coordinator owns most editor behavior.
- Gesture handling, rendering, keyboard accessory, viewport anchoring, undo registration, and markdown formatting are all interleaved.
- The file is risky to edit even when changing only one feature.

Recommended target structure:

```text
Features/Editor/TextViewBridge/
  MarkdownEditorTextViewCoordinator.swift
  EditorRenderScheduler.swift
  EditorViewportCoordinator.swift
  MarkdownGestureController.swift
  MarkdownFormattingCommandController.swift
  EditorKeyboardAccessoryCoordinator.swift
```

Specific TODOs:

- [ ] P1: Extract deferred/full/incremental render scheduling into `EditorRenderScheduler`.
- [ ] P1: Extract viewport capture/restore and saved-date pull distance into `EditorViewportCoordinator`.
- [ ] P1: Extract task/link/code-copy gestures into `MarkdownGestureController`.
- [ ] P1: Extract formatting menu commands into `MarkdownFormattingCommandController`.
- [ ] P1: Extract keyboard accessory configuration/state into `EditorKeyboardAccessoryCoordinator`.
- [ ] P2: Keep the main coordinator as the `UITextViewDelegate` adapter only.

### `Downward/App/AppCoordinator.swift`

Current problems:

- Launch restore, workspace refresh, mutation result application, document loading/saving, navigation, recents, and session persistence are coupled.
- The file has useful policy collaborators but still absorbs most orchestration.
- Mutation result handling is long and easy to break.

Recommended target structure:

```text
App/
  AppCoordinator.swift
  WorkspaceRestoreCoordinator.swift
  WorkspaceMutationResultApplier.swift
  DocumentPresentationCoordinator.swift
  RestorableDocumentSessionController.swift
```

Specific TODOs:

- [ ] P1: Extract mutation result application into `WorkspaceMutationResultApplier`.
- [ ] P1: Extract restorable document session load/save/clear into `RestorableDocumentSessionController`.
- [ ] P1: Keep `AppCoordinator` as the top-level orchestrator and owner of generation tokens.
- [ ] P2: Add tests around extracted mutation applier behavior before moving more code.

### `Downward/Domain/Workspace/WorkspaceManager.swift`

Current problems:

- Restore, snapshot, mutation, path validation, name normalization, file coordination, and stubs share one file.
- Safety-critical helpers are private inside a very large file.
- The stub manager adds even more unrelated code to the live manager file.

Recommended target structure:

```text
Domain/Workspace/
  WorkspaceManager.swift
  LiveWorkspaceManager.swift
  WorkspaceMutationNamePolicy.swift
  WorkspaceMutationPathPolicy.swift
  WorkspaceFileCoordinator.swift
  StubWorkspaceManager.swift
```

Specific TODOs:

- [ ] P1: Move `LiveWorkspaceFileCoordinator` into its own file.
- [ ] P1: Move stub manager into `StubWorkspaceManager.swift`.
- [ ] P1: Extract pure name/path helper functions into tested policy types.
- [ ] P2: Split restore/snapshot helpers only after mutation extraction is stable.

### `Downward/Features/Settings/SupporterUnlockSettingsPage.swift`

Current problems:

- Purchase actions, view state, marketing copy, previews, benefits, and purchase bar are together.
- StoreKit loading/purchasing is hard to preview without live manager state.
- The page has recently changed often, so it should be easier to adjust visually.

Recommended target structure:

```text
Features/Settings/Supporter/
  SupporterUnlockSettingsPage.swift
  SupporterUnlockViewState.swift
  SupporterIntroSection.swift
  SupporterThemePreviewSection.swift
  SupporterBenefitsSection.swift
  SupporterPurchaseBar.swift
```

Specific TODOs:

- [ ] P1: Add previewable `SupporterUnlockViewState`.
- [ ] P1: Extract each visual section.
- [ ] P1: Add previews for purchased, locked, loading product, purchasing, unavailable product, and restore error.
- [ ] P2: Move preview theme selection out of the view body.

## 15. Suggested Refactor Roadmap

### Phase 1: Safety and release readiness

- Fix delete permanence copy and non-empty folder confirmation.
- Add document size policy.
- Add font import size policy.
- Prove saves, restore, delete, conflict, and security-scoped access on real devices.
- Prove StoreKit Supporter/Tips in Sandbox and TestFlight, or hide surfaces.
- Complete archive validation, export, legal/privacy/product metadata evidence.

### Phase 2: UI readability

- Split `EditorSettingsPage`.
- Split `WorkspaceFolderScreen`.
- Split `ThemeEditorSettingsPage`.
- Split Supporter/Tips purchase pages into view states and sections.
- Remove or adopt unused Settings component layer.
- Add previews for common UI states.

### Phase 3: Architecture cleanup

- Add missing task/observer cleanup.
- Split `MarkdownEditorTextViewCoordinator` by behavior cluster.
- Split `WorkspaceManager` mutation/name/path helpers.
- Split `AppCoordinator` mutation result/session persistence logic.
- Extract testable state formatters from SwiftUI views.

### Phase 4: Polish and future-proofing

- Complete VoiceOver and Dynamic Type passes.
- Add CI or document no-CI decision.
- Add formatter/lint convention.
- Decide localization/string-catalog plan.
- Add measured performance baselines.
- Document same-file multi-window behavior.

## Notes / Open Questions

- Should delete be permanent, or should Downward attempt a trash/recoverable delete workflow where Files providers support it?
- What maximum document size is acceptable for 1.0 on the target devices?
- Tips are intended to ship in 1.0 alongside Supporter if TestFlight product loading and purchase checks pass.
- Should Rate the App use SwiftUI `requestReview()` only, or open a final App Store write-review URL once the app ID exists?
- Is iPhone portrait-only intentional for a text editor, especially for hardware keyboard users?
- Is the current cached Supporter unlock policy acceptable for refund/revocation timing, given it avoids false lockouts for paying users?
- Should `TODO.md` remain the single active backlog, or should the docs be changed to the `PLANS.md`/`CODE_REVIEW.md` model named in `AGENTS.md`?
