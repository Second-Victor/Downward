import Foundation

enum AppError: Error, Equatable, LocalizedError, Sendable {
    case missingWorkspaceSelection
    case workspaceRestoreFailed(details: String)
    case workspaceAccessInvalid(displayName: String)
    case fileOperationFailed(action: String, name: String, details: String)
    case documentUnavailable(name: String)
    case documentOpenFailed(name: String, details: String)
    case documentSaveFailed(name: String, details: String)
    case unsupportedOperation(details: String)
    case stubFailure(details: String)

    var errorDescription: String? {
        switch self {
        case .missingWorkspaceSelection:
            "No workspace has been selected."
        case let .workspaceRestoreFailed(details):
            "Workspace restore failed: \(details)"
        case let .workspaceAccessInvalid(displayName):
            "Workspace access is invalid for \(displayName)."
        case let .fileOperationFailed(action, name, details):
            "\(action) failed for \(name): \(details)"
        case let .documentUnavailable(name):
            "The document \(name) is unavailable."
        case let .documentOpenFailed(name, details):
            "The document \(name) could not be opened: \(details)"
        case let .documentSaveFailed(name, details):
            "The document \(name) could not be saved: \(details)"
        case let .unsupportedOperation(details):
            "Unsupported operation: \(details)"
        case let .stubFailure(details):
            "Stub failure: \(details)"
        }
    }
}
