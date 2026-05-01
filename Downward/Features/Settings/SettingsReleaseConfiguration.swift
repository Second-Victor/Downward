import Foundation

struct SettingsReleaseConfiguration: Equatable, Sendable {
    var tipsPurchasesEnabled: Bool
    var rateTheAppEnabled: Bool
    var appStoreReviewURL: URL?
    var projectURL: URL?
    var privacyPolicyURL: URL?
    var termsAndConditionsURL: URL?

    init(
        tipsPurchasesEnabled: Bool,
        rateTheAppEnabled: Bool = false,
        appStoreReviewURL: URL? = nil,
        projectURL: URL? = nil,
        privacyPolicyURL: URL? = nil,
        termsAndConditionsURL: URL? = nil
    ) {
        self.tipsPurchasesEnabled = tipsPurchasesEnabled
        self.rateTheAppEnabled = rateTheAppEnabled
        self.appStoreReviewURL = appStoreReviewURL
        self.projectURL = projectURL
        self.privacyPolicyURL = privacyPolicyURL
        self.termsAndConditionsURL = termsAndConditionsURL
    }

    static let current = SettingsReleaseConfiguration(
        tipsPurchasesEnabled: true,
        rateTheAppEnabled: false,
        appStoreReviewURL: nil,
        projectURL: URL(string: "https://secondvictor.com/public/projects/downward/downward.html"),
        privacyPolicyURL: URL(string: "https://secondvictor.com/public/projects/downward/downward-policy.html"),
        termsAndConditionsURL: URL(string: "https://secondvictor.com/public/projects/downward/downward-terms.html")
    )

    var showsTipsPage: Bool {
        tipsPurchasesEnabled
    }

    var showsRateTheApp: Bool {
        rateTheAppEnabled && appStoreReviewURL != nil
    }

    var showsLegalLinks: Bool {
        privacyPolicyURL != nil || termsAndConditionsURL != nil
    }
}
