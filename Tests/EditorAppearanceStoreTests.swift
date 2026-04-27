import UIKit
import XCTest
@testable import Downward

final class EditorAppearanceStoreTests: XCTestCase {
    @MainActor
    func testEditorAppearanceStorePersistsPreferences() throws {
        let suiteName = "EditorAppearanceStoreTests.\(UUID().uuidString)"
        let userDefaults = try makeIsolatedUserDefaults(suiteName: suiteName)
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let resolver = EditorFontResolver(
            isRuntimeFontAvailable: { fontName in
                fontName == "Menlo-Regular"
            }
        )

        let store = EditorAppearanceStore(
            userDefaults: userDefaults,
            preferencesKey: "test.editor.appearance",
            resolver: resolver
        )
        store.setFontChoice(.menlo)
        store.setFontSize(19)
        store.setMarkdownSyntaxMode(.hiddenOutsideCurrentLine)
        store.setShowLineNumbers(true)
        store.setColorFormattedText(false)
        store.setSelectedThemeID(EditorTheme.greyAdaptive.id)
        store.setMatchSystemChromeToTheme(false)

        let reloadedStore = EditorAppearanceStore(
            userDefaults: userDefaults,
            preferencesKey: "test.editor.appearance",
            resolver: resolver
        )

        XCTAssertEqual(
            reloadedStore.effectivePreferences,
            EditorAppearancePreferences(
                fontChoice: .menlo,
                fontSize: 19,
                markdownSyntaxMode: .hiddenOutsideCurrentLine,
                showLineNumbers: true,
                colorFormattedText: false,
                selectedThemeID: EditorTheme.greyAdaptive.id,
                matchSystemChromeToTheme: false
            )
        )
    }

    @MainActor
    func testDefaultLineNumbersAreFalse() {
        let store = EditorAppearanceStore(initialPreferences: .default)

        XCTAssertFalse(store.showLineNumbers)
        XCTAssertFalse(store.effectiveShowLineNumbers)
    }

    @MainActor
    func testLineNumbersPersistForMonospacedFonts() throws {
        let suiteName = "EditorAppearanceStoreTests.\(UUID().uuidString)"
        let userDefaults = try makeIsolatedUserDefaults(suiteName: suiteName)
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        let store = EditorAppearanceStore(
            userDefaults: userDefaults,
            preferencesKey: "test.editor.appearance",
            initialPreferences: EditorAppearancePreferences(
                fontChoice: .systemMonospaced,
                fontSize: 16
            )
        )

        store.setShowLineNumbers(true)

        let reloadedStore = EditorAppearanceStore(
            userDefaults: userDefaults,
            preferencesKey: "test.editor.appearance"
        )
        XCTAssertTrue(reloadedStore.showLineNumbers)
        XCTAssertTrue(reloadedStore.effectiveShowLineNumbers)
    }

    @MainActor
    func testSwitchingToProportionalFontDisablesAndPersistsLineNumbers() throws {
        let suiteName = "EditorAppearanceStoreTests.\(UUID().uuidString)"
        let userDefaults = try makeIsolatedUserDefaults(suiteName: suiteName)
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        let store = EditorAppearanceStore(
            userDefaults: userDefaults,
            preferencesKey: "test.editor.appearance",
            initialPreferences: EditorAppearancePreferences(
                fontChoice: .systemMonospaced,
                fontSize: 16,
                showLineNumbers: true
            )
        )

        store.setFontChoice(.default)

        XCTAssertFalse(store.showLineNumbers)
        XCTAssertFalse(store.effectiveShowLineNumbers)

        let reloadedStore = EditorAppearanceStore(
            userDefaults: userDefaults,
            preferencesKey: "test.editor.appearance"
        )
        XCTAssertFalse(reloadedStore.showLineNumbers)
        XCTAssertFalse(reloadedStore.effectiveShowLineNumbers)
    }

    @MainActor
    func testSwitchingBetweenMonospacedFontsPreservesLineNumbers() {
        let store = EditorAppearanceStore(
            initialPreferences: EditorAppearancePreferences(
                fontChoice: .systemMonospaced,
                fontSize: 16,
                showLineNumbers: true
            )
        )

        store.setFontChoice(.menlo)

        XCTAssertEqual(store.selectedFontChoice, .menlo)
        XCTAssertTrue(store.showLineNumbers)
        XCTAssertTrue(store.effectiveShowLineNumbers)
    }

