import XCTest
@testable import Downward

final class SettingsScreenModelTests: XCTestCase {
    @MainActor
    func testHomeSummaryUsesCurrentFontFamily() {
        let store = EditorAppearanceStore(
            initialPreferences: EditorAppearancePreferences(
                fontChoice: .systemMonospaced,
                fontSize: 15
            )
        )

        let summary = SettingsHomeSummary(
            workspaceName: "MarkDown",
            editorAppearanceStore: store
        )

        XCTAssertEqual(summary.fontName, "SF Mono")
    }

    @MainActor
    func testHomeSummaryUsesCurrentThemeName() {
        let summary = SettingsHomeSummary(
            workspaceName: "MarkDown",
            editorAppearanceStore: EditorAppearanceStore(),
            selectedTheme: .greyAdaptive
        )

        XCTAssertEqual(summary.themeName, "Grey Adaptive")
    }

    @MainActor
    func testHomeSummaryUsesCurrentWorkspaceName() {
        let summary = SettingsHomeSummary(
            workspaceName: "Writing",
            editorAppearanceStore: EditorAppearanceStore()
        )

        XCTAssertEqual(summary.workspaceName, "Writing")
    }

    @MainActor
    func testHomeSummaryUsesNoneWhenNoWorkspaceIsLoaded() {
        let summary = SettingsHomeSummary(
            workspaceName: nil,
            editorAppearanceStore: EditorAppearanceStore()
        )

        XCTAssertEqual(summary.workspaceName, "None")
    }

    @MainActor
    func testWorkspaceSettingsPresentationShowsCurrentFolderName() {
        let presentation = WorkspaceSettingsPresentation(
            workspaceName: "Writing",
            accessState: .ready(displayName: "Writing")
        )

        XCTAssertEqual(presentation.currentFolderName, "Writing")
        XCTAssertTrue(presentation.canClearWorkspace)
    }

    @MainActor
    func testWorkspaceSettingsPresentationShowsNoneWithoutWorkspaceAndDisablesClear() {
        let presentation = WorkspaceSettingsPresentation(
            workspaceName: nil,
            accessState: .noneSelected
        )

        XCTAssertEqual(presentation.currentFolderName, "None")
        XCTAssertFalse(presentation.canClearWorkspace)
    }

    @MainActor
    func testHomeSummaryUsesCurrentAppearanceName() {
        let summary = SettingsHomeSummary(
            workspaceName: "Writing",
            editorAppearanceStore: EditorAppearanceStore(),
            appearanceName: AppColorScheme.dark.label
        )

        XCTAssertEqual(summary.appearanceName, "Dark")
    }

    @MainActor
    func testEditorFontSelectionUpdatesStore() {
        let store = EditorAppearanceStore(initialPreferences: .default)

        store.setFontChoice(.systemMonospaced)

        XCTAssertEqual(store.selectedFontChoice, .systemMonospaced)
        XCTAssertEqual(
            SettingsHomeSummary(
                workspaceName: "MarkDown",
                editorAppearanceStore: store
            ).fontName,
            "SF Mono"
        )
    }

    @MainActor
    func testMarkdownDisplaySettingUpdatesStore() {
        let store = EditorAppearanceStore(initialPreferences: .default)

        store.setMarkdownSyntaxMode(.hiddenOutsideCurrentLine)
        store.setColorFormattedText(false)
        store.setTapToToggleTasks(false)
        store.setCreateMarkdownTitleFromFilename(true)
        store.setReopenLastDocumentOnLaunch(false)

        XCTAssertEqual(store.markdownSyntaxMode, .hiddenOutsideCurrentLine)
        XCTAssertEqual(store.colorFormattedText, false)
        XCTAssertFalse(store.tapToToggleTasks)
        XCTAssertTrue(store.createMarkdownTitleFromFilename)
        XCTAssertFalse(store.reopenLastDocumentOnLaunch)
    }

    @MainActor
    func testLineNumberSettingUpdatesStoreForMonospacedFonts() {
        let store = EditorAppearanceStore(
            initialPreferences: EditorAppearancePreferences(
                fontChoice: .systemMonospaced,
                fontSize: 16
            )
        )

        store.setShowLineNumbers(true)

        XCTAssertTrue(store.showLineNumbers)
        XCTAssertTrue(store.effectiveShowLineNumbers)
    }

    @MainActor
    func testLineNumberOpacitySettingUpdatesStore() {
        let store = EditorAppearanceStore(
            initialPreferences: EditorAppearancePreferences(
                fontChoice: .systemMonospaced,
                fontSize: 16,
                showLineNumbers: true
            )
        )

        store.setLineNumberOpacity(0.55)

        XCTAssertEqual(store.lineNumberOpacity, 0.55)
    }

