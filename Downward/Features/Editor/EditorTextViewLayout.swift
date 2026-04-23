import UIKit

/// Shared spacing constants for the shipping `MarkdownEditorTextView` boundary.
enum EditorTextViewLayout {
    static let horizontalInset: CGFloat = 12
    static let contentTopInset: CGFloat = 24
    static let bottomInset: CGFloat = 12

    /// Keep the editor surface continuous under the top chrome while starting visible text below
    /// the current safe-area/navigation clearance on both iPhone and iPad.
    static func effectiveTopInset(topViewportInset: CGFloat) -> CGFloat {
        max(0, topViewportInset) + contentTopInset
    }
}