    @MainActor
    func testDecodingOldPreferencesWithoutLineNumbersDefaultsToFalse() throws {
        let json = """
        {
          "fontChoice": "systemMonospaced",
          "fontSize": 16,
          "markdownSyntaxMode": "visible",
          "colorFormattedText": true,
          "selectedThemeID": "adaptive",
          "matchSystemChromeToTheme": true
        }
        """

        let preferences = try JSONDecoder().decode(
            EditorAppearancePreferences.self,
            from: Data(json.utf8)
        )

        XCTAssertFalse(preferences.showLineNumbers)
    }

    @MainActor
    func testEditorFontResolverFiltersUnavailableNamedFonts() {
        let resolver = EditorFontResolver(
            isRuntimeFontAvailable: { fontName in
                fontName == "Courier"
            }
        )

        XCTAssertEqual(
            resolver.availableChoices,
            [.default, .systemMonospaced, .courier, .newYork]
        )
    }

    @MainActor
    func testEditorAppearanceStorePersistsProportionalFontChoice() throws {
        let suiteName = "EditorAppearanceStoreTests.\(UUID().uuidString)"
        let userDefaults = try makeIsolatedUserDefaults(suiteName: suiteName)
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let resolver = EditorFontResolver(
            isRuntimeFontAvailable: { fontName in
                fontName == "Georgia"
            }
        )
        let store = EditorAppearanceStore(
            userDefaults: userDefaults,
            preferencesKey: "test.editor.appearance",
            resolver: resolver
        )

        store.setFontChoice(.georgia)

        let reloadedStore = EditorAppearanceStore(
            userDefaults: userDefaults,
            preferencesKey: "test.editor.appearance",
            resolver: resolver
        )

        XCTAssertEqual(reloadedStore.selectedFontChoice, .georgia)
    }

    @MainActor
    func testEditorAppearanceStoreResolvesSelectedThemeThroughThemeStore() async {
        let customTheme = CustomTheme(
            id: UUID(),
            name: "Custom",
            background: HexColor(hex: "#1E1E1E"),
            text: HexColor(hex: "#D4D4D4"),
            tint: HexColor(hex: "#569CD6"),
            boldItalicMarker: HexColor(hex: "#72727F"),
            strikethrough: HexColor(hex: "#808080"),
            inlineCode: HexColor(hex: "#CE9178"),
            codeBackground: HexColor(hex: "#2D2D2D"),
            horizontalRule: HexColor(hex: "#404040"),
            checkboxUnchecked: HexColor(hex: "#F44747"),
            checkboxChecked: HexColor(hex: "#6A9955")
        )
        let themeStore = ThemeStore(fileURL: FileManager.default.temporaryDirectory.appending(path: "editor-theme-\(UUID().uuidString).json"))
        let didAddTheme = await themeStore.add(customTheme)
        XCTAssertTrue(didAddTheme)

        let store = EditorAppearanceStore(
            initialPreferences: EditorAppearancePreferences(
                fontChoice: .default,
                fontSize: 16,
                selectedThemeID: customTheme.id.uuidString
            )
        )

        XCTAssertEqual(store.selectedThemeLabel(using: themeStore), "Custom")
        XCTAssertSameResolvedColor(store.resolvedTheme(using: themeStore).editorBackground, customTheme.background.uiColor)
    }

    @MainActor
    func testColorFormattedTextMapsHeadingAndEmphasisToSyntaxMarkerColor() async {
        let customTheme = CustomTheme(
            id: UUID(),
            name: "Custom",
            background: HexColor(hex: "#1E1E1E"),
            text: HexColor(hex: "#D4D4D4"),
            tint: HexColor(hex: "#569CD6"),
            boldItalicMarker: HexColor(hex: "#C586C0"),
            strikethrough: HexColor(hex: "#808080"),
            inlineCode: HexColor(hex: "#CE9178"),
            codeBackground: HexColor(hex: "#2D2D2D"),
            horizontalRule: HexColor(hex: "#404040"),
            checkboxUnchecked: HexColor(hex: "#F44747"),
            checkboxChecked: HexColor(hex: "#6A9955")
        )
        let themeStore = ThemeStore(fileURL: FileManager.default.temporaryDirectory.appending(path: "editor-color-formatted-\(UUID().uuidString).json"))
        let didAddTheme = await themeStore.add(customTheme)
        XCTAssertTrue(didAddTheme)

        let enabledStore = EditorAppearanceStore(
            initialPreferences: EditorAppearancePreferences(
                fontChoice: .default,
                fontSize: 16,
                colorFormattedText: true,
                selectedThemeID: customTheme.id.uuidString
            )
        )
        let enabledTheme = enabledStore.resolvedTheme(using: themeStore)

        XCTAssertSameResolvedColor(enabledTheme.headingText, customTheme.boldItalicMarker.uiColor)
        XCTAssertSameResolvedColor(enabledTheme.emphasisText, customTheme.boldItalicMarker.uiColor)

        let disabledStore = EditorAppearanceStore(
            initialPreferences: EditorAppearancePreferences(
                fontChoice: .default,
                fontSize: 16,
                colorFormattedText: false,
                selectedThemeID: customTheme.id.uuidString
            )
        )
        let disabledTheme = disabledStore.resolvedTheme(using: themeStore)

        XCTAssertSameResolvedColor(disabledTheme.headingText, customTheme.text.uiColor)
        XCTAssertSameResolvedColor(disabledTheme.emphasisText, customTheme.text.uiColor)
    }

