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
            using: resolver
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

    var fontSize: Double {
        preferences.fontSize
    }

    var editorFont: Font {
        resolver.font(for: effectivePreferences)
    }

    var editorUIFont: UIFont {
        resolver.uiFont(for: effectivePreferences)
    }

    var markdownSyntaxMode: MarkdownSyntaxMode {
        effectivePreferences.markdownSyntaxMode
    }

    var effectivePreferences: EditorAppearancePreferences {
        Self.normalize(preferences, using: resolver)
    }

    func setFontChoice(_ choice: EditorFontChoice) {
        let normalizedChoice = resolver.normalizedChoice(choice)
        guard preferences.fontChoice != normalizedChoice else {
            return
        }

        preferences.fontChoice = normalizedChoice
        persist()
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

    private func persist() {
        guard let data = try? encoder.encode(effectivePreferences) else {
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
        using resolver: EditorFontResolver
    ) -> EditorAppearancePreferences {
        EditorAppearancePreferences(
            fontChoice: resolver.normalizedChoice(preferences.fontChoice),
            fontSize: clampFontSize(preferences.fontSize),
            markdownSyntaxMode: preferences.markdownSyntaxMode
        )
    }

    private static func clampFontSize(_ size: Double) -> Double {
        min(max(size.rounded(), 12), 24)
    }
}
