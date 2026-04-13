import Foundation

/// Maps internal app failures into the minimal copy that views should present.
protocol ErrorReporter: Sendable {
    func report(_ error: AppError, context: String)
    func makeUserFacingError(from error: AppError) -> UserFacingError
}

struct StubErrorReporter: ErrorReporter {
    private let logger: DebugLogger

    init(logger: DebugLogger) {
        self.logger = logger
    }

    func report(_ error: AppError, context: String) {
        logger.log("\(context): \(error.localizedDescription)")
    }

    func makeUserFacingError(from error: AppError) -> UserFacingError {
        switch error {
        case .missingWorkspaceSelection:
            UserFacingError(
                title: "Choose a Workspace",
                message: "No workspace is available yet.",
                recoverySuggestion: "Open a workspace to continue."
            )
        case let .workspaceRestoreFailed(details):
            UserFacingError(
                title: "Unable to Restore Workspace",
                message: details,
                recoverySuggestion: "Try again or choose a different workspace."
            )
        case let .workspaceAccessInvalid(displayName):
            UserFacingError(
                title: "Workspace Needs Reconnect",
                message: "\(displayName) is no longer available.",
                recoverySuggestion: "Reconnect the folder to keep editing."
            )
        case let .fileOperationFailed(action, name, details):
            UserFacingError(
                title: action,
                message: "\(name): \(details)",
                recoverySuggestion: "Try again from the browser."
            )
        case let .documentUnavailable(name):
            UserFacingError(
                title: "Document Unavailable",
                message: "\(name) is no longer available at this location.",
                recoverySuggestion: "Return to the browser and refresh if the file moved."
            )
        case let .documentOpenFailed(name, details):
            UserFacingError(
                title: "Can’t Open Document",
                message: "\(name) could not be loaded. \(details)",
                recoverySuggestion: "Return to the browser and try again."
            )
        case let .documentSaveFailed(name, details):
            UserFacingError(
                title: "Save Failed",
                message: "\(name) could not be saved. \(details)",
                recoverySuggestion: "Keep editing and try again."
            )
        case let .unsupportedOperation(details),
             let .stubFailure(details):
            UserFacingError(
                title: "Not Available Yet",
                message: details,
                recoverySuggestion: "This flow is stubbed for the current phase."
            )
        }
    }
}
