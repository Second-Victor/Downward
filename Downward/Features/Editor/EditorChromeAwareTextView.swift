import UIKit

class EditorChromeAwareTextView: UITextView {
    var keyboardAccessoryToolbarView: KeyboardAccessoryToolbarView?
    var undoAccessoryItem: UIBarButtonItem?
    var redoAccessoryItem: UIBarButtonItem?
    var dismissAccessoryItem: UIBarButtonItem?
    var keyboardOverlapInset: CGFloat = 0
}
