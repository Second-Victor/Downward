import Foundation

struct EditorAppearancePreferences: Codable, Equatable, Sendable {
    var fontChoice: EditorFontChoice
    var fontSize: Double

    static let `default` = EditorAppearancePreferences(
        fontChoice: .default,
        fontSize: 16
    )
}
