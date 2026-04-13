import Foundation

enum DocumentConflictState: Equatable, Sendable {
    case none
    case needsResolution(DocumentConflict)
    case preservingEdits(DocumentConflict)

    var isConflicted: Bool {
        activeConflict != nil
    }

    var activeConflict: DocumentConflict? {
        switch self {
        case .none:
            nil
        case let .needsResolution(conflict), let .preservingEdits(conflict):
            conflict
        }
    }

    var needsResolution: Bool {
        if case .needsResolution = self {
            return true
        }

        return false
    }

    var isPreservingEdits: Bool {
        if case .preservingEdits = self {
            return true
        }

        return false
    }
}
