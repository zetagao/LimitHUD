import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = QuotaStore()
    var panel: HUDPanel!
    var hotKey: HotKeyManager!
    var statusItem: NSStatusItem!
    var settingsWC: NSWindowController?
    private var cancellables = Set<AnyCancellable>()
    /// Global mouse monitor that dismisses the transient peek card on outside click.
    private var peekMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Notifier.requestAuthorization()
        panel = HUDPanel(
            store: store,
            onClose: { [weak self] in self?.hidePanel() },
            onSettings: { [weak self] in self?.openSettings() },
            onPin: { [weak self] in self?.togglePin() }
        )
        setupStatusItem()
        // Warm all pet frames so switching characters never hitches (which froze
        // the UI on the previous pet's frame — the "flash of Lota").
        DispatchQueue.main.async { PetImage.warmAll() }
        NotificationCenter.default.addObserver(
            self, selector: #selector(panelMoved),
            name: NSWindow.didMoveNotification, object: panel)
        // Menu-bar-first: only auto-show the card if the user pinned it.
        if Settings.shared.cardPinned { showPanel() }

        hotKey = HotKeyManager { [weak self] in self?.togglePanel() }
        let s = Settings.shared
        s.hotKeyRegistered = hotKey.register(keyCode: UInt32(s.hotKeyKeyCode), carbonModifiers: UInt32(s.hotKeyModifiers))
        s.$hotKeyKeyCode.combineLatest(s.$hotKeyModifiers)
            .dropFirst()
            .sink { [weak self] code, mods in
                Settings.shared.hotKeyRegistered =
                    self?.hotKey.register(keyCode: UInt32(code), carbonModifiers: UInt32(mods)) ?? false
            }
            .store(in: &cancellables)

        // Live menu-bar refresh when data or menu-bar prefs change.
        store.$providers
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusItem() }
            .store(in: &cancellables)
        s.$menuBarSource.dropFirst()
            .sink { [weak self] _ in self?.updateStatusItem() }
            .store(in: &cancellables)
        s.$menuBarQuietHealthy.dropFirst()
            .sink { [weak self] _ in self?.updateStatusItem() }
            .store(in: &cancellables)
        s.$hiddenWindows.dropFirst()
            .sink { [weak self] _ in self?.updateStatusItem() }
            .store(in: &cancellables)
    }

    func openSettings() {
        if settingsWC == nil {
            let host = NSHostingController(rootView: SettingsView(store: store))
            let win = NSWindow(contentViewController: host)
            win.title = "LimitHUD Settings"
            win.styleMask = [.titled, .closable, .fullSizeContentView]
            win.titleVisibility = .hidden
            win.titlebarAppearsTransparent = true
            win.isMovableByWindowBackground = true
            win.backgroundColor = .clear
            win.isOpaque = false
            win.appearance = NSAppearance(named: .darkAqua)   // match the card's dark look
            win.isReleasedWhenClosed = false
            win.setContentSize(NSSize(width: 380, height: 560))
            settingsWC = NSWindowController(window: win)
        }
        settingsWC?.window?.center()
        NSApp.activate(ignoringOtherApps: true)
        settingsWC?.showWindow(nil)
    }

    // MARK: Menu bar button

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "AI Quota · click to toggle / right-click for menu (⌘⇧L)"
        }
        updateStatusItem()
    }

    /// Tightest monitored, non-hidden window (nil if no data).
    private func menuBarPick() -> (name: String, remaining: Double)? {
        let s = Settings.shared
        var pairs: [(String, Double)] = []
        for p in store.providers where p.error == nil {
            for w in p.windows where !s.hiddenWindows.contains("\(p.name)/\(w.label)") {
                pairs.append((p.name, w.remaining))
            }
        }
        switch s.menuBarSource {
        case "claude": pairs = pairs.filter { $0.0 == "Claude" }
        case "codex":  pairs = pairs.filter { $0.0 == "Codex" }
        default: break
        }
        return pairs.min { $0.1 < $1.1 }.map { (name: $0.0, remaining: $0.1) }
    }

    /// Menu bar shows just "<Provider> <%>", always in white.
    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        let pick = menuBarPick()
        let valueText: String
        if let pick { valueText = "\(pick.name) \(Int(pick.remaining * 100))%" }
        else { valueText = "–" }

        // Rendered as a NON-template image so the menu bar can't recolor it — the
        // title's foregroundColor is ignored on the status bar (renders black on a
        // light menu bar), but a non-template image keeps exactly the color we draw.
        // Always white per the user's request (no red/amber tint).
        button.attributedTitle = NSAttributedString(string: "")
        button.title = ""
        button.contentTintColor = nil
        button.image = Self.menuImage(valueText, color: .white)
        button.imagePosition = .imageOnly
    }

    /// Draw the menu-bar text into a non-template image so its color is preserved
    /// (white by default) regardless of the menu bar's light/dark appearance.
    private static func menuImage(_ text: String, color: NSColor) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize - 1, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let textSize = (text as NSString).size(withAttributes: attrs)
        let size = NSSize(width: ceil(textSize.width) + 2, height: ceil(textSize.height))
        let img = NSImage(size: size, flipped: false) { _ in
            (text as NSString).draw(at: NSPoint(x: 1, y: 0), withAttributes: attrs)
            return true
        }
        img.isTemplate = false
        return img
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showStatusMenu()
        } else {
            togglePanel()
        }
    }

    private func showStatusMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Settings…", action: #selector(settingsAction), keyEquivalent: ",")
        menu.addItem(withTitle: "Refresh", action: #selector(refreshAction), keyEquivalent: "")

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit LimitHUD", action: #selector(quitAction), keyEquivalent: "q")
        menu.items.forEach { if $0.action != nil { $0.target = self } }
        // Temporarily attach the menu, pop it, then detach so left-click keeps toggling.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func settingsAction() { openSettings() }
    @objc private func refreshAction() { store.refresh() }
    @objc private func quitAction() { NSApp.terminate(nil) }

    // MARK: Show / hide

    private func togglePanel() {
        if panel.isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    /// Show the card. Pinned → restore remembered/anchored position and stay put.
    /// Unpinned → "peek" under the icon and auto-dismiss on the next outside click.
    private func showPanel() {
        // Show transparent first: SwiftUI doesn't repaint while the card is hidden,
        // so the window still holds its last frame (e.g., a previously-viewed pet).
        // Fading in only after a runloop tick — once SwiftUI has repainted the
        // current state — avoids that stale frame flashing on open.
        panel.alphaValue = 0
        // Restore the remembered spot if there is one; otherwise anchor under
        // the icon. Applies to both peek and pinned so a moved card stays put.
        positionPanel()
        panel.orderFrontRegardless()
        installPeekMonitorIfNeeded()
        NotificationCenter.default.post(name: .hudCardWillShow, object: nil)
        DispatchQueue.main.async {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.16
                self.panel.animator().alphaValue = 1
            }
        }
    }

    private func hidePanel() {
        panel.orderOut(nil)
        removePeekMonitor()
    }

    /// Toggle pinned state from the card's 📌 button. Pinning makes the card
    /// persistent; unpinning turns it back into a transient peek (and arms the
    /// outside-click dismiss so it behaves like a popover from now on).
    private func togglePin() {
        Settings.shared.cardPinned.toggle()
        if Settings.shared.cardPinned {
            removePeekMonitor()
        } else {
            installPeekMonitorIfNeeded()
        }
    }

    /// In peek mode, watch for clicks outside the card and dismiss it.
    private func installPeekMonitorIfNeeded() {
        guard !Settings.shared.cardPinned, peekMonitor == nil else { return }
        peekMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            // A global monitor only fires for clicks outside our app, so any
            // event here means the user clicked away — dismiss the peek.
            self?.hidePanel()
        }
    }

    private func removePeekMonitor() {
        if let m = peekMonitor { NSEvent.removeMonitor(m); peekMonitor = nil }
    }

    @objc private func panelMoved() {
        guard Settings.shared.rememberPosition, panel.isVisible else { return }
        let f = panel.frame
        Settings.shared.cardPosX = f.origin.x
        Settings.shared.cardPosTop = f.origin.y + f.size.height // top-left, stable across resizes
        Settings.shared.cardPosSet = true
    }

    /// Restore the remembered position if we have one, else anchor under the icon.
    /// Clamps fully on-screen so a disconnected monitor can't hide the card.
    private func positionPanel() {
        let s = Settings.shared
        guard s.rememberPosition, s.cardPosSet else { positionUnderStatusItem(); return }
        let size = panel.frame.size
        let topLeft = NSPoint(x: s.cardPosX, y: s.cardPosTop)
        let screen = NSScreen.screens.first { $0.frame.contains(topLeft) } ?? NSScreen.main
        guard let vf = screen?.visibleFrame else { positionUnderStatusItem(); return }
        let x = min(max(s.cardPosX, vf.minX), vf.maxX - size.width)
        let y = min(max(s.cardPosTop - size.height, vf.minY), vf.maxY - size.height)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: Placement

    /// Anchor the card directly below the menu-bar icon (popover style),
    /// horizontally centered on it and clamped to the visible screen.
    private func positionUnderStatusItem() {
        guard let button = statusItem?.button, let barWindow = button.window else {
            positionPanelCenter()
            return
        }
        let anchor = barWindow.frame                 // status item's frame in screen coords
        let size = panel.frame.size
        let gap: CGFloat = 6
        var x = anchor.midX - size.width / 2
        let y = anchor.minY - size.height - gap      // top of card sits just under the menu bar

        if let screen = barWindow.screen ?? NSScreen.main {
            let vf = screen.visibleFrame
            x = min(max(x, vf.minX + 8), vf.maxX - size.width - 8)
        }
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    /// Fallback: center of the main screen, slightly above the middle.
    private func positionPanelCenter() {
        guard let screen = NSScreen.main else { panel.center(); return }
        let frame = screen.visibleFrame
        let size = panel.frame.size
        let x = frame.midX - size.width / 2
        let y = frame.midY - size.height / 2 + frame.height * 0.12
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
