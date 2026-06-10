import AppKit
import SwiftUI

/// A borderless, always-on-top, draggable floating panel that hosts the SwiftUI card.
/// Sizes itself to the card's fitting size and does not steal focus from other apps.
final class HUDPanel: NSPanel {
    init(store: QuotaStore, onClose: @escaping () -> Void, onSettings: @escaping () -> Void) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 240),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        // Stay above all app windows, across every Space and over other apps' full-screen.
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isMovableByWindowBackground = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        hidesOnDeactivate = false

        let root = HUDView(store: store, onClose: onClose, onSettings: onSettings)
        let host = NSHostingView(rootView: root)
        host.translatesAutoresizingMaskIntoConstraints = false
        contentView = host

        // size the panel to the SwiftUI card
        let fitting = host.fittingSize
        setContentSize(fitting)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
