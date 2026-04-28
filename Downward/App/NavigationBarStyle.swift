import SwiftUI
import UIKit

@MainActor
enum NavigationBarStyle {
    static func makeAppearance(
        preferredContentSizeCategory: UIContentSizeCategory
    ) -> UINavigationBarAppearance {
        styledAppearance(
            from: nil,
            preferredContentSizeCategory: preferredContentSizeCategory
        )
    }

    static func apply(
        to navigationBar: UINavigationBar,
        preferredContentSizeCategory: UIContentSizeCategory
    ) {
        navigationBar.standardAppearance = styledAppearance(
            from: navigationBar.standardAppearance,
            preferredContentSizeCategory: preferredContentSizeCategory
        )
        navigationBar.scrollEdgeAppearance = styledAppearance(
            from: navigationBar.scrollEdgeAppearance ?? navigationBar.standardAppearance,
            preferredContentSizeCategory: preferredContentSizeCategory
        )
        navigationBar.compactAppearance = styledAppearance(
            from: navigationBar.compactAppearance ?? navigationBar.standardAppearance,
            preferredContentSizeCategory: preferredContentSizeCategory
        )
    }

    private static func styledAppearance(
        from existingAppearance: UINavigationBarAppearance?,
        preferredContentSizeCategory: UIContentSizeCategory
    ) -> UINavigationBarAppearance {
        let traitCollection = UITraitCollection(preferredContentSizeCategory: preferredContentSizeCategory)
        let appearance = existingAppearance?.copy() as? UINavigationBarAppearance ?? UINavigationBarAppearance()
        if existingAppearance == nil {
            appearance.configureWithDefaultBackground()
        }

        appearance.largeTitleTextAttributes = replacingFont(
            in: appearance.largeTitleTextAttributes,
            with: largeTitleFont(compatibleWith: traitCollection)
        )
        appearance.titleTextAttributes = replacingFont(
            in: appearance.titleTextAttributes,
            with: titleFont(compatibleWith: traitCollection)
        )
        return appearance
    }

    private static func replacingFont(
        in attributes: [NSAttributedString.Key: Any],
        with font: UIFont
    ) -> [NSAttributedString.Key: Any] {
        var updatedAttributes = attributes
        updatedAttributes[.font] = font
        return updatedAttributes
    }

    private static func largeTitleFont(compatibleWith traitCollection: UITraitCollection) -> UIFont {
        font(textStyle: .largeTitle, compatibleWith: traitCollection)
    }

    private static func titleFont(compatibleWith traitCollection: UITraitCollection) -> UIFont {
        font(textStyle: .headline, compatibleWith: traitCollection)
    }

    private static func font(
        textStyle: UIFont.TextStyle,
        compatibleWith traitCollection: UITraitCollection
    ) -> UIFont {
        let fallbackDescriptor = UIFontDescriptor.preferredFontDescriptor(
            withTextStyle: textStyle,
            compatibleWith: traitCollection
        )
        let roundedDescriptor = fallbackDescriptor.withDesign(.rounded) ?? fallbackDescriptor
        let boldDescriptor = roundedDescriptor.withSymbolicTraits(.traitBold) ?? roundedDescriptor
        return UIFont(descriptor: boldDescriptor, size: 0)
    }
}

private struct NavigationBarConfigurator: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        let viewController = UIViewController()
        viewController.view.isHidden = true
        viewController.view.isUserInteractionEnabled = false
        return viewController
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        applyNavigationBarStyle(for: uiViewController)
        Task { @MainActor [weak uiViewController] in
            guard let uiViewController else { return }
            applyNavigationBarStyle(for: uiViewController)
        }
    }

    private func applyNavigationBarStyle(for uiViewController: UIViewController) {
        guard let navigationBar = uiViewController.navigationController?.navigationBar else {
            return
        }

        NavigationBarStyle.apply(
            to: navigationBar,
            preferredContentSizeCategory: uiViewController.traitCollection.preferredContentSizeCategory
        )
    }
}

extension View {
    func roundedNavigationBarTitles() -> some View {
        background {
            NavigationBarConfigurator()
                .frame(width: 0, height: 0)
        }
    }
}
