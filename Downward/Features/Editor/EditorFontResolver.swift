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

    func font(for preferences: EditorAppearancePreferences) -> Font {
        let normalizedChoice = normalizedChoice(preferences.fontChoice)
        let size = preferences.fontSize

        switch normalizedChoice {
        case .default:
            return Font.system(size: size)
        case .systemMonospaced:
            return Font.system(size: size, design: .monospaced)
        case .menlo, .courier, .courierNew:
            return Font.custom(normalizedChoice.runtimeFontName ?? "", size: size)
        }
    }

    func uiFont(for preferences: EditorAppearancePreferences) -> UIFont {
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
        }
    }
}
