import Foundation
import Observation

typealias ThemeEntitlementChangeHandler = @MainActor @Sendable () -> Void

@MainActor
protocol ThemeEntitlementProviding: AnyObject {
    var hasUnlockedThemes: Bool { get }
    var canRestoreThemePurchases: Bool { get }
    var supporterProductDisplayName: String? { get }
    var supporterProductDisplayPrice: String? { get }
    var isLoadingSupporterProduct: Bool { get }
    var isPurchasingSupporterUnlock: Bool { get }
    var supporterPurchaseErrorMessage: String? { get }

    func loadSupporterProduct() async
    func purchaseSupporterUnlock() async
    func restoreThemePurchases() async
    func clearSupporterPurchaseError()
    func setEntitlementChangeHandler(_ handler: ThemeEntitlementChangeHandler?)
}

@MainActor
@Observable
final class ThemeEntitlementStore: ThemeEntitlementProviding {
    private(set) var hasUnlockedThemes: Bool
    private(set) var canRestoreThemePurchases: Bool
    private(set) var supporterProductDisplayName: String?
    private(set) var supporterProductDisplayPrice: String?
    private(set) var isLoadingSupporterProduct = false
    private(set) var isPurchasingSupporterUnlock = false
    private(set) var supporterPurchaseErrorMessage: String?
    @ObservationIgnored private var entitlementChangeHandler: ThemeEntitlementChangeHandler?

    init(
        hasUnlockedThemes: Bool = false,
        canRestoreThemePurchases: Bool = false,
        supporterProductDisplayName: String? = nil,
        supporterProductDisplayPrice: String? = nil
    ) {
        self.hasUnlockedThemes = hasUnlockedThemes
        self.canRestoreThemePurchases = canRestoreThemePurchases
        self.supporterProductDisplayName = supporterProductDisplayName
        self.supporterProductDisplayPrice = supporterProductDisplayPrice
    }

    func setHasUnlockedThemes(_ isUnlocked: Bool) {
        hasUnlockedThemes = isUnlocked
        entitlementChangeHandler?()
    }

    func loadSupporterProduct() async {
    }

    func purchaseSupporterUnlock() async {
        guard hasUnlockedThemes == false else {
            supporterPurchaseErrorMessage = nil
            return
        }

        supporterPurchaseErrorMessage = "Supporter purchases are not available yet."
    }

    func restoreThemePurchases() async {
    }

    func clearSupporterPurchaseError() {
        supporterPurchaseErrorMessage = nil
    }

    func setEntitlementChangeHandler(_ handler: ThemeEntitlementChangeHandler?) {
        entitlementChangeHandler = handler
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
