import Foundation

enum StoreProductIdentifiers {
    nonisolated static let supporterUnlock = "com.secondvictor.downward.supporter"
    nonisolated static let tipSmall = "com.secondvictor.downward.tip.small"
    nonisolated static let tipMedium = "com.secondvictor.downward.tip.medium"
    nonisolated static let tipLarge = "com.secondvictor.downward.tip.large"
    nonisolated static let tipXLarge = "com.secondvictor.downward.tip.xlarge"

    nonisolated static let tipProductIDs = [
        tipSmall,
        tipMedium,
        tipLarge,
        tipXLarge,
    ]

    nonisolated static let allProductIDs = Set([
        supporterUnlock,
        tipSmall,
        tipMedium,
        tipLarge,
        tipXLarge,
    ])
}
