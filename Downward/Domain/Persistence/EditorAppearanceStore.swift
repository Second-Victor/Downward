import Foundation
import Observation
import SwiftUI
import UIKit

@MainActor
@Observable
final class EditorAppearanceStore {
    private let userDefaults: UserDefaults
    private let preferencesKey: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let resolver: EditorFontResolver

    private(set) var preferences: EditorAppearancePreferences
    private var areImportedFontsUnlocked = false

    init(
        userDefaults: UserDefaults = .standard,
        preferencesKey: String = "editor.appearance.preferences",
        resolver: EditorFontResolver = EditorFontResolver(),
        initialPreferences: EditorAppearancePreferences? = nil
    ) {
        self.userDefaults = userDefaults
        self.preferencesKey = preferencesKey
        self.resolver = resolver

        let loadedPreferences = initialPreferences ?? Self.loadPreferences(
            from: userDefaults,
            key: preferencesKey,
            decoder: decoder
        )
        let normalizedPreferences = Self.normalize(
            loadedPreferences,
            using: resolver,
            importedFontsUnlocked: false
        )
        self.preferences = normalizedPreferences

        if initialPreferences == nil, normalizedPreferences != loadedPreferences {
            persist()
        }
    }

    var availableFontChoices: [EditorFontChoice] {
        resolver.availableChoices
    }

    var selectedFontChoice: EditorFontChoice {
        resolver.normalizedChoice(preferences.fontChoice)
    }

    var selectedImportedFontFamilyName: String? {
        guard areImportedFontsUnlocked else {
            return nil
        }

        return preferences.importedFontFamilyName
    }

    var selectedImportedFontFamilyDisplayName: String? {
        guard selectedImportedFontFamilyName != nil else {
            return nil
        }

        return preferences.importedFontFamilyDisplayName ?? preferences.importedFontFamilyName
    }

    var selectedFontDisplayName: String {
        selectedImportedFontFamilyDisplayName ?? selectedFontChoice.displayName
    }

    var fontSize: Double {
        preferences.fontSize
    }

    var editorFont: Font {
        editorFont(importedFamily: nil)
    }

    var editorUIFont: UIFont {
        editorUIFont(importedFamily: nil)
    }

    func editorFont(importedFamily: ImportedFontFamily?) -> Font {
        resolver.font(
            for: effectivePreferences,
            importedFontsUnlocked: areImportedFontsUnlocked,
            importedFamily: importedFamily
        )
    }

    func editorUIFont(importedFamily: ImportedFontFamily?) -> UIFont {
        resolver.uiFont(
            for: effectivePreferences,
            importedFontsUnlocked: areImportedFontsUnlocked,
            importedFamily: importedFamily
        )
    }

    var markdownSyntaxMode: MarkdownSyntaxMode {
        effectivePreferences.markdownSyntaxMode
    }

    var showLineNumbers: Bool {
        preferences.showLineNumbers
    }

    var effectiveShowLineNumbers: Bool {
        effectivePreferences.showLineNumbers
    }

    var lineNumberOpacity: Double {
        effectivePreferences.lineNumberOpacity
    }

    var largerHeadingText: Bool {
        preferences.largerHeadingText
    }

    var effectiveLargerHeadingText: Bool {
        effectivePreferences.largerHeadingText
    }

    var colorFormattedText: Bool {
        effectivePreferences.colorFormattedText
    }

    var tapToToggleTasks: Bool {
        effectivePreferences.tapToToggleTasks
    }

    var createMarkdownTitleFromFilename: Bool {
        effectivePreferences.createMarkdownTitleFromFilename
    }

    var selectedThemeID: String {
        effectivePreferences.selectedThemeID
    }

    var matchSystemChromeToTheme: Bool {
        effectivePreferences.matchSystemChromeToTheme
    }

    var reopenLastDocumentOnLaunch: Bool {
        effectivePreferences.reopenLastDocumentOnLaunch
    }

    var resolvedTheme: ResolvedEditorTheme {
        // Compatibility path for tests and callers that do not own a ThemeStore.
        // Runtime editor rendering should prefer resolvedTheme(using:).
        EditorTheme.adaptive.resolvedEditorTheme.applyingColorFormattedText(colorFormattedText)
    }

    func resolvedTheme(using themeStore: ThemeStore) -> ResolvedEditorTheme {
        themeStore.resolve(selectedThemeID).resolvedEditorTheme.applyingColorFormattedText(colorFormattedText)
    }

    func selectedThemeLabel(using themeStore: ThemeStore) -> String {
        themeStore.resolve(selectedThemeID).label
    }

