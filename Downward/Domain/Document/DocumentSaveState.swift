import Foundation

enum DocumentSaveState: Equatable, Sendable {
    case idle
    case unsaved
    case saving
    case saved(Date)
    case failed(UserFacingError)

    var statusText: String {
        switch self {
        case .idle:
            "Idle"
        case .unsaved:
            "Unsaved"
        case .saving:
            "Saving"
        case .saved:
            "Saved"
        case .failed:
            "Save Failed"
        }
    }

    var showsUnsavedIndicator: Bool {
        switch self {
        case .unsaved, .saving, .failed:
            true
        case .idle, .saved:
            false
        }
    }
}
