import Foundation

struct DocumentConflict: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case modifiedOnDisk
        case missingOnDisk
    }

    let kind: Kind
    let error: UserFacingError
}
