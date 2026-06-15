import AppKit
import SwiftUI

/// NSHostingView that keeps its window sized to the SwiftUI content
/// (so scaling the card or changing rows resizes the panel), anchored top-left.
final class AutoSizingHostingView<V: View>: NSHostingView<V> {
    override func layout() {
        super.layout()
        guard let win = window else { return }
        let target = fittingSize
        guard target.width > 1, target.height > 1, win.frame.size != target else { return }
        var f = win.frame
        f.origin.y += f.size.height - target.height // keep the top edge fixed
        f.size = target
        win.setFrame(f, display: true)
    }
}

/// Borderless, always-on-top, draggable floating panel hosting the SwiftUI card.
final class HUDPanel: NSPanel {
    private var cursorMonitor: Any?

    init(store: QuotaStore, onClose: @escaping () -> Void, onSettings: @escaping () -> Void, onPin: @escaping () -> Void) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 240),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isMovableByWindowBackground = true
        acceptsMouseMovedEvents = true   // so resize handles can update the cursor on hover
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        hidesOnDeactivate = false

        let root = HUDView(store: store, onClose: onClose, onSettings: onSettings, onPin: onPin)
        let host = AutoSizingHostingView(rootView: root)
        host.translatesAutoresizingMaskIntoConstraints = false
        contentView = host
        setContentSize(host.fittingSize)

        // Ultimate cursor fix: on every mouse move over this panel, hit-test what's
        // under the pointer and set the right cursor directly. This bypasses
        // NSTrackingArea entirely (which is unreliable on a non-key floating panel,
        // and goes stale across resizes), so the resize handles always flip the
        // cursor — even right after the card was scaled.
        cursorMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.refreshResizeCursor(event)
            return event
        }
    }

    private func refreshResizeCursor(_ event: NSEvent) {
        guard event.window === self, let content = contentView else { return }
        let pt = event.locationInWindow
        if let knob = content.hitTest(pt) as? DragSurface.DragNSView {
            knob.cursor.set()
        } else if content.bounds.contains(content.convert(pt, from: nil)) {
            NSCursor.arrow.set()
        }
    }

    deinit {
        if let m = cursorMonitor { NSEvent.removeMonitor(m) }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
