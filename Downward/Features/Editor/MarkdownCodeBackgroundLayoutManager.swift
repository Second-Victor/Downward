import UIKit

enum MarkdownCodeBackgroundKind: Int {
    case inline
    case block
}

extension NSAttributedString.Key {
    nonisolated static let markdownCodeBackgroundKind = NSAttributedString.Key("Downward.MarkdownCodeBackgroundKind")
}

final class MarkdownCodeBackgroundLayoutManager: NSLayoutManager {
    private let horizontalPadding: CGFloat = 4
    private let verticalPadding: CGFloat = 1
    private let cornerRadius: CGFloat = 3

    nonisolated override init() {
        super.init()
    }

    nonisolated required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    nonisolated override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)

        guard let textStorage else {
            return
        }

        let characterRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        textStorage.enumerateAttribute(.markdownCodeBackgroundKind, in: characterRange) { value, range, _ in
            guard
                let rawValue = value as? Int,
                let kind = MarkdownCodeBackgroundKind(rawValue: rawValue)
            else {
                return
            }

            let glyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let visibleGlyphRange = NSIntersectionRange(glyphRange, glyphsToShow)
            guard visibleGlyphRange.length > 0 else {
                return
            }

            switch kind {
            case .inline:
                self.drawInlineBackground(forGlyphRange: visibleGlyphRange, at: origin)
            case .block:
                self.drawBlockBackground(forGlyphRange: visibleGlyphRange, at: origin)
            }
        }
    }

    nonisolated private func drawInlineBackground(
        forGlyphRange glyphRange: NSRange,
        at origin: CGPoint
    ) {
        guard let textContainer = textContainers.first else {
            return
        }

        enumerateEnclosingRects(
            forGlyphRange: glyphRange,
            withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
            in: textContainer
        ) { rect, _ in
            let expandedRect = rect
                .insetBy(dx: -self.horizontalPadding, dy: -self.verticalPadding)
                .offsetBy(dx: origin.x, dy: origin.y)
            let path = UIBezierPath(
                roundedRect: expandedRect,
                cornerRadius: self.cornerRadius
            )
            UIColor.secondarySystemFill.setFill()
            path.fill()
        }
    }

    nonisolated private func drawBlockBackground(
        forGlyphRange glyphRange: NSRange,
        at origin: CGPoint
    ) {
        var unionRect: CGRect?
        enumerateLineFragments(forGlyphRange: glyphRange) { usedRect, _, _, lineGlyphRange, _ in
            guard NSIntersectionRange(lineGlyphRange, glyphRange).length > 0 else {
                return
            }

            unionRect = unionRect.map { $0.union(usedRect) } ?? usedRect
        }

        guard let unionRect else {
            return
        }

        let expandedRect = unionRect
            .insetBy(dx: -horizontalPadding, dy: -verticalPadding)
            .offsetBy(dx: origin.x, dy: origin.y)
        let path = UIBezierPath(
            roundedRect: expandedRect,
            cornerRadius: cornerRadius
        )
        UIColor.secondarySystemFill.setFill()
        path.fill()
    }
}
