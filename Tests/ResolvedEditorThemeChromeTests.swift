import SwiftUI
import UIKit
import XCTest
@testable import Downward

final class ResolvedEditorThemeChromeTests: XCTestCase {
    @MainActor
    func testBlackBackgroundPrefersDarkChromeSchemeForLightForeground() {
        let theme = makeTheme(background: .black)

        XCTAssertEqual(theme.preferredChromeColorScheme(resolvingAgainst: .light), .dark)
    }

    @MainActor
    func testWhiteBackgroundPrefersLightChromeSchemeForDarkForeground() {
        let theme = makeTheme(background: .white)

        XCTAssertEqual(theme.preferredChromeColorScheme(resolvingAgainst: .dark), .light)
    }

    @MainActor
    func testDarkCustomBackgroundPrefersDarkChromeScheme() {
        let theme = makeTheme(background: UIColor(red: 0.08, green: 0.09, blue: 0.12, alpha: 1))

        XCTAssertEqual(theme.preferredChromeColorScheme(resolvingAgainst: .light), .dark)
    }

    @MainActor
    func testLightCustomBackgroundPrefersLightChromeScheme() {
        let theme = makeTheme(background: UIColor(red: 0.91, green: 0.93, blue: 0.88, alpha: 1))

        XCTAssertEqual(theme.preferredChromeColorScheme(resolvingAgainst: .dark), .light)
    }

    @MainActor
    func testMidGreyBackgroundUsesDocumentedLuminanceThreshold() {
        let theme = makeTheme(background: UIColor(white: 0.5, alpha: 1))

        // WCAG-linearized 50% grey is below the 0.5 threshold, so chrome requests light foregrounds.
        XCTAssertEqual(theme.preferredChromeColorScheme(resolvingAgainst: .light), .dark)
    }

    @MainActor
    func testAdaptiveBackgroundFollowsCurrentEnvironmentScheme() {
        let theme = ResolvedEditorTheme.default

        XCTAssertEqual(theme.preferredChromeColorScheme(resolvingAgainst: .light), .light)
        XCTAssertEqual(theme.preferredChromeColorScheme(resolvingAgainst: .dark), .dark)
    }

    @MainActor
    private func makeTheme(background: UIColor) -> ResolvedEditorTheme {
        EditorTheme(
            id: "test-\(UUID().uuidString)",
            label: "Test",
            background: background,
            text: .label,
            tint: .systemBlue,
            boldItalicMarker: .secondaryLabel,
            strikethrough: .label,
            inlineCode: .label,
            codeBackground: .secondarySystemFill,
            horizontalRule: .tertiaryLabel,
            checkboxUnchecked: .systemRed,
            checkboxChecked: .systemGreen
        ).resolvedEditorTheme
    }
}
