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
        NotificationCenter.default.addObserver(
            self, selector: #selector(panelMoved),
            name: NSWindow.didMoveNotification, object: panel)
        // Menu-bar-first: only auto-show the card if the user pinned it.
        if Settings.shared.cardPinned { showPanel() }

        hotKey = HotKeyManager { [weak self] in self?.togglePanel() }
        let s = Settings.shared
        hotKey.register(keyCode: UInt32(s.hotKeyKeyCode), carbonModifiers: UInt32(s.hotKeyModifiers))
        s.$hotKeyKeyCode.combineLatest(s.$hotKeyModifiers)
            .dropFirst()
            .sink { [weak self] code, mods in
                self?.hotKey.register(keyCode: UInt32(code), carbonModifiers: UInt32(mods))
            }
            .store(in: &cancellables)

        // Live menu-bar refresh when data or menu-bar prefs change.
        store.$providers
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusItem() }
            .store(in: &cancellables)
        s.$menuBarMode.combineLatest(s.$menuBarSource)
            .dropFirst()
            .sink { [weak self] _, _ in self?.updateStatusItem() }
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
            win.styleMask = [.titled, .closable]
            win.isReleasedWhenClosed = false
            win.setContentSize(NSSize(width: 360, height: 470))
            settingsWC = NSWindowController(window: win)
        }
        settingsWC?.window?.center()
        NSApp.activate(ignoringOtherApps: true)
        settingsWC?.showWindow(nil)
    }

    // MARK: Menu bar button

    /// Candidate menu-bar icons. Pick one live from the right-click submenu.
    private let iconChoices: [(symbol: String, title: String)] = [
        ("gauge.with.dots.needle.bottom.50percent", "Gauge"),
        ("speedometer",            "Speedometer"),
        ("circle.righthalf.filled","Half Circle"),
        ("chart.bar.fill",         "Bar Chart"),
        ("chart.pie.fill",         "Pie"),
        ("bolt.fill",              "Bolt"),
        ("hourglass",              "Hourglass"),
        ("chart.line.downtrend.xyaxis", "Downtrend"),
        // cute & cool
        ("sparkles",               "Sparkles"),
        ("flame.fill",             "Flame"),
        ("bolt.circle.fill",       "Bolt Circle"),
        ("moon.stars.fill",        "Moon & Stars"),
        ("leaf.fill",              "Leaf"),
        ("drop.fill",              "Drop"),
        ("star.fill",              "Star"),
        ("heart.fill",             "Heart"),
        ("atom",                   "Atom"),
        ("waveform",               "Waveform"),
        ("cloud.fill",             "Cloud"),
        ("flag.checkered",         "Checkered"),
    ]
    private let symbolKey = "menuBarSymbol"
    private var currentSymbol: String {
        UserDefaults.standard.string(forKey: symbolKey) ?? iconChoices[0].symbol
    }

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

    private func iconImage() -> NSImage? {
        let img = NSImage(systemSymbolName: currentSymbol, accessibilityDescription: "AI Quota")
            ?? NSImage(systemSymbolName: iconChoices[0].symbol, accessibilityDescription: "AI Quota")
        img?.isTemplate = true
        return img
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

    /// Quiet when healthy; amber/red when it matters. Shows "<Provider> <%>".
    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        let s = Settings.shared
        let pick = menuBarPick()

        var tint: NSColor?
        if let v = pick?.remaining {
            if v < 0.2 { tint = .systemRed }
            else if v < 0.5 { tint = .systemOrange }
            else { tint = s.menuBarQuietHealthy ? nil : .systemGreen }
        }

        let showIcon = (s.menuBarMode == "icon" || s.menuBarMode == "iconValue")
        let showValue = (s.menuBarMode != "icon")

        button.image = showIcon ? iconImage() : nil
        button.contentTintColor = tint

        if showValue {
            let str: String
            if let pick { str = "\(pick.name) \(Int(pick.remaining * 100))%" }
            else { str = "–" }
            let text = showIcon ? " " + str : str
            button.attributedTitle = NSAttributedString(string: text, attributes: [
                .foregroundColor: tint ?? NSColor.labelColor,
                .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize - 1, weight: .medium)
            ])
        } else {
            button.attributedTitle = NSAttributedString(string: "")
        }
    }

    @objc private func selectIcon(_ sender: NSMenuItem) {
        guard let symbol = sender.representedObject as? String else { return }
        UserDefaults.standard.set(symbol, forKey: symbolKey)
        updateStatusItem()
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

        // 图标样式 submenu — each item previews its own SF Symbol.
        let iconMenu = NSMenu()
        for choice in iconChoices {
            let item = NSMenuItem(title: choice.title, action: #selector(selectIcon(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = choice.symbol
            let preview = NSImage(systemSymbolName: choice.symbol, accessibilityDescription: nil)
            preview?.isTemplate = true
            item.image = preview
            item.state = (choice.symbol == currentSymbol) ? .on : .off
            iconMenu.addItem(item)
        }
        let iconItem = NSMenuItem(title: "Icon Style", action: nil, keyEquivalent: "")
        iconItem.submenu = iconMenu
        menu.addItem(iconItem)

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
        // Restore the remembered spot if there is one; otherwise anchor under
        // the icon. Applies to both peek and pinned so a moved card stays put.
        positionPanel()
        panel.orderFrontRegardless()
        installPeekMonitorIfNeeded()
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
