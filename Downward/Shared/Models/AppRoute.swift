import Foundation

enum AppRoute: Hashable, Sendable {
    case editor(URL)
    case trustedEditor(URL, String)
    case settings

    var isEditor: Bool {
        switch self {
        case .editor, .trustedEditor:
            return true
        case .settings:
            return false
        }
    }

    var editorURL: URL? {
        switch self {
        case let .editor(url), let .trustedEditor(url, _):
            return url
        case .settings:
            return nil
        }
    }

    var editorRelativePath: String? {
        if case let .trustedEditor(_, relativePath) = self {
            return relativePath
        }

        return nil
    }

    func replacingEditorURL(oldURL: URL, newURL: URL) -> AppRoute {
        guard editorURL == oldURL else {
            return self
        }

        switch self {
        case .editor:
            return .editor(newURL)
        case let .trustedEditor(_, relativePath):
            return .trustedEditor(newURL, relativePath)
        case .settings:
            return .settings
        }
    }
}
