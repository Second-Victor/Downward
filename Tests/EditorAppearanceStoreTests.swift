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
        store.setLineNumberOpacity(0.42)
        store.setLargerHeadingText(true)
        store.setColorFormattedText(false)
        store.setTapToToggleTasks(false)
        store.setSelectedThemeID(EditorTheme.greyAdaptive.id)
        store.setMatchSystemChromeToTheme(false)
        store.setReopenLastDocumentOnLaunch(false)

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
                showLineNumbers: false,
                lineNumberOpacity: 0.42,
                largerHeadingText: true,
                colorFormattedText: false,
                tapToToggleTasks: false,
                selectedThemeID: EditorTheme.greyAdaptive.id,
                matchSystemChromeToTheme: false,
                reopenLastDocumentOnLaunch: false
            )
        )
    }

    @MainActor
    func testDefaultLineNumbersAreFalse() {
        let store = EditorAppearanceStore(initialPreferences: .default)

        XCTAssertFalse(store.showLineNumbers)
        XCTAssertFalse(store.effectiveShowLineNumbers)
        XCTAssertEqual(store.lineNumberOpacity, EditorAppearancePreferences.defaultLineNumberOpacity)
        XCTAssertFalse(store.largerHeadingText)
        XCTAssertFalse(store.effectiveLargerHeadingText)
    }

    @MainActor
    func testLineNumbersPersistForAnyFont() throws {
        let suiteName = "EditorAppearanceStoreTests.\(UUID().uuidString)"
        let userDefaults = try makeIsolatedUserDefaults(suiteName: suiteName)
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        let store = EditorAppearanceStore(
            userDefaults: userDefaults,
            preferencesKey: "test.editor.appearance",
            initialPreferences: EditorAppearancePreferences(
                fontChoice: .default,
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
    func testLineNumberOpacityPersistsAndClamps() throws {
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

        store.setLineNumberOpacity(1.25)
        XCTAssertEqual(store.lineNumberOpacity, 1)

        store.setLineNumberOpacity(0.336)
        XCTAssertEqual(store.lineNumberOpacity, 0.34)

        let reloadedStore = EditorAppearanceStore(
            userDefaults: userDefaults,
            preferencesKey: "test.editor.appearance"
        )
        XCTAssertEqual(reloadedStore.lineNumberOpacity, 0.34)
    }

    @MainActor
    func testLargerHeadingTextPersistsAndDisablesLineNumbers() throws {
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

        store.setLargerHeadingText(true)

        XCTAssertTrue(store.largerHeadingText)
        XCTAssertTrue(store.effectiveLargerHeadingText)
        XCTAssertFalse(store.showLineNumbers)
        XCTAssertFalse(store.effectiveShowLineNumbers)

        let reloadedStore = EditorAppearanceStore(
            userDefaults: userDefaults,
            preferencesKey: "test.editor.appearance"
        )
        XCTAssertTrue(reloadedStore.largerHeadingText)
        XCTAssertFalse(reloadedStore.showLineNumbers)
        XCTAssertFalse(reloadedStore.effectiveShowLineNumbers)
    }

    @MainActor
    func testLineNumbersCannotBeEnabledWhileLargerHeadingTextIsEnabled() {
        let store = EditorAppearanceStore(
            initialPreferences: EditorAppearancePreferences(
                fontChoice: .systemMonospaced,
                fontSize: 16,
                largerHeadingText: true
            )
        )

        store.setShowLineNumbers(true)

        XCTAssertTrue(store.largerHeadingText)
        XCTAssertFalse(store.showLineNumbers)
        XCTAssertFalse(store.effectiveShowLineNumbers)
    }

    @MainActor
    func testSwitchingToProportionalFontPreservesLineNumbers() throws {
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

        XCTAssertTrue(store.showLineNumbers)
        XCTAssertTrue(store.effectiveShowLineNumbers)

        let reloadedStore = EditorAppearanceStore(
            userDefaults: userDefaults,
            preferencesKey: "test.editor.appearance"
        )
        XCTAssertTrue(reloadedStore.showLineNumbers)
        XCTAssertTrue(reloadedStore.effectiveShowLineNumbers)
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
        XCTAssertEqual(preferences.lineNumberOpacity, EditorAppearancePreferences.defaultLineNumberOpacity)
        XCTAssertTrue(preferences.tapToToggleTasks)
        XCTAssertTrue(preferences.reopenLastDocumentOnLaunch)
    }

    @MainActor
    func testDecodingOldPreferencesWithoutLargerHeadingTextDefaultsToFalse() throws {
        let json = """
        {
          "fontChoice": "systemMonospaced",
          "fontSize": 16,
          "markdownSyntaxMode": "visible",
          "showLineNumbers": false,
          "colorFormattedText": true,
          "selectedThemeID": "adaptive",
          "matchSystemChromeToTheme": true
        }
        """

        let preferences = try JSONDecoder().decode(
            EditorAppearancePreferences.self,
            from: Data(json.utf8)
        )

        XCTAssertFalse(preferences.largerHeadingText)
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
        let themeStore = ThemeStore(
            fileURL: FileManager.default.temporaryDirectory.appending(path: "editor-theme-\(UUID().uuidString).json"),
            entitlements: ThemeEntitlementStore(hasUnlockedThemes: true),
            bundledPremiumThemes: []
        )
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
    func testEditorAppearanceStoreFallsBackFromLockedCustomThemeSelection() async {
        let entitlements = ThemeEntitlementStore(hasUnlockedThemes: true)
        let customTheme = CustomTheme(
            id: UUID(),
            name: "Locked Custom",
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
        let themeStore = ThemeStore(
            fileURL: FileManager.default.temporaryDirectory.appending(path: "locked-editor-theme-\(UUID().uuidString).json"),
            entitlements: entitlements,
            bundledPremiumThemes: []
        )
        let didAddTheme = await themeStore.add(customTheme)
        XCTAssertTrue(didAddTheme)

        let store = EditorAppearanceStore(
            initialPreferences: EditorAppearancePreferences(
                fontChoice: .default,
                fontSize: 16,
                selectedThemeID: customTheme.id.uuidString
            )
        )

        entitlements.setHasUnlockedThemes(false)
        store.fallBackToAdaptiveThemeIfSelectedCustomThemeIsNotEntitled(using: themeStore)
        store.setSelectedThemeID(customTheme.id.uuidString, using: themeStore)

        XCTAssertEqual(store.selectedThemeID, EditorTheme.adaptive.id)
        XCTAssertEqual(store.selectedThemeLabel(using: themeStore), EditorTheme.adaptive.label)
    }

    @MainActor
    func testEditorAppearanceStorePreservesCustomThemeUntilEntitlementsResolve() {
        let selectedThemeID = UUID()
        let themeStore = ThemeStore(
            fileURL: FileManager.default.temporaryDirectory.appending(path: "unresolved-editor-theme-\(UUID().uuidString).json"),
            entitlements: UnresolvedEditorAppearanceThemeEntitlementStore(),
            bundledPremiumThemes: []
        )
        let store = EditorAppearanceStore(
            initialPreferences: EditorAppearancePreferences(
                fontChoice: .default,
                fontSize: 16,
                selectedThemeID: selectedThemeID.uuidString
            )
        )

        store.fallBackToAdaptiveThemeIfSelectedCustomThemeIsNotEntitled(using: themeStore)

        XCTAssertEqual(store.selectedThemeID, selectedThemeID.uuidString)
    }

    @MainActor
    func testColorFormattedTextMapsHeadingToAccentAndEmphasisToSyntaxMarkerColor() async {
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
        let themeStore = ThemeStore(
            fileURL: FileManager.default.temporaryDirectory.appending(path: "editor-color-formatted-\(UUID().uuidString).json"),
            entitlements: ThemeEntitlementStore(hasUnlockedThemes: true),
            bundledPremiumThemes: []
        )
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

        XCTAssertSameResolvedColor(enabledTheme.headingText, customTheme.tint.uiColor)
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
    func testEditorViewModelReflectsMatchSystemChromeToThemePreference() {
        let enabledContainer = AppContainer.preview(
            launchState: .noWorkspaceSelected,
            editorAppearancePreferences: EditorAppearancePreferences(
                fontChoice: .default,
                fontSize: 16,
                matchSystemChromeToTheme: true
            )
        )
        let disabledContainer = AppContainer.preview(
            launchState: .noWorkspaceSelected,
            editorAppearancePreferences: EditorAppearancePreferences(
                fontChoice: .default,
                fontSize: 16,
                matchSystemChromeToTheme: false
            )
        )

        XCTAssertTrue(enabledContainer.editorViewModel.matchSystemChromeToTheme)
        XCTAssertFalse(disabledContainer.editorViewModel.matchSystemChromeToTheme)
    }

    @MainActor
    func testImportedFontSelectionRequiresThemeUnlock() {
        let resolver = EditorFontResolver(isRuntimeFontAvailable: { $0 == "Readable-Regular" })
        let store = EditorAppearanceStore(resolver: resolver, initialPreferences: .default)
        let record = ImportedFontRecord(
            displayName: "Readable",
            familyName: "Readable",
            postScriptName: "Readable-Regular",
            styleName: "Regular",
            relativePath: "Readable.ttf",
            importDate: Date(),
            symbolicTraitsRawValue: 0
        )

        store.setImportedFont(record)
        XCTAssertNil(store.selectedImportedFontFamilyName)
        XCTAssertEqual(store.selectedFontChoice, .default)

        store.setImportedFontsUnlocked(true)
        store.setImportedFont(record)

        XCTAssertEqual(store.selectedImportedFontFamilyName, "Readable")
        XCTAssertEqual(store.selectedImportedFontFamilyDisplayName, "Readable")
    }

    @MainActor
    func testImportedFontSelectionPreservesLineNumbersWhenHeadingsAreNormal() {
        let resolver = EditorFontResolver(isRuntimeFontAvailable: { $0 == "Readable-Regular" })
        let store = EditorAppearanceStore(
            resolver: resolver,
            initialPreferences: EditorAppearancePreferences(
                fontChoice: .default,
                fontSize: 16,
                showLineNumbers: true
            )
        )
        let family = ImportedFontFamily(
            familyName: "Readable",
            displayName: "Readable",
            records: [
                ImportedFontRecord(
                    displayName: "Readable Regular",
                    familyName: "Readable",
                    postScriptName: "Readable-Regular",
                    styleName: "Regular",
                    relativePath: "Readable.ttf",
                    importDate: Date(),
                    symbolicTraitsRawValue: 0
                )
            ]
        )

        store.setImportedFontsUnlocked(true)
        store.setImportedFontFamily(family)

        XCTAssertEqual(store.selectedImportedFontFamilyName, "Readable")
        XCTAssertTrue(store.showLineNumbers)
        XCTAssertTrue(store.effectiveShowLineNumbers)
    }

    @MainActor
    func testSelectedImportedFontPersistsButFallsBackWhenLocked() throws {
        let suiteName = "EditorAppearanceStoreTests.\(UUID().uuidString)"
        let userDefaults = try makeIsolatedUserDefaults(suiteName: suiteName)
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        let resolver = EditorFontResolver(isRuntimeFontAvailable: { $0 == "Readable-Regular" })
        let record = ImportedFontRecord(
            displayName: "Readable",
            familyName: "Readable",
            postScriptName: "Readable-Regular",
            styleName: "Regular",
            relativePath: "Readable.ttf",
            importDate: Date(),
            symbolicTraitsRawValue: 0
        )
        let store = EditorAppearanceStore(
            userDefaults: userDefaults,
            preferencesKey: "test.editor.appearance",
            resolver: resolver
        )
        store.setImportedFontsUnlocked(true)
        store.setImportedFont(record)

        let lockedReload = EditorAppearanceStore(
            userDefaults: userDefaults,
            preferencesKey: "test.editor.appearance",
            resolver: resolver
        )
        XCTAssertNil(lockedReload.selectedImportedFontFamilyName)
        XCTAssertEqual(lockedReload.selectedFontChoice, .default)

        lockedReload.setImportedFontsUnlocked(true)
        XCTAssertEqual(lockedReload.selectedImportedFontFamilyName, "Readable")
        XCTAssertEqual(lockedReload.selectedImportedFontFamilyDisplayName, "Readable")
    }

    @MainActor
    func testClearingDeletedImportedFontFamilyFallsBackToBuiltInFont() {
        let resolver = EditorFontResolver(isRuntimeFontAvailable: { $0 == "Readable-Regular" })
        let store = EditorAppearanceStore(resolver: resolver, initialPreferences: .default)
        let family = ImportedFontFamily(
            familyName: "Readable",
            displayName: "Readable",
            records: [
                ImportedFontRecord(
                    displayName: "Readable Regular",
                    familyName: "Readable",
                    postScriptName: "Readable-Regular",
                    styleName: "Regular",
                    relativePath: "Readable.ttf",
                    importDate: Date(),
                    symbolicTraitsRawValue: 0
                )
            ]
        )

        store.setImportedFontsUnlocked(true)
        store.setImportedFontFamily(family)
        store.clearImportedFontFamilyIfSelected("Readable")

        XCTAssertNil(store.selectedImportedFontFamilyName)
        XCTAssertEqual(store.selectedFontChoice, .default)
        XCTAssertEqual(store.selectedFontDisplayName, "SF Pro")
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

@MainActor
private final class UnresolvedEditorAppearanceThemeEntitlementStore: ThemeEntitlementProviding {
    private(set) var hasUnlockedThemes = false
    private(set) var hasResolvedThemeEntitlements = false
    private(set) var canRestoreThemePurchases = false
    private(set) var supporterProductDisplayName: String?
    private(set) var supporterProductDisplayPrice: String?
    private(set) var isLoadingSupporterProduct = false
    private(set) var isPurchasingSupporterUnlock = false
    private(set) var supporterPurchaseErrorMessage: String?

    func loadSupporterProduct() async {}

    func purchaseSupporterUnlock() async {}

    func restoreThemePurchases() async {}

    func clearSupporterPurchaseError() {
        supporterPurchaseErrorMessage = nil
    }

    func setEntitlementChangeHandler(_ handler: ThemeEntitlementChangeHandler?) {}
}