    var effectivePreferences: EditorAppearancePreferences {
        Self.normalize(
            preferences,
            using: resolver,
            importedFontsUnlocked: areImportedFontsUnlocked
        )
    }

    func setFontChoice(_ choice: EditorFontChoice) {
        let normalizedChoice = resolver.normalizedChoice(choice)
        guard
            preferences.fontChoice != normalizedChoice
                || preferences.importedFontFamilyName != nil
                || preferences.importedFontFamilyDisplayName != nil
                || preferences.importedFontPostScriptName != nil
                || preferences.importedFontDisplayName != nil
        else {
            return
        }

        preferences.fontChoice = normalizedChoice
        preferences.importedFontFamilyName = nil
        preferences.importedFontFamilyDisplayName = nil
        preferences.importedFontPostScriptName = nil
        preferences.importedFontDisplayName = nil
        preferences = Self.normalize(
            preferences,
            using: resolver,
            importedFontsUnlocked: areImportedFontsUnlocked
        )
        persist()
    }

    func setImportedFontFamily(_ family: ImportedFontFamily) {
        guard areImportedFontsUnlocked else {
            return
        }

        guard
            preferences.importedFontFamilyName != family.familyName
                || preferences.importedFontFamilyDisplayName != family.displayName
        else {
            return
        }

        preferences.importedFontFamilyName = family.familyName
        preferences.importedFontFamilyDisplayName = family.displayName
        preferences.importedFontPostScriptName = nil
        preferences.importedFontDisplayName = nil
        persist()
    }

    func setImportedFont(_ record: ImportedFontRecord) {
        guard areImportedFontsUnlocked else {
            return
        }

        guard
            preferences.importedFontPostScriptName != record.postScriptName
                || preferences.importedFontDisplayName != record.displayName
        else {
            return
        }

        preferences.importedFontFamilyName = record.familyName
        preferences.importedFontFamilyDisplayName = record.familyName
        preferences.importedFontPostScriptName = record.postScriptName
        preferences.importedFontDisplayName = record.displayName
        persist()
    }

    func clearImportedFontFamilyIfSelected(_ familyName: String) {
        guard preferences.importedFontFamilyName == familyName else {
            return
        }

        preferences.importedFontFamilyName = nil
        preferences.importedFontFamilyDisplayName = nil
        preferences.importedFontPostScriptName = nil
        preferences.importedFontDisplayName = nil
        persist()
    }

    func setImportedFontsUnlocked(_ isUnlocked: Bool) {
        guard areImportedFontsUnlocked != isUnlocked else {
            return
        }

        areImportedFontsUnlocked = isUnlocked
    }

    func setFontSize(_ size: Double) {
        let clampedSize = Self.clampFontSize(size)
        guard preferences.fontSize != clampedSize else {
            return
        }

        preferences.fontSize = clampedSize
        persist()
    }

    func setMarkdownSyntaxMode(_ mode: MarkdownSyntaxMode) {
        guard preferences.markdownSyntaxMode != mode else {
            return
        }

        preferences.markdownSyntaxMode = mode
        persist()
    }

    func setShowLineNumbers(_ isEnabled: Bool) {
        let normalizedValue = effectiveLargerHeadingText == false && isEnabled
        guard preferences.showLineNumbers != normalizedValue else {
            return
        }

        preferences.showLineNumbers = normalizedValue
        persist()
    }

    func setLineNumberOpacity(_ opacity: Double) {
        let clampedOpacity = Self.clampLineNumberOpacity(opacity)
        guard abs(preferences.lineNumberOpacity - clampedOpacity) > 0.001 else {
            return
        }

        preferences.lineNumberOpacity = clampedOpacity
        persist()
    }

    func setLargerHeadingText(_ isEnabled: Bool) {
        guard preferences.largerHeadingText != isEnabled || (isEnabled && preferences.showLineNumbers) else {
            return
        }

        preferences.largerHeadingText = isEnabled
        if isEnabled {
            preferences.showLineNumbers = false
        }
        persist()
    }

    func setColorFormattedText(_ isEnabled: Bool) {
        guard preferences.colorFormattedText != isEnabled else {
            return
        }

        preferences.colorFormattedText = isEnabled
        persist()
    }

    func setTapToToggleTasks(_ isEnabled: Bool) {
        guard preferences.tapToToggleTasks != isEnabled else {
            return
        }

        preferences.tapToToggleTasks = isEnabled
        persist()
    }

