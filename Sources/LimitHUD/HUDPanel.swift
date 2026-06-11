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
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
