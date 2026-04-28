import Foundation

struct SettingsReleaseConfiguration: Equatable, Sendable {
    var tipsPurchasesEnabled: Bool
    var appStoreReviewURL: URL?
    var privacyPolicyURL: URL?
    var termsAndConditionsURL: URL?

    static let current = SettingsReleaseConfiguration(
        tipsPurchasesEnabled: false,
        appStoreReviewURL: nil,
        privacyPolicyURL: nil,
        termsAndConditionsURL: nil
    )

    var showsTipsPage: Bool {
        tipsPurchasesEnabled
    }

    var showsRateTheApp: Bool {
        appStoreReviewURL != nil
    }

    var showsLegalLinks: Bool {
        privacyPolicyURL != nil || termsAndConditionsURL != nil
    }
}