    @MainActor
    func testLargerHeadingTextSettingUpdatesStoreAndDisablesLineNumbers() {
        let store = EditorAppearanceStore(
            initialPreferences: EditorAppearancePreferences(
                fontChoice: .systemMonospaced,
                fontSize: 16,
                showLineNumbers: true
            )
        )

        store.setLargerHeadingText(true)

        XCTAssertTrue(store.largerHeadingText)
        XCTAssertTrue(store.effectiveLargerHeadingText)
        XCTAssertFalse(store.showLineNumbers)
        XCTAssertFalse(store.effectiveShowLineNumbers)
    }

    @MainActor
    func testReleaseConfigurationShowsImplementedInformationSurfaces() {
        let configuration = SettingsReleaseConfiguration.current

        XCTAssertFalse(configuration.showsTipsPage)
        XCTAssertFalse(configuration.showsRateTheApp)
        XCTAssertTrue(configuration.showsLegalLinks)
        XCTAssertEqual(configuration.projectURL?.absoluteString, "https://secondvictor.com/public/projects/downward/downward.html")
        XCTAssertEqual(configuration.privacyPolicyURL?.absoluteString, "https://secondvictor.com/public/projects/downward/downward-policy.html")
        XCTAssertEqual(configuration.termsAndConditionsURL?.absoluteString, "https://secondvictor.com/public/projects/downward/downward-terms.html")
        XCTAssertFalse(SettingsPlaceholderFeature.tipsPurchases.isVisible(in: configuration))
        XCTAssertFalse(SettingsPlaceholderFeature.rateTheApp.isVisible(in: configuration))
        XCTAssertTrue(SettingsPlaceholderFeature.legalLinks.isVisible(in: configuration))
        XCTAssertTrue(SettingsPlaceholderFeature.lineNumbers.isVisible(in: configuration))
        XCTAssertTrue(SettingsPlaceholderFeature.largerHeadingText.isVisible(in: configuration))
        XCTAssertTrue(SettingsPlaceholderFeature.tapToToggleTasks.isVisible(in: configuration))
    }

    @MainActor
    func testConfiguredReleaseSurfacesCanBeReenabled() throws {
        let appStoreReviewURL = try XCTUnwrap(URL(string: "https://apps.apple.com/app/id1234567890?action=write-review"))
        let privacyPolicyURL = try XCTUnwrap(URL(string: "https://example.com/privacy"))
        let termsAndConditionsURL = try XCTUnwrap(URL(string: "https://example.com/terms"))
        let configuration = SettingsReleaseConfiguration(
            tipsPurchasesEnabled: true,
            appStoreReviewURL: appStoreReviewURL,
            privacyPolicyURL: privacyPolicyURL,
            termsAndConditionsURL: termsAndConditionsURL
        )

        XCTAssertTrue(configuration.showsTipsPage)
        XCTAssertTrue(configuration.showsRateTheApp)
        XCTAssertTrue(configuration.showsLegalLinks)
        XCTAssertTrue(SettingsPlaceholderFeature.tipsPurchases.isVisible(in: configuration))
        XCTAssertTrue(SettingsPlaceholderFeature.rateTheApp.isVisible(in: configuration))
        XCTAssertTrue(SettingsPlaceholderFeature.legalLinks.isVisible(in: configuration))
    }

    @MainActor
    func testRateTheAppIsHiddenWithoutAppStoreReviewURL() {
        let configuration = SettingsReleaseConfiguration(
            tipsPurchasesEnabled: false,
            rateTheAppEnabled: true,
            appStoreReviewURL: nil
        )

        XCTAssertFalse(configuration.showsRateTheApp)
        XCTAssertFalse(SettingsPlaceholderFeature.rateTheApp.isVisible(in: configuration))
    }

    func testPlaceholderSettingsAreNotMarkedImplemented() {
        let placeholders: [SettingsPlaceholderFeature] = [
            .tipsPurchases
        ]

        XCTAssertTrue(placeholders.allSatisfy { $0.isImplemented == false })
        XCTAssertTrue(SettingsPlaceholderFeature.lineNumbers.isImplemented)
        XCTAssertTrue(SettingsPlaceholderFeature.largerHeadingText.isImplemented)
        XCTAssertTrue(SettingsPlaceholderFeature.tapToToggleTasks.isImplemented)
        XCTAssertTrue(SettingsPlaceholderFeature.rateTheApp.isImplemented)
        XCTAssertTrue(SettingsPlaceholderFeature.legalLinks.isImplemented)
    }
}
