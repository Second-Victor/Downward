import Foundation
import Observation
import StoreKit

@MainActor
@Observable
final class TipJarManager {
    private static let productIdentifiers = [
        "com.secondvictor.downward.tip.small",
        "com.secondvictor.downward.tip.medium",
        "com.secondvictor.downward.tip.large",
        "com.secondvictor.downward.tip.xlarge"
    ]

    enum PurchaseState: Equatable {
        case idle
        case purchasing
        case success(String)
        case failed(String)
    }

    private(set) var products: [Product] = []
    private(set) var isLoadingProducts = false
    private(set) var purchaseInProgress = false
    private(set) var purchaseState: PurchaseState = .idle

    @ObservationIgnored private var transactionListener: Task<Void, Never>?

    init(autoload: Bool = true) {
        transactionListener = listenForTransactions()

        if autoload {
            Task { [weak self] in
                await self?.loadProducts()
            }
        }
    }

    isolated deinit {
        transactionListener?.cancel()
    }

    func loadProducts() async {
        guard isLoadingProducts == false else {
            return
        }

        isLoadingProducts = true
        defer { isLoadingProducts = false }

        do {
            let storeProducts = try await Product.products(for: Self.productIdentifiers)
            products = storeProducts.sorted { $0.price < $1.price }
        } catch {
            products = []
            purchaseState = .failed("Could not load tips: \(error.localizedDescription)")
        }
    }

    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        guard purchaseInProgress == false else {
            return false
        }

        purchaseInProgress = true
        purchaseState = .purchasing
        defer { purchaseInProgress = false }

        do {
            let result = try await product.purchase()

            switch result {
            case let .success(verification):
                let transaction = try Self.checkVerified(verification)
                await transaction.finish()
                purchaseState = .success(product.displayName)
                return true
            case .userCancelled:
                purchaseState = .idle
                return false
            case .pending:
                purchaseState = .failed("Purchase is pending approval.")
                return false
            @unknown default:
                purchaseState = .failed("The purchase could not be completed.")
                return false
            }
        } catch {
            purchaseState = .failed(error.localizedDescription)
            return false
        }
    }

    func resetPurchaseState() {
        purchaseState = .idle
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
            guard Self.productIdentifiers.contains(transaction.productID) else {
                return
            }

            await transaction.finish()
        } catch {
            purchaseState = .failed(error.localizedDescription)
        }
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
