import Foundation

struct UserFacingError: Error, Equatable, Hashable, Identifiable, Sendable {
    let title: String
    let message: String
    let recoverySuggestion: String?

    var id: String {
        [title, message, recoverySuggestion ?? ""].joined(separator: "::")
    }
}
