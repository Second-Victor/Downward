import UIKit

enum MarkdownCodeBackgroundKind: Int {
    case inline
    case block
}

extension NSAttributedString.Key {
    nonisolated static let markdownCodeBackgroundKind = NSAttributedString.Key("Downward.MarkdownCodeBackgroundKind")
    nonisolated static let markdownBlockquoteDepth = NSAttributedString.Key("Downward.MarkdownBlockquoteDepth")
    nonisolated static let markdownBlockquoteGroupID = NSAttributedString.Key("Downward.MarkdownBlockquoteGroupID")
}

final class MarkdownCodeBackgroundLayoutManager: NSLayoutManager {
    private let horizontalPadding: CGFloat = 4
    private let verticalPadding: CGFloat = 1
    private let cornerRadius: CGFloat = 4
    private let blockquoteBarWidth: CGFloat = 6
    private let blockquoteBarSpacing: CGFloat = 0
    private let blockquoteBarInset: CGFloat = 0
    private let blockquoteBarCornerRadius: CGFloat = 2
    private let blockquoteBackgroundInset = UIEdgeInsets(top: 2, left: 2, bottom: 2, right: 2)
    private let blockquoteBackgroundCornerRadius: CGFloat = 4

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

        textStorage.enumerateAttribute(.markdownBlockquoteGroupID, in: characterRange) { value, range, _ in
            guard let groupID = value as? Int else {
                return
            }

            let glyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let visibleGlyphRange = NSIntersectionRange(glyphRange, glyphsToShow)
            guard visibleGlyphRange.length > 0 else {
                return
            }

            self.drawBlockquoteBlock(
                forGlyphRange: visibleGlyphRange,
                characterRange: range,
                groupID: groupID,
                at: origin
            )
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

    nonisolated private func drawBlockquoteBlock(
        forGlyphRange glyphRange: NSRange,
        characterRange: NSRange,
        groupID: Int,
        at origin: CGPoint
    ) {
        guard let textStorage else {
            return
        }

        struct BlockquoteLineFragment {
            let fragmentRect: CGRect
            let usedRect: CGRect
            let depth: Int
        }

        var fragments: [BlockquoteLineFragment] = []
        enumerateLineFragments(forGlyphRange: glyphRange) { _, usedRect, textContainer, lineGlyphRange, _ in
            guard NSIntersectionRange(lineGlyphRange, glyphRange).length > 0 else {
                return
            }

            let lineCharacterRange = self.characterRange(
                forGlyphRange: lineGlyphRange,
                actualGlyphRange: nil
            )
            guard
                let lineDepth = textStorage.attribute(
                    .markdownBlockquoteDepth,
                    at: lineCharacterRange.location,
                    effectiveRange: nil
                ) as? Int,
                let lineGroupID = textStorage.attribute(
                    .markdownBlockquoteGroupID,
                    at: lineCharacterRange.location,
                    effectiveRange: nil
                ) as? Int,
                lineGroupID == groupID
            else {
                return
            }

            let fragmentRect = self.lineFragmentRect(forGlyphAt: lineGlyphRange.location, effectiveRange: nil, withoutAdditionalLayout: true)
            let containerOrigin = self.location(forGlyphAt: lineGlyphRange.location)
            let adjustedFragmentRect = CGRect(
                x: fragmentRect.minX,
                y: fragmentRect.minY,
                width: textContainer.size.width,
                height: fragmentRect.height
            )
            _ = containerOrigin
            fragments.append(
                BlockquoteLineFragment(
                    fragmentRect: adjustedFragmentRect,
                    usedRect: usedRect,
                    depth: lineDepth
                )
            )
        }

        guard fragments.isEmpty == false else {
            return
        }

        var backgroundRect = fragments[0].fragmentRect
        for fragment in fragments.dropFirst() {
            backgroundRect = backgroundRect.union(fragment.fragmentRect)
        }
        backgroundRect = backgroundRect
            .inset(by: UIEdgeInsets(
                top: -blockquoteBackgroundInset.top,
                left: -blockquoteBackgroundInset.left,
                bottom: -blockquoteBackgroundInset.bottom,
                right: -blockquoteBackgroundInset.right
            ))
            .offsetBy(dx: origin.x, dy: origin.y)

        let backgroundPath = UIBezierPath(
            roundedRect: backgroundRect,
            cornerRadius: blockquoteBackgroundCornerRadius
        )
        UIColor.secondarySystemFill.setFill()
        backgroundPath.fill()

        let maxDepth = fragments.map(\.depth).max() ?? 0
        guard maxDepth > 0 else {
            return
        }

        for level in 1...maxDepth {
            let levelFragments = fragments.filter { $0.depth >= level }
            guard levelFragments.isEmpty == false else {
                continue
            }

            var guideRect = CGRect.null
            for fragment in levelFragments {
                let rect = CGRect(
                    x: fragment.usedRect.minX,
                    y: fragment.fragmentRect.minY + 1,
                    width: max(fragment.usedRect.width, 0),
                    height: max(fragment.fragmentRect.height - 2, 0)
                )
                guideRect = guideRect.union(rect)
            }

            let guideX = backgroundRect.minX + CGFloat(level - 1) * (blockquoteBarWidth + blockquoteBarSpacing)
            let finalGuideRect = CGRect(
                x: guideX,
                y: guideRect.minY + origin.y,
                width: blockquoteBarWidth,
                height: guideRect.height
            )
            let guidePath = UIBezierPath(
                roundedRect: finalGuideRect,
                cornerRadius: blockquoteBarCornerRadius
            )
            UIColor.tertiaryLabel.setFill()
            guidePath.fill()
        }
    }
}
