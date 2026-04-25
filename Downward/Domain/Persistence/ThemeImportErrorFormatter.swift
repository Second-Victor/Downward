import Foundation

enum ThemeImportErrorFormatter {
    static func message(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           description.isEmpty == false {
            return description
        }

        return "Could not import the theme JSON: \(error.localizedDescription)"
    }
}
