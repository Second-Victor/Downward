import SwiftUI
import UIKit

struct EditorFontResolver: Sendable {
    private let isRuntimeFontAvailable: @Sendable (String) -> Bool

    init(
        isRuntimeFontAvailable: @escaping @Sendable (String) -> Bool = { fontName in
            UIFont(name: fontName, size: 16) != nil
        }
    ) {
        self.isRuntimeFontAvailable = isRuntimeFontAvailable
    }

    var availableChoices: [EditorFontChoice] {
        EditorFontChoice.allCases.filter { choice in
            guard let runtimeFontName = choice.runtimeFontName else {
                return true
            }

            return isRuntimeFontAvailable(runtimeFontName)
        }
    }

    func normalizedChoice(_ choice: EditorFontChoice) -> EditorFontChoice {
        availableChoices.contains(choice) ? choice : .default
    }

    func font(
        for preferences: EditorAppearancePreferences,
        importedFontsUnlocked: Bool = false,
        importedFamily: ImportedFontFamily? = nil
    ) -> Font {
        if let importedFontName = usableImportedFontName(
            for: preferences,
            importedFontsUnlocked: importedFontsUnlocked,
            importedFamily: importedFamily
        ) {
            return Font.custom(importedFontName, size: preferences.fontSize)
        }

        let normalizedChoice = normalizedChoice(preferences.fontChoice)
        let size = preferences.fontSize

        switch normalizedChoice {
        case .default:
            return Font.system(size: size)
        case .systemMonospaced:
            return Font.system(size: size, design: .monospaced)
        case .menlo, .courier, .courierNew:
            return Font.custom(normalizedChoice.runtimeFontName ?? "", size: size)
        case .newYork:
            return Font.system(size: size, design: .serif)
        case .georgia:
            return Font.custom(normalizedChoice.runtimeFontName ?? "", size: size)
        }
    }

    func uiFont(
        for preferences: EditorAppearancePreferences,
        importedFontsUnlocked: Bool = false,
        importedFamily: ImportedFontFamily? = nil
    ) -> UIFont {
        if let importedFontName = usableImportedFontName(
            for: preferences,
            importedFontsUnlocked: importedFontsUnlocked,
            importedFamily: importedFamily
        ),
           let font = UIFont(name: importedFontName, size: preferences.fontSize) {
            return font
        }

        let normalizedChoice = normalizedChoice(preferences.fontChoice)
        let size = preferences.fontSize

        switch normalizedChoice {
        case .default:
            return UIFont.systemFont(ofSize: size)
        case .systemMonospaced:
            return UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
        case .menlo, .courier, .courierNew:
            return UIFont(name: normalizedChoice.runtimeFontName ?? "", size: size)
                ?? UIFont.systemFont(ofSize: size)
        case .newYork:
            let descriptor = UIFontDescriptor
                .preferredFontDescriptor(withTextStyle: .body)
                .withDesign(.serif)
                ?? UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)
            return UIFont(descriptor: descriptor, size: size)
        case .georgia:
            return UIFont(name: normalizedChoice.runtimeFontName ?? "", size: size)
                ?? UIFont.systemFont(ofSize: size)
        }
    }

    func canUseImportedFont(
        _ postScriptName: String?,
        importedFontsUnlocked: Bool
    ) -> Bool {
        guard
            importedFontsUnlocked,
            let postScriptName,
            postScriptName.isEmpty == false
        else {
            return false
        }

        return isRuntimeFontAvailable(postScriptName)
    }

    func canUseImportedFamily(
        _ familyName: String?,
        importedFontsUnlocked: Bool,
        importedFamily: ImportedFontFamily?
    ) -> Bool {
        guard
            importedFontsUnlocked,
            let familyName,
            familyName.isEmpty == false,
            let importedFamily,
            importedFamily.familyName == familyName,
            let postScriptName = importedFamily.baseRecord?.postScriptName
        else {
            return false
        }

        return isRuntimeFontAvailable(postScriptName)
    }

    private func usableImportedFontName(
        for preferences: EditorAppearancePreferences,
        importedFontsUnlocked: Bool,
        importedFamily: ImportedFontFamily?
    ) -> String? {
        if canUseImportedFamily(
            preferences.importedFontFamilyName,
            importedFontsUnlocked: importedFontsUnlocked,
            importedFamily: importedFamily
        ) {
            return importedFamily?.baseRecord?.postScriptName
        }

        guard preferences.importedFontFamilyName == nil,
              canUseImportedFont(
                preferences.importedFontPostScriptName,
                importedFontsUnlocked: importedFontsUnlocked
              ) else {
            return nil
        }

        return preferences.importedFontPostScriptName
    }
}