    @MainActor
    func testEditorFontResolverFallsBackToDefaultWhenSavedFontIsUnavailable() {
        let resolver = EditorFontResolver(isRuntimeFontAvailable: { _ in false })

        XCTAssertEqual(resolver.normalizedChoice(.menlo), .default)
        XCTAssertEqual(resolver.normalizedChoice(.courierNew), .default)
    }

    @MainActor
    func testEditorAppearanceStoreClampsFontSizeAndFallsBackForUnavailableChoice() {
        let resolver = EditorFontResolver(isRuntimeFontAvailable: { _ in false })
        let store = EditorAppearanceStore(
            resolver: resolver,
            initialPreferences: EditorAppearancePreferences(
                fontChoice: .courierNew,
                fontSize: 30
            )
        )

        XCTAssertEqual(
            store.effectivePreferences,
            EditorAppearancePreferences(
                fontChoice: .default,
                fontSize: 24,
                markdownSyntaxMode: .visible
            )
        )

        store.setFontSize(10)

        XCTAssertEqual(store.fontSize, 12)
        XCTAssertEqual(store.selectedFontChoice, .default)
    }

    @MainActor
    func testSelectedCustomThemeDeletionFallsBackToAdaptiveTheme() {
        let selectedThemeID = UUID()
        let unrelatedThemeID = UUID()
        let store = EditorAppearanceStore(
            initialPreferences: EditorAppearancePreferences(
                fontChoice: .default,
                fontSize: 16,
                selectedThemeID: selectedThemeID.uuidString
            )
        )

        store.fallBackToAdaptiveThemeIfSelectedThemeWasDeleted(unrelatedThemeID, didDelete: true)
        XCTAssertEqual(store.selectedThemeID, selectedThemeID.uuidString)

        store.fallBackToAdaptiveThemeIfSelectedThemeWasDeleted(selectedThemeID, didDelete: false)
        XCTAssertEqual(store.selectedThemeID, selectedThemeID.uuidString)

        store.fallBackToAdaptiveThemeIfSelectedThemeWasDeleted(selectedThemeID, didDelete: true)
        XCTAssertEqual(store.selectedThemeID, EditorTheme.adaptive.id)
    }

    @MainActor
    func testEditorAppearanceStoreExposesDefaultResolvedTheme() {
        let store = EditorAppearanceStore(initialPreferences: .default)
        let theme = store.resolvedTheme

        XCTAssertSameResolvedColor(theme.editorBackground, .systemBackground)
        XCTAssertSameResolvedColor(theme.keyboardAccessoryUnderlayBackground, .systemBackground)
        XCTAssertSameResolvedColor(theme.primaryText, .label)
        XCTAssertSameResolvedColor(theme.syntaxMarkerText, .secondaryLabel)
        XCTAssertSameResolvedColor(theme.subtleSyntaxMarkerText, .tertiaryLabel)
        XCTAssertSameResolvedColor(theme.inlineCodeBackground, .secondarySystemFill)
        XCTAssertSameResolvedColor(theme.blockquoteBar, .tertiaryLabel)
    }

    @MainActor
    private func makeIsolatedUserDefaults(suiteName: String) throws -> UserDefaults {
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            throw XCTSkip("Unable to create isolated UserDefaults suite.")
        }

        userDefaults.removePersistentDomain(forName: suiteName)
        return userDefaults
    }

    private func XCTAssertSameResolvedColor(
        _ actual: UIColor,
        _ expected: UIColor,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let lightTraits = UITraitCollection(userInterfaceStyle: .light)
        let darkTraits = UITraitCollection(userInterfaceStyle: .dark)

        XCTAssertEqual(
            actual.resolvedColor(with: lightTraits),
            expected.resolvedColor(with: lightTraits),
            file: file,
            line: line
        )
        XCTAssertEqual(
            actual.resolvedColor(with: darkTraits),
            expected.resolvedColor(with: darkTraits),
            file: file,
            line: line
        )
    }
}
