import UIKit

extension UIColor {
    var wcagRelativeLuminance: Double {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        let linearize: (CGFloat) -> Double = { component in
            let value = Double(component)
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linearize(r) + 0.7152 * linearize(g) + 0.0722 * linearize(b)
    }

    func wcagContrastRatio(against other: UIColor) -> Double {
        let lighter = max(wcagRelativeLuminance, other.wcagRelativeLuminance)
        let darker = min(wcagRelativeLuminance, other.wcagRelativeLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    func darkerShade() -> UIColor {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0

        if getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) {
            return UIColor(
                hue: hue,
                saturation: min(saturation * 1.05, 1),
                brightness: max(brightness * 0.78, 0),
                alpha: alpha
            )
        }

        var white: CGFloat = 0
        if getWhite(&white, alpha: &alpha) {
            return UIColor(white: max(white * 0.72, 0), alpha: alpha)
        }

        return self
    }
}
