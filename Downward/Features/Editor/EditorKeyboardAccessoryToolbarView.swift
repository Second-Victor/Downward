import UIKit

final class KeyboardAccessoryToolbarView: UIView {
    static let bottomSpacing: CGFloat = 8

    let toolbar = UIToolbar()
    let formatButton: UIBarButtonItem
    let undoButton: UIBarButtonItem
    let redoButton: UIBarButtonItem
    let dismissButton: UIBarButtonItem
    private var resolvedTheme: ResolvedEditorTheme
    private let showsDismissButton: Bool

    init(
        target: AnyObject,
        undoAction: Selector,
        redoAction: Selector,
        dismissAction: Selector,
        resolvedTheme: ResolvedEditorTheme,
        formatMenu: UIMenu = UIMenu(children: []),
        showsDismissButton: Bool = UIDevice.current.userInterfaceIdiom != .pad
    ) {
        self.resolvedTheme = resolvedTheme
        self.showsDismissButton = showsDismissButton
        formatButton = UIBarButtonItem(
            title: nil,
            image: UIImage(systemName: "textformat"),
            primaryAction: nil,
            menu: formatMenu
        )
        formatButton.accessibilityLabel = "Format"

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

        // Match the prototype: let UIKit's keyboard host render its own blurred/translucent
        // background. Painting the accessory view (or walking up the superview chain to
        // paint the private keyboard host wrappers) caused the whole screen to adopt the
        // editor background color during presentation and interactive dismissal.
        backgroundColor = .clear
        isOpaque = false
        autoresizingMask = [.flexibleWidth, .flexibleHeight]

        addSubview(toolbar)
        toolbar.autoresizingMask = [.flexibleWidth]
        let commandSpacer = UIBarButtonItem(systemItem: .fixedSpace)
        commandSpacer.width = 8
        toolbar.items = showsDismissButton
            ? [formatButton, .flexibleSpace(), undoButton, redoButton, commandSpacer, dismissButton]
            : [formatButton, .flexibleSpace(), undoButton, redoButton]

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

    func updateFormatMenu(_ formatMenu: UIMenu) {
        // Kept as the narrow replacement point for future dynamic format menus. The coordinator
        // currently builds the menu once so accessory state refreshes do not churn UIKit menu items.
        formatButton.menu = formatMenu
    }

    func update(canUndo: Bool, canRedo: Bool, canDismiss: Bool) {
        undoButton.isEnabled = canUndo
        redoButton.isEnabled = canRedo
        dismissButton.isEnabled = showsDismissButton && canDismiss
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    func applyResolvedTheme(_ resolvedTheme: ResolvedEditorTheme) {
        self.resolvedTheme = resolvedTheme
        // The toolbar's tint drives the bar-button (undo / redo / dismiss) icon color.
        // Background stays clear so the keyboard host's own material shows through, which
        // keeps the accessory visually consistent with the status bar / nav bar buttons.
        toolbar.tintColor = resolvedTheme.accent
    }

    func applyChromeInterfaceStyle(_ style: UIUserInterfaceStyle) {
        overrideUserInterfaceStyle = style
        toolbar.overrideUserInterfaceStyle = style
    }
}
