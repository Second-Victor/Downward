import UIKit
import XCTest
@testable import Downward

@MainActor
final class NavigationBarStyleTests: XCTestCase {
    func testNavigationTitleFontsScaleWithDynamicType() throws {
        let standardAppearance = NavigationBarStyle.makeAppearance(preferredContentSizeCategory: .large)
        let accessibilityAppearance = NavigationBarStyle.makeAppearance(
            preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge
        )

        let standardLargeTitleFont = try XCTUnwrap(
            standardAppearance.largeTitleTextAttributes[.font] as? UIFont
        )
        let accessibilityLargeTitleFont = try XCTUnwrap(
            accessibilityAppearance.largeTitleTextAttributes[.font] as? UIFont
        )
        let standardTitleFont = try XCTUnwrap(
            standardAppearance.titleTextAttributes[.font] as? UIFont
        )
        let accessibilityTitleFont = try XCTUnwrap(
            accessibilityAppearance.titleTextAttributes[.font] as? UIFont
        )

        XCTAssertGreaterThan(accessibilityLargeTitleFont.pointSize, standardLargeTitleFont.pointSize)
        XCTAssertGreaterThan(accessibilityTitleFont.pointSize, standardTitleFont.pointSize)
        XCTAssertTrue(standardLargeTitleFont.fontDescriptor.symbolicTraits.contains(.traitBold))
        XCTAssertTrue(standardTitleFont.fontDescriptor.symbolicTraits.contains(.traitBold))
    }

    func testApplyUpdatesNavigationBarAppearances() throws {
        let navigationBar = UINavigationBar()

        NavigationBarStyle.apply(
            to: navigationBar,
            preferredContentSizeCategory: .extraExtraExtraLarge
        )

        let standardLargeTitleFont = try XCTUnwrap(
            navigationBar.standardAppearance.largeTitleTextAttributes[.font] as? UIFont
        )
        let scrollEdgeLargeTitleFont = try XCTUnwrap(
            navigationBar.scrollEdgeAppearance?.largeTitleTextAttributes[.font] as? UIFont
        )
        let standardTitleFont = try XCTUnwrap(
            navigationBar.standardAppearance.titleTextAttributes[.font] as? UIFont
        )
        let compactTitleFont = try XCTUnwrap(
            navigationBar.compactAppearance?.titleTextAttributes[.font] as? UIFont
        )

        XCTAssertEqual(standardLargeTitleFont.pointSize, scrollEdgeLargeTitleFont.pointSize)
        XCTAssertEqual(standardTitleFont.pointSize, compactTitleFont.pointSize)
        XCTAssertTrue(standardTitleFont.fontDescriptor.symbolicTraits.contains(.traitBold))
    }

    func testApplyPreservesExistingAppearanceColors() throws {
        let navigationBar = UINavigationBar()
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .systemPink
        appearance.titleTextAttributes = [.foregroundColor: UIColor.systemYellow]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.systemGreen]
        navigationBar.standardAppearance = appearance

        NavigationBarStyle.apply(to: navigationBar, preferredContentSizeCategory: .large)

        XCTAssertEqual(navigationBar.standardAppearance.backgroundColor, .systemPink)
        XCTAssertEqual(
            navigationBar.standardAppearance.titleTextAttributes[.foregroundColor] as? UIColor,
            .systemYellow
        )
        XCTAssertEqual(
            navigationBar.standardAppearance.largeTitleTextAttributes[.foregroundColor] as? UIColor,
            .systemGreen
        )
        XCTAssertNotNil(navigationBar.standardAppearance.titleTextAttributes[.font] as? UIFont)
    }
}
