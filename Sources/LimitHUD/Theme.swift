import AppKit
import SwiftUI

/// Design tokens from the Framea Design System, made appearance-adaptive.
/// Dark = the canonical Framea palette; Light = an inverted variant on #F4F4F5.
/// All colors are dynamic NSColors, so they auto-switch when the system theme changes.
enum Theme {
    // MARK: dynamic builders
    private static func dyn(_ light: NSColor, _ dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { ap in
            ap.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
    private static func hx(_ h: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((h >> 16) & 0xFF) / 255,
                green:   CGFloat((h >> 8) & 0xFF) / 255,
                blue:    CGFloat(h & 0xFF) / 255, alpha: 1)
    }
    private static func w(_ o: CGFloat) -> NSColor { NSColor(white: 1, alpha: o) }
    private static func b(_ o: CGFloat) -> NSColor { NSColor(white: 0, alpha: o) }

    // MARK: surfaces
    static let bg       = dyn(hx(0xF4F4F5), hx(0x0E0E10))
    static let surface  = dyn(hx(0xFFFFFF), hx(0x161618))
    static let surface2 = dyn(hx(0xF2F2F3), hx(0x1C1C1F))

    // MARK: ink scale
    static let ink    = dyn(hx(0x1A1A1E), hx(0xF4F4F5))
    static let inkDim = dyn(b(0.82), w(0.82))
    static let muted  = dyn(b(0.55), w(0.55))
    static let muted2 = dyn(b(0.42), w(0.36))
    static let muted3 = dyn(b(0.26), w(0.22))

    // MARK: borders / fills
    static let border    = dyn(b(0.10), w(0.08))
    static let border2   = dyn(b(0.14), w(0.12))
    static let border3   = dyn(b(0.20), w(0.18))
    static let trackBg   = dyn(b(0.09), w(0.07)) // progress-bar track
    static let hoverFill = dyn(b(0.08), w(0.10)) // icon-button pressed/hover

    // MARK: brand + semantics (darkened in light mode for contrast)
    static let accent  = dyn(hx(0x4E7A5C), hx(0x5E8C6A)) // moss
    static let success = dyn(hx(0x1FA968), hx(0x34C982))
    static let warning = dyn(hx(0xB0780A), hx(0xF5C842))
    static let ai      = dyn(hx(0x7C5CE6), hx(0xB197FC))
    static let error   = dyn(hx(0xD0303D), hx(0xE84855))

    /// Remaining-quota color ramp: healthy → caution → critical.
    static func quotaColor(remaining: Double) -> Color {
        switch remaining {
        case 0.5...:    return success
        case 0.2..<0.5: return warning
        default:        return error
        }
    }
}

extension Text {
    /// Space-Mono-style uppercase system label (IDs, counts, time).
    func monoLabel(size: CGFloat = 11, tracking: CGFloat = 1.6, color: Color = Theme.muted2) -> Text {
        self.font(.system(size: size, weight: .bold, design: .monospaced))
            .tracking(tracking)
            .foregroundColor(color)
    }
}
