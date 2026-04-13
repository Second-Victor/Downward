import Foundation

enum WorkspaceAccessState: Equatable, Sendable {
    case noneSelected
    case restorable(displayName: String)
    case ready(displayName: String)
    case invalid(displayName: String, error: UserFacingError)

    var displayName: String? {
        switch self {
        case .noneSelected:
            nil
        case let .restorable(displayName),
             let .ready(displayName),
             let .invalid(displayName, _):
            displayName
        }
    }

    var invalidationError: UserFacingError? {
        if case let .invalid(_, error) = self {
            return error
        }

        return nil
    }
}
