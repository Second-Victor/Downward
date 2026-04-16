import Foundation

enum AppRoute: Hashable, Sendable {
    case editor(URL)
    case settings

    var isEditor: Bool {
        if case .editor = self {
            return true
        }

        return false
    }

    var editorURL: URL? {
        if case let .editor(url) = self {
            return url
        }

        return nil
    }

    func replacingEditorURL(oldURL: URL, newURL: URL) -> AppRoute {
        guard editorURL == oldURL else {
            return self
        }

        return .editor(newURL)
    }
}
