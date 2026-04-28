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

        XCTAssertEqual(store.markdownSyntaxMode, .hiddenOutsideCurrentLine)
        XCTAssertEqual(store.colorFormattedText, false)
        XCTAssertFalse(store.tapToToggleTasks)
        XCTAssertTrue(store.createMarkdownTitleFromFilename)
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

    func testPlaceholderSettingsAreNotMarkedImplemented() {
        let placeholders: [SettingsPlaceholderFeature] = [
            .tipsPurchases,
            .rateTheApp,
            .legalLinks
        ]

        XCTAssertTrue(placeholders.allSatisfy { $0.isImplemented == false })
        XCTAssertTrue(SettingsPlaceholderFeature.lineNumbers.isImplemented)
        XCTAssertTrue(SettingsPlaceholderFeature.largerHeadingText.isImplemented)
        XCTAssertTrue(SettingsPlaceholderFeature.tapToToggleTasks.isImplemented)
    }
}
