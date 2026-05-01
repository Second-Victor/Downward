import Foundation
import Observation
import StoreKit

@MainActor
@Observable
final class StoreKitThemeEntitlementStore: ThemeEntitlementProviding {
    static let supporterProductID = "com.secondvictor.downward.supporter"
    static let cachedSupporterUnlockKey = "theme.entitlements.supporterUnlock.cached"

    private(set) var hasUnlockedThemes = false
    private(set) var hasResolvedThemeEntitlements = false
    private(set) var canRestoreThemePurchases = true
    private(set) var supporterProductDisplayName: String?
    private(set) var supporterProductDisplayPrice: String?
    private(set) var isLoadingSupporterProduct = false
    private(set) var isPurchasingSupporterUnlock = false
    private(set) var supporterPurchaseErrorMessage: String?

    @ObservationIgnored private let userDefaults: UserDefaults
    @ObservationIgnored private var supporterProduct: Product?
    @ObservationIgnored private var transactionListener: Task<Void, Never>?
    @ObservationIgnored private var entitlementChangeHandler: ThemeEntitlementChangeHandler?

    init(
        userDefaults: UserDefaults = .standard,
        autoload: Bool = true
    ) {
        self.userDefaults = userDefaults
        if userDefaults.bool(forKey: Self.cachedSupporterUnlockKey) {
            hasUnlockedThemes = true
            hasResolvedThemeEntitlements = true
        }

        transactionListener = listenForTransactions()

        if autoload {
            Task { [weak self] in
                await self?.refreshPurchasedEntitlements()
                await self?.loadSupporterProduct()
            }
        }
    }

    isolated deinit {
        transactionListener?.cancel()
    }

    func setEntitlementChangeHandler(_ handler: ThemeEntitlementChangeHandler?) {
        entitlementChangeHandler = handler
    }

    func loadSupporterProduct() async {
        guard supporterProduct == nil, isLoadingSupporterProduct == false else {
            return
        }

        isLoadingSupporterProduct = true
        defer { isLoadingSupporterProduct = false }

        do {
            let products = try await Product.products(for: [Self.supporterProductID])
            guard let product = products.first else {
                supporterPurchaseErrorMessage = "The Supporter Unlock is not available yet."
                return
            }

            supporterProduct = product
            supporterProductDisplayName = product.displayName
            supporterProductDisplayPrice = product.displayPrice
            supporterPurchaseErrorMessage = nil
        } catch {
            supporterPurchaseErrorMessage = "Could not load the Supporter Unlock: \(error.localizedDescription)"
        }
    }

    func purchaseSupporterUnlock() async {
        guard hasUnlockedThemes == false else {
            supporterPurchaseErrorMessage = nil
            return
        }

        if supporterProduct == nil {
            await loadSupporterProduct()
        }

        guard let supporterProduct else {
            if supporterPurchaseErrorMessage == nil {
                supporterPurchaseErrorMessage = "The Supporter Unlock is not available yet."
            }
            return
        }

        guard isPurchasingSupporterUnlock == false else {
            return
        }

        isPurchasingSupporterUnlock = true
        defer { isPurchasingSupporterUnlock = false }

        do {
            let result = try await supporterProduct.purchase()

            switch result {
            case let .success(verification):
                let transaction = try Self.checkVerified(verification)
                try await deliverSupporterUnlock(from: transaction)
                await transaction.finish()
                supporterPurchaseErrorMessage = nil
            case .userCancelled:
                supporterPurchaseErrorMessage = nil
            case .pending:
                supporterPurchaseErrorMessage = "The Supporter Unlock purchase is pending approval."
            @unknown default:
                supporterPurchaseErrorMessage = "The Supporter Unlock purchase could not be completed."
            }
        } catch {
            supporterPurchaseErrorMessage = error.localizedDescription
        }
    }

    func restoreThemePurchases() async {
        do {
            try await AppStore.sync()
            await refreshPurchasedEntitlements()

            if hasUnlockedThemes {
                supporterPurchaseErrorMessage = nil
            } else {
                supporterPurchaseErrorMessage = "No previous Supporter Unlock purchase was found."
            }
        } catch {
            supporterPurchaseErrorMessage = "Could not restore purchases: \(error.localizedDescription)"
        }
    }

    func clearSupporterPurchaseError() {
        supporterPurchaseErrorMessage = nil
    }

    private func refreshPurchasedEntitlements() async {
        var isUnlocked = false

        for await result in Transaction.currentEntitlements {
            guard case let .verified(transaction) = result else {
                continue
            }

            if Self.isCurrentSupporterTransaction(transaction) {
                isUnlocked = true
                break
            }
        }

        applyResolvedSupporterEntitlement(hasCurrentEntitlement: isUnlocked)
    }

    func applyResolvedSupporterEntitlement(hasCurrentEntitlement isUnlocked: Bool) {
        // The launch cache is optimistic only until StoreKit finishes enumerating
        // current entitlements. Once resolved, mirror the authoritative result locally.
        setHasUnlockedThemes(
            isUnlocked,
            markingEntitlementsResolved: true,
            persistLocalUnlock: isUnlocked,
            clearLocalUnlock: isUnlocked == false
        )
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task { [weak self] in
            for await result in Transaction.updates {
                await self?.handle(transactionUpdate: result)
            }
        }
    }

    private func handle(transactionUpdate result: VerificationResult<Transaction>) async {
        do {
            let transaction = try Self.checkVerified(result)
            guard transaction.productID == Self.supporterProductID else {
                return
            }

            guard transaction.revocationDate == nil else {
                await refreshPurchasedEntitlements()
                await transaction.finish()
                return
            }

            try await deliverSupporterUnlock(from: transaction)
            await transaction.finish()
        } catch {
            supporterPurchaseErrorMessage = error.localizedDescription
        }
    }

    private func deliverSupporterUnlock(from transaction: Transaction) async throws {
        guard Self.isCurrentSupporterTransaction(transaction) else {
            return
        }

        setHasUnlockedThemes(true, persistLocalUnlock: true)
    }

    private func setHasUnlockedThemes(
        _ isUnlocked: Bool,
        markingEntitlementsResolved: Bool = false,
        persistLocalUnlock: Bool = false,
        clearLocalUnlock: Bool = false
    ) {
        let didChangeUnlockState = hasUnlockedThemes != isUnlocked
        let didResolveEntitlements = markingEntitlementsResolved && hasResolvedThemeEntitlements == false

        hasUnlockedThemes = isUnlocked
        if isUnlocked && persistLocalUnlock {
            userDefaults.set(true, forKey: Self.cachedSupporterUnlockKey)
        } else if isUnlocked == false && clearLocalUnlock {
            userDefaults.removeObject(forKey: Self.cachedSupporterUnlockKey)
        }

        if markingEntitlementsResolved {
            hasResolvedThemeEntitlements = true
        }

        if didChangeUnlockState || didResolveEntitlements {
            entitlementChangeHandler?()
        }
    }

    private static func isCurrentSupporterTransaction(_ transaction: Transaction) -> Bool {
        transaction.productID == Self.supporterProductID && transaction.revocationDate == nil
    }

    private nonisolated static func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case let .unverified(_, error):
            throw error
        case let .verified(safe):
            return safe
        }
    }
}
