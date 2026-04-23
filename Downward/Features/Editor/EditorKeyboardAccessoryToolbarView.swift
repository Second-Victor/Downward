import UIKit

final class KeyboardAccessoryToolbarView: UIView {
    static let bottomSpacing: CGFloat = 8

    let toolbar = UIToolbar()
    let undoButton: UIBarButtonItem
    let redoButton: UIBarButtonItem
    let dismissButton: UIBarButtonItem
    private var resolvedTheme: ResolvedEditorTheme

    init(
        target: AnyObject,
        undoAction: Selector,
        redoAction: Selector,
        dismissAction: Selector,
        resolvedTheme: ResolvedEditorTheme
    ) {
        self.resolvedTheme = resolvedTheme
        undoButton = UIBarButtonItem(
            image: UIImage(systemName: "arrow.uturn.backward"),
            style: .plain,
            target: target,
            action: undoAction
        )
        undoButton.accessibilityLabel = "Undo"

        redoButton = UIBarButtonItem(
            image: UIImage(systemName: "arrow.uturn.forward"),
            style: .plain,
            target: target,
            action: redoAction
        )
        redoButton.accessibilityLabel = "Redo"

        dismissButton = UIBarButtonItem(
            image: UIImage(systemName: "keyboard.chevron.compact.down"),
            style: .plain,
            target: target,
            action: dismissAction
        )
        dismissButton.accessibilityLabel = "Dismiss Keyboard"

        super.init(frame: .zero)

        isOpaque = false
        autoresizingMask = [.flexibleWidth, .flexibleHeight]

        addSubview(toolbar)
        toolbar.isOpaque = false
        toolbar.isTranslucent = true
        toolbar.autoresizingMask = [.flexibleWidth]
        toolbar.items = [undoButton, redoButton, .flexibleSpace(), dismissButton]
        applyResolvedTheme(resolvedTheme)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        let toolbarHeight = toolbar.sizeThatFits(CGSize(width: bounds.width, height: UIView.noIntrinsicMetric)).height
        return CGSize(width: UIView.noIntrinsicMetric, height: toolbarHeight + Self.bottomSpacing)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let toolbarHeight = toolbar.sizeThatFits(CGSize(width: size.width, height: UIView.noIntrinsicMetric)).height
        return CGSize(width: size.width, height: toolbarHeight + Self.bottomSpacing)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let toolbarHeight = toolbar.sizeThatFits(CGSize(width: bounds.width, height: UIView.noIntrinsicMetric)).height
        toolbar.frame = CGRect(x: 0, y: 0, width: bounds.width, height: toolbarHeight)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        applyResolvedTheme(resolvedTheme)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyResolvedTheme(resolvedTheme)
    }

    func update(canUndo: Bool, canRedo: Bool, canDismiss: Bool) {
        undoButton.isEnabled = canUndo
        redoButton.isEnabled = canRedo
        dismissButton.isEnabled = canDismiss
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    func applyResolvedTheme(_ resolvedTheme: ResolvedEditorTheme) {
        self.resolvedTheme = resolvedTheme
        isOpaque = false
        // Keep the accessory host visually transparent unless a future theme opts into painting
        // its own underlay on purpose.
        backgroundColor = resolvedTheme.keyboardAccessoryUnderlayBackground
        toolbar.backgroundColor = .clear
        toolbar.barTintColor = .clear
        toolbar.isOpaque = false
        toolbar.tintColor = resolvedTheme.accent
        applyTransparentToolbarAppearance()
    }

    /// Keep the accessory visually transparent even when the keyboard host is recreated or traits
    /// change. This is especially important once editor background colors become theme-driven.
    private func applyTransparentToolbarAppearance() {
        let appearance = UIToolbarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = .clear
        appearance.shadowColor = .clear

        toolbar.standardAppearance = appearance
        toolbar.compactAppearance = appearance
        toolbar.scrollEdgeAppearance = appearance
        if #available(iOS 15.0, *) {
            toolbar.compactScrollEdgeAppearance = appearance
        }

        toolbar.setBackgroundImage(UIImage(), forToolbarPosition: .any, barMetrics: .default)
        toolbar.setShadowImage(UIImage(), forToolbarPosition: .any)
    }
}
