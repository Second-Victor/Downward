import Foundation
import Observation

@MainActor
protocol ThemeEntitlementProviding: AnyObject {
    var hasUnlockedThemes: Bool { get }
    var canRestoreThemePurchases: Bool { get }

    func purchaseSupporterUnlock() async
    func restoreThemePurchases() async
}

@MainActor
@Observable
final class ThemeEntitlementStore: ThemeEntitlementProviding {
    private(set) var hasUnlockedThemes: Bool
    private(set) var canRestoreThemePurchases: Bool

    init(
        hasUnlockedThemes: Bool = false,
        canRestoreThemePurchases: Bool = false
    ) {
        self.hasUnlockedThemes = hasUnlockedThemes
        self.canRestoreThemePurchases = canRestoreThemePurchases
    }

    func setHasUnlockedThemes(_ isUnlocked: Bool) {
        hasUnlockedThemes = isUnlocked
    }

    func purchaseSupporterUnlock() async {
        // StoreKit purchase wiring belongs here when theme purchases are implemented.
    }

    func restoreThemePurchases() async {
        // StoreKit restore wiring belongs here when theme purchases are implemented.
    }
}

enum ThemeEntitlementGate {
    static let lockedMessage = "Custom themes require the Themes unlock."

    static func canCreateCustomTheme(hasUnlockedThemes: Bool) -> Bool {
        hasUnlockedThemes
    }

    static func canImportCustomThemes(hasUnlockedThemes: Bool) -> Bool {
        hasUnlockedThemes
    }

    static func canEditCustomThemes(hasUnlockedThemes: Bool) -> Bool {
        hasUnlockedThemes
    }

    static func canExportCustomThemes(hasUnlockedThemes: Bool) -> Bool {
        hasUnlockedThemes
    }

    static func canSelectCustomTheme(hasUnlockedThemes: Bool) -> Bool {
        hasUnlockedThemes
    }

    static func canImportCustomFonts(hasUnlockedThemes: Bool) -> Bool {
        hasUnlockedThemes
    }

    static func entitledThemeID(for rawValue: String, hasUnlockedThemes: Bool) -> String {
        guard UUID(uuidString: rawValue) != nil, hasUnlockedThemes == false else {
            return rawValue
        }

        return EditorTheme.adaptive.id
    }
}
