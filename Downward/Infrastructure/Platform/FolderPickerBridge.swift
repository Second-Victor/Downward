import Foundation
import UniformTypeIdentifiers

protocol FolderPickerBridge: Sendable {
    var allowedContentTypes: [UTType] { get }
    func selectedURL(from result: Result<[URL], Error>) -> Result<URL?, UserFacingError>
}

struct LiveFolderPickerBridge: FolderPickerBridge {
    let allowedContentTypes: [UTType] = [.folder]

    func selectedURL(from result: Result<[URL], Error>) -> Result<URL?, UserFacingError> {
        switch result {
        case let .success(urls):
            return .success(urls.first)
        case let .failure(error):
            let nsError = error as NSError

            if nsError.domain == NSCocoaErrorDomain, nsError.code == NSUserCancelledError {
                return .success(nil)
            }

            return .failure(
                UserFacingError(
                    title: "Can’t Choose Folder",
                    message: "Files did not return a usable folder.",
                    recoverySuggestion: "Try choosing the folder again."
                )
            )
        }
    }
}

struct StubFolderPickerBridge: FolderPickerBridge {
    let allowedContentTypes: [UTType] = [.folder]

    func selectedURL(from result: Result<[URL], Error>) -> Result<URL?, UserFacingError> {
        switch result {
        case let .success(urls):
            return .success(urls.first)
        case .failure:
            return .failure(
                UserFacingError(
                    title: "Folder Picking Unavailable",
                    message: "This preview uses stub workspace state instead of Files.",
                    recoverySuggestion: "Use the injected preview state."
                )
            )
        }
    }
}
