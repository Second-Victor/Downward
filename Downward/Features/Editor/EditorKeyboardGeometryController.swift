import UIKit

final class EditorKeyboardGeometryController: NSObject {
    struct ViewportInsetsSnapshot: Equatable {
        let keyboardOverlapInset: CGFloat
        let contentInsetBottom: CGFloat
        let verticalScrollIndicatorInsetBottom: CGFloat
    }

    weak var activeTextView: EditorChromeAwareTextView?

    private let notificationCenter: NotificationCenter
    private var isObservingKeyboard = false
    private var onKeyboardFrameApplied: (() -> Void)?
    private var onKeyboardHideApplied: (() -> Void)?

    init(notificationCenter: NotificationCenter = .default) {
        self.notificationCenter = notificationCenter
    }

    deinit {
        if isObservingKeyboard {
            notificationCenter.removeObserver(self)
        }
    }

    func attach(
        to textView: EditorChromeAwareTextView,
        onKeyboardFrameApplied: @escaping () -> Void,
        onKeyboardHideApplied: @escaping () -> Void
    ) {
        activeTextView = textView
        self.onKeyboardFrameApplied = onKeyboardFrameApplied
        self.onKeyboardHideApplied = onKeyboardHideApplied

        guard isObservingKeyboard == false else {
            return
        }

        notificationCenter.addObserver(
            self,
            selector: #selector(keyboardWillChangeFrame(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
        isObservingKeyboard = true
    }

    /// Match the prototype behavior: reserve the full keyboard overlap in the scroll view insets
    /// and let the transparent accessory simply overlay the text view content.
    func viewportInsetsSnapshot(for textView: UITextView) -> ViewportInsetsSnapshot {
        let keyboardOverlapInset = (textView as? EditorChromeAwareTextView)?.keyboardOverlapInset ?? 0
        let contentInsetBottom = max(0, keyboardOverlapInset)

        return ViewportInsetsSnapshot(
            keyboardOverlapInset: keyboardOverlapInset,
            contentInsetBottom: contentInsetBottom,
            verticalScrollIndicatorInsetBottom: contentInsetBottom
        )
    }

    func applyKeyboardOverlap(_ overlap: CGFloat, to textView: UITextView) {
        if let textView = textView as? EditorChromeAwareTextView {
            textView.keyboardOverlapInset = max(0, overlap)
        }
        updateKeyboardBottomInsets(for: textView)
    }

    private func updateKeyboardBottomInsets(for textView: UITextView) {
        let viewportInsetsSnapshot = viewportInsetsSnapshot(for: textView)

        var updatedContentInset = textView.contentInset
        updatedContentInset.bottom = viewportInsetsSnapshot.contentInsetBottom
        if textView.contentInset != updatedContentInset {
            textView.contentInset = updatedContentInset
        }

        var updatedVerticalScrollIndicatorInsets = textView.verticalScrollIndicatorInsets
        updatedVerticalScrollIndicatorInsets.bottom = viewportInsetsSnapshot.verticalScrollIndicatorInsetBottom
        if textView.verticalScrollIndicatorInsets != updatedVerticalScrollIndicatorInsets {
            textView.verticalScrollIndicatorInsets = updatedVerticalScrollIndicatorInsets
        }
    }

    @objc
    private func keyboardWillChangeFrame(_ notification: Notification) {
        guard
            let textView = activeTextView,
            let endFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
            let window = textView.window
        else {
            return
        }

        let keyboardFrameInView = textView.convert(endFrame, from: window.screen.coordinateSpace)
        let overlap = max(0, textView.bounds.maxY - keyboardFrameInView.minY)

        animateAlongsideKeyboard(notification) {
            self.applyKeyboardOverlap(overlap, to: textView)
        } completion: {
            self.applyKeyboardOverlap(overlap, to: textView)
            self.scrollToCaret(in: textView)
            self.onKeyboardFrameApplied?()
        }
    }

    @objc
    private func keyboardWillHide(_ notification: Notification) {
        guard let textView = activeTextView else {
            return
        }

        animateAlongsideKeyboard(notification) {
            self.applyKeyboardOverlap(0, to: textView)
        } completion: {
            self.applyKeyboardOverlap(0, to: textView)
            self.onKeyboardHideApplied?()
        }
    }

    private func animateAlongsideKeyboard(
        _ notification: Notification,
        animations: @escaping () -> Void,
        completion: @escaping () -> Void = {}
    ) {
        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval ?? 0.25
        let curveRaw = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt ?? 0
        let options = UIView.AnimationOptions(rawValue: curveRaw << 16)

        UIView.animate(withDuration: duration, delay: 0, options: options) {
            animations()
        } completion: { _ in
            completion()
        }
    }

    private func scrollToCaret(in textView: UITextView) {
        guard let selectedRange = textView.selectedTextRange else {
            return
        }

        let caretRect = textView.caretRect(for: selectedRange.end)
        let visibleRect = caretRect.insetBy(dx: 0, dy: -20)
        textView.scrollRectToVisible(visibleRect, animated: true)
    }
}
