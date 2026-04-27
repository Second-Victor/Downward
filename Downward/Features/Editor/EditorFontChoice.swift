import Foundation

enum EditorFontChoice: String, Codable, CaseIterable, Sendable {
    case `default`
    case systemMonospaced
    case menlo
    case courier
    case courierNew
    case newYork
    case georgia

    var displayName: String {
        switch self {
        case .default:
            "SF Pro"
        case .systemMonospaced:
            "System Monospaced"
        case .menlo:
            "Menlo"
        case .courier:
            "Courier"
        case .courierNew:
            "Courier New"
        case .newYork:
            "New York"
        case .georgia:
            "Georgia"
        }
    }

    var isMonospaced: Bool {
        switch self {
        case .systemMonospaced, .menlo, .courier, .courierNew:
            true
        case .default, .newYork, .georgia:
            false
        }
    }

    var runtimeFontName: String? {
        switch self {
        case .default, .systemMonospaced, .newYork:
            nil
        case .menlo:
            "Menlo-Regular"
        case .courier:
            "Courier"
        case .courierNew:
            "CourierNewPSMT"
        case .georgia:
            "Georgia"
        }
    }
}
