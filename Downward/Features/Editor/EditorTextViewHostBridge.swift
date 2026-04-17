import SwiftUI
import UIKit

enum EditorTextViewLayout {
    static let horizontalInset: CGFloat = 12
    static let placeholderTopPadding: CGFloat = 8
}

/// Owns the narrow UIKit bridge needed to tune the `UITextView` that SwiftUI currently uses
/// under `TextEditor`.
///
/// This exists because `TextEditor` still does not expose a SwiftUI-native API for applying
/// subtle horizontal text inset while keeping the scroll indicator near the screen edge.
/// The bridge intentionally adjusts only `textContainerInset` and `lineFragmentPadding`;
/// it does not change scroll-view content inset, which preserves the system scroll-indicator
/// placement.
///
/// Assumption: the `TextEditor` view hierarchy still contains a `UITextView` reachable from
/// this probe's surrounding UIKit container. If SwiftUI changes that implementation detail,
/// the bridge safely becomes a no-op rather than changing editing behavior.
struct EditorTextViewHostBridge: UIViewRepresentable {
    let horizontalInset: CGFloat
    let documentIdentity: URL

    func makeUIView(context: Context) -> EditorTextViewHostBridgeView {
        let view = EditorTextViewHostBridgeView()
        view.update(
            configuration: .init(
                horizontalInset: horizontalInset,
                documentIdentity: documentIdentity
            )
        )
        return view
    }

    func updateUIView(_ uiView: EditorTextViewHostBridgeView, context: Context) {
        uiView.update(
            configuration: .init(
                horizontalInset: horizontalInset,
                documentIdentity: documentIdentity
            )
        )
    }
}

final class EditorTextViewHostBridgeView: UIView {
    struct Configuration: Equatable {
        let horizontalInset: CGFloat
        let documentIdentity: URL
    }

    private weak var cachedTextView: UITextView?
    private var configuration: Configuration?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        invalidateResolvedTextView()
        applyConfigurationIfPossible()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        invalidateResolvedTextView()
        applyConfigurationIfPossible()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        applyConfigurationIfPossible()
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        applyConfigurationIfPossible()
    }

    /// Re-applies bridge configuration whenever the editor host changes document identity or
    /// layout. A document change invalidates the cached `UITextView` so we do not keep writing
    /// inset updates into a detached text view after rapid file switches.
    func update(configuration: Configuration) {
        if self.configuration?.documentIdentity != configuration.documentIdentity {
            invalidateResolvedTextView()
        }

        self.configuration = configuration
        applyConfigurationIfPossible()
    }

    private func invalidateResolvedTextView() {
        cachedTextView = nil
    }

    private func applyConfigurationIfPossible() {
        guard
            let configuration,
            let textView = resolvedTextView()
        else {
            return
        }

        var updatedInset = textView.textContainerInset
        updatedInset.left = configuration.horizontalInset
        updatedInset.right = configuration.horizontalInset

        if textView.textContainerInset != updatedInset {
            textView.textContainerInset = updatedInset
        }

        if textView.textContainer.lineFragmentPadding != 0 {
            textView.textContainer.lineFragmentPadding = 0
        }
    }

    private func resolvedTextView() -> UITextView? {
        if
            let cachedTextView,
            cachedTextView.window === window,
            cachedTextView.superview != nil
        {
            return cachedTextView
        }

        let textView = nearestTextView()
        cachedTextView = textView
        return textView
    }
}

private extension UIView {
    func nearestTextView() -> UITextView? {
        var currentView: UIView? = self

        while let view = currentView {
            if let textView = view.findSubview(of: UITextView.self) {
                return textView
            }

            currentView = view.superview
        }

        return nil
    }

    func findSubview<T: UIView>(of type: T.Type) -> T? {
        for subview in subviews {
            if let matchingView = subview as? T {
                return matchingView
            }

            if let matchingDescendant = subview.findSubview(of: type) {
                return matchingDescendant
            }
        }

        return nil
    }
}