    func setCreateMarkdownTitleFromFilename(_ isEnabled: Bool) {
        guard preferences.createMarkdownTitleFromFilename != isEnabled else {
            return
        }

        preferences.createMarkdownTitleFromFilename = isEnabled
        persist()
    }

    func setSelectedThemeID(_ id: String) {
        guard preferences.selectedThemeID != id else {
            return
        }

        preferences.selectedThemeID = id
        persist()
    }

    func setSelectedThemeID(_ id: String, using themeStore: ThemeStore) {
        guard themeStore.canSelectTheme(withID: id) else {
            setSelectedThemeID(EditorTheme.adaptive.id)
            return
        }

        setSelectedThemeID(id)
    }

    func fallBackToAdaptiveThemeIfSelectedThemeWasDeleted(_ deletedThemeID: UUID, didDelete: Bool) {
        guard didDelete, selectedThemeID == deletedThemeID.uuidString else {
            return
        }

        setSelectedThemeID(EditorTheme.adaptive.id)
    }

    func fallBackToAdaptiveThemeIfSelectedCustomThemeIsNotEntitled(using themeStore: ThemeStore) {
        let entitledThemeID = ThemeEntitlementGate.entitledThemeID(
            for: selectedThemeID,
            hasUnlockedThemes: themeStore.hasUnlockedThemes
        )
        guard entitledThemeID != selectedThemeID else {
            return
        }

        setSelectedThemeID(entitledThemeID)
    }

    func setMatchSystemChromeToTheme(_ isEnabled: Bool) {
        guard preferences.matchSystemChromeToTheme != isEnabled else {
            return
        }

        preferences.matchSystemChromeToTheme = isEnabled
        persist()
    }

    func setReopenLastDocumentOnLaunch(_ isEnabled: Bool) {
        guard preferences.reopenLastDocumentOnLaunch != isEnabled else {
            return
        }

        preferences.reopenLastDocumentOnLaunch = isEnabled
        persist()
    }

    private func persist() {
        let normalizedPreferences = Self.normalize(
            preferences,
            using: resolver,
            importedFontsUnlocked: true
        )

        guard let data = try? encoder.encode(normalizedPreferences) else {
            return
        }

        userDefaults.set(data, forKey: preferencesKey)
    }

    private static func loadPreferences(
        from userDefaults: UserDefaults,
        key: String,
        decoder: JSONDecoder
    ) -> EditorAppearancePreferences {
        guard
            let data = userDefaults.data(forKey: key),
            let preferences = try? decoder.decode(EditorAppearancePreferences.self, from: data)
        else {
            return .default
        }

        return preferences
    }

    private static func normalize(
        _ preferences: EditorAppearancePreferences,
        using resolver: EditorFontResolver,
        importedFontsUnlocked _: Bool
    ) -> EditorAppearancePreferences {
        let normalizedChoice = resolver.normalizedChoice(preferences.fontChoice)
        let normalizedShowLineNumbers = preferences.largerHeadingText == false
            ? preferences.showLineNumbers
            : false

        return EditorAppearancePreferences(
            fontChoice: normalizedChoice,
            fontSize: clampFontSize(preferences.fontSize),
            markdownSyntaxMode: preferences.markdownSyntaxMode,
            showLineNumbers: normalizedShowLineNumbers,
            lineNumberOpacity: clampLineNumberOpacity(preferences.lineNumberOpacity),
            largerHeadingText: preferences.largerHeadingText,
            colorFormattedText: preferences.colorFormattedText,
            tapToToggleTasks: preferences.tapToToggleTasks,
            createMarkdownTitleFromFilename: preferences.createMarkdownTitleFromFilename,
            selectedThemeID: preferences.selectedThemeID,
            matchSystemChromeToTheme: preferences.matchSystemChromeToTheme,
            reopenLastDocumentOnLaunch: preferences.reopenLastDocumentOnLaunch,
            importedFontFamilyName: preferences.importedFontFamilyName,
            importedFontFamilyDisplayName: preferences.importedFontFamilyDisplayName,
            importedFontPostScriptName: preferences.importedFontPostScriptName,
            importedFontDisplayName: preferences.importedFontDisplayName
        )
    }

    private static func clampFontSize(_ size: Double) -> Double {
        min(max(size.rounded(), 12), 24)
    }

    private static func clampLineNumberOpacity(_ opacity: Double) -> Double {
        guard opacity.isFinite else {
            return EditorAppearancePreferences.defaultLineNumberOpacity
        }

        return min(max((opacity * 100).rounded() / 100, 0), 1)
    }
}
