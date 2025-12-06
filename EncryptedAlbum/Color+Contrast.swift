import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

#if canImport(AppKit)
import AppKit
#endif

// Utilities for computing perceived luminance and choosing a readable
// black/white foreground color for a given background Color.
//
// Uses sRGB -> linear conversion and WCAG contrast ratio test to pick the
// best foreground (black or white). This is a best-effort approach for
// dynamically-generated SwiftUI Colors and tints.
extension Color {
    /// Convert SwiftUI Color to UIColor when possible (iOS/tvOS). Returns nil on macOS.
    func toUIColor() -> UIColor? {
        #if canImport(UIKit)
        // UIColor(Color) is available on iOS 14+, and handles dynamic colors.
        return UIColor(self)
        #else
        return nil
        #endif
    }

    /// Returns the relative luminance (0..1) for this color in sRGB space.
    /// Uses the standard linearization formula from WCAG.
    func relativeLuminance() -> CGFloat? {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0

        // Prefer UIKit on iOS/tvOS, fall back to AppKit on macOS.
        #if canImport(UIKit)
        if let ui = toUIColor(), ui.getRed(&r, green: &g, blue: &b, alpha: &a) {
            return Self.computeLuminance(r: r, g: g, b: b)
        }
        #endif

        #if canImport(AppKit)
        if let converted = NSColor(self).usingColorSpace(.sRGB),
           converted.getRed(&r, green: &g, blue: &b, alpha: &a) {
            return Self.computeLuminance(r: r, g: g, b: b)
        }
        #endif

        return nil
    }

    private static func computeLuminance(r: CGFloat, g: CGFloat, b: CGFloat) -> CGFloat {
        func linearize(_ c: CGFloat) -> CGFloat {
            if c <= 0.03928 { return c / 12.92 }
            return pow((c + 0.055) / 1.055, 2.4)
        }

        let R = linearize(r)
        let G = linearize(g)
        let B = linearize(b)

        // Relative luminance formula
        return 0.2126 * R + 0.7152 * G + 0.0722 * B
    }

    /// Returns either .black or .white depending on which gives a higher contrast
    /// ratio against this color. It picks the better of the two (and will prefer
    /// the one with the larger ratio even if neither reaches 4.5:1 — this is
    /// still helpful for decorative chips where only binary black/white is allowed).
    func idealTextColorAgainstBackground() -> Color {
        // Background luminance L (0..1). Create contrast ratios with black and white.
        guard let L = relativeLuminance() else {
            // If we couldn't compute, fall back to a sensible default that works
            // well in most themes.
            return Color.primary
        }

        // Contrast ratios per WCAG
        // contrast with black: (L + 0.05) / (0 + 0.05)
        let contrastBlack = ((Double(L) + 0.05) / 0.05)
        // contrast with white: (1 + 0.05) / (L + 0.05)
        let contrastWhite = (1.05 / (Double(L) + 0.05))

        return contrastBlack >= contrastWhite ? Color.black : Color.white
    }
}
