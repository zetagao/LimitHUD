import AppKit
import SwiftUI

/// Subtle bottom-right resize corner.
struct CornerHint: View {
    let s: CGFloat

    var body: some View {
        CornerTicks()
            .stroke(Color.white.opacity(0.28), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
            .frame(width: 11 * s, height: 11 * s)
            .allowsHitTesting(false)
    }
}

private struct CornerTicks: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        for o in stride(from: 0.0, through: r.width, by: r.width / 2.4) {
            p.move(to: CGPoint(x: r.maxX - o, y: r.maxY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - o))
        }
        return p
    }
}

/// Subtle right-edge width hint.
struct EdgeHint: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(Color.white.opacity(0.22))
            .frame(width: 2, height: 16)
            .allowsHitTesting(false)
    }
}

/// Transparent AppKit drag surface that opts out of window-moving.
struct DragSurface: NSViewRepresentable {
    var cursor: NSCursor
    var onChanged: (CGSize) -> Void
    var onEnded: (CGSize) -> Void = { _ in }

    func makeNSView(context: Context) -> DragNSView {
        let v = DragNSView()
        v.cursor = cursor
        v.onChanged = onChanged
        v.onEnded = onEnded
        return v
    }

    func updateNSView(_ v: DragNSView, context: Context) {
        v.cursor = cursor
        v.onChanged = onChanged
        v.onEnded = onEnded
    }

    // Hover cursor is handled centrally by HUDPanel's mouse-moved monitor (which
    // hit-tests this view) — far more reliable than per-view tracking areas on a
    // non-key floating panel. This view only owns the drag itself.
    final class DragNSView: NSView {
        var cursor: NSCursor = .arrow
        var onChanged: ((CGSize) -> Void)?
        var onEnded: ((CGSize) -> Void)?
        private var startScreen: NSPoint = .zero

        override var mouseDownCanMoveWindow: Bool { false }

        override func mouseDown(with e: NSEvent) {
            startScreen = NSEvent.mouseLocation
            cursor.push()           // force this cursor for the duration of the drag
        }

        override func mouseDragged(with e: NSEvent) {
            cursor.set()
            let p = NSEvent.mouseLocation
            onChanged?(CGSize(width: p.x - startScreen.x, height: p.y - startScreen.y))
        }

        override func mouseUp(with e: NSEvent) {
            let p = NSEvent.mouseLocation
            onEnded?(CGSize(width: p.x - startScreen.x, height: p.y - startScreen.y))
            NSCursor.pop()
        }
    }
}

extension NSCursor {
    static var nwseResize: NSCursor {
        let cls: AnyObject = NSCursor.self
        let sel = NSSelectorFromString("_windowResizeNorthWestSouthEastCursor")
        if cls.responds(to: sel), let v = cls.perform(sel)?.takeUnretainedValue() as? NSCursor {
            return v
        }
        return .crosshair
    }
}

/// System blur behind the panel.
struct FrostedBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        v.appearance = NSAppearance(named: .darkAqua)
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(RoundedRectangle(cornerRadius: 5)
                .fill(configuration.isPressed ? Theme.hoverFill : Color.clear))
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
