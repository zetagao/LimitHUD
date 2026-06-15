import SwiftUI

/// Settings window content — Framea-styled, appearance-adaptive.
struct SettingsView: View {
    @ObservedObject var store: QuotaStore
    @ObservedObject var settings = Settings.shared
    private let reader = BrowserCookieReader()
    @State private var advancedLayoutOpen = false

    private func profilesFor(_ browserId: String) -> [String] {
        guard let b = BrowserCookieReader.supported.first(where: { $0.id == browserId })
        else { return [] }
        return reader.profiles(for: b)
    }

    private func profileLabel(_ browserId: String, _ profile: String) -> String {
        guard let b = BrowserCookieReader.supported.first(where: { $0.id == browserId })
        else { return profile }
        return reader.profileDisplayName(b, profile)
    }

    @ViewBuilder
    private func browserRow(_ title: String, browser: Binding<String>, profile: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundColor(Theme.inkDim)
            Picker("Browser", selection: browser) {
                Text("Auto").tag("auto")
                ForEach(reader.installedBrowsers()) { b in Text(b.name).tag(b.id) }
            }
            .labelsHidden()
            .onChange(of: browser.wrappedValue) { _ in profile.wrappedValue = "auto" }
            let profs = profilesFor(browser.wrappedValue)
            if browser.wrappedValue != "auto", !profs.isEmpty {
                Picker("Profile", selection: profile) {
                    Text("Auto").tag("auto")
                    ForEach(profs, id: \.self) { p in
                        Text(profileLabel(browser.wrappedValue, p)).tag(p)
                    }
                }
                .labelsHidden()
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                settingsHeader

                group("REMINDERS") {
                    Toggle("Low-quota alert", isOn: $settings.thresholdEnabled)
                    Stepper(value: $settings.thresholdPercent, in: 5...50, step: 5) {
                        Text("Alert when below \(settings.thresholdPercent)% left")
                            .foregroundColor(settings.thresholdEnabled ? Theme.inkDim : Theme.muted2)
                    }
                    .disabled(!settings.thresholdEnabled)
                    Toggle("Recovery reminder", isOn: $settings.recoveryEnabled)
                    Toggle("System notifications", isOn: $settings.notificationsEnabled)
                    Toggle("Sound", isOn: $settings.soundEnabled)
                    Toggle("Quiet hours", isOn: $settings.dndEnabled)
                    if settings.dndEnabled {
                        HStack(spacing: 8) {
                            Text("From").foregroundColor(Theme.inkDim)
                            hourPicker($settings.dndStart)
                            Text("to").foregroundColor(Theme.inkDim)
                            hourPicker($settings.dndEnd)
                        }
                    }
                }

                group("PET") {
                    Picker("Character", selection: $settings.petStyle) {
                        Text("Mochi").tag("mochi")   // the pink blob
                        Text("Lota").tag("neko")     // the calico cat
                        Text("Bao").tag("inu")       // the derpy West Highland pup
                        Text("Mozart").tag("boo")    // the ghost
                    }
                    Text("Your quota buddy on the card — reacts to the tightest window.")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.muted2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                group("MENU BAR") {
                    Picker("Value", selection: $settings.menuBarSource) {
                        Text("Tightest").tag("tightest")
                        Text("Claude").tag("claude")
                        Text("Codex").tag("codex")
                    }
                    Toggle("Quiet when healthy", isOn: $settings.menuBarQuietHealthy)
                    Text("Stays neutral above 50% · amber under 50% · red under 20%.")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.muted2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                group("SOURCES") {
                    Toggle("Claude", isOn: $settings.monitorClaude)
                    Toggle("Codex", isOn: $settings.monitorCodex)
                }

                group("BROWSER") {
                    if settings.monitorClaude {
                        browserRow("Claude", browser: $settings.claudeBrowser, profile: $settings.claudeProfile)
                    }
                    if settings.monitorCodex {
                        browserRow("Codex", browser: $settings.codexBrowser, profile: $settings.codexProfile)
                    }
                    Text("Each can read a different browser / profile — handy when Claude and ChatGPT use different Google accounts.")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.muted2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !allWindows.isEmpty {
                    group("CARD CONTENT") {
                        ForEach(allWindows, id: \.self) { key in
                            Toggle(key.replacingOccurrences(of: "/", with: " · "), isOn: Binding(
                                get: { !settings.hiddenWindows.contains(key) },
                                set: { on in
                                    if on { settings.hiddenWindows.remove(key) }
                                    else  { settings.hiddenWindows.insert(key) }
                                }))
                        }
                    }
                }

                group("REFRESH") {
                    Picker("", selection: $settings.refreshInterval) {
                        Text("30s").tag(30)
                        Text("1 min").tag(60)
                        Text("5 min").tag(300)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                group("CARD") {
                    HotKeyRecorder()
                    Toggle("Launch at login", isOn: $settings.launchAtLogin)
                    Toggle("Remember position", isOn: $settings.rememberPosition)
                    sliderRow("Size", value: $settings.cardScale, range: 0.7...2.0) {
                        "\(Int(settings.cardScale * 100))%"
                    }
                    sliderRow("Opacity", value: $settings.opacity, range: 0.4...1.0) {
                        "\(Int(settings.opacity * 100))%"
                    }
                    Toggle("Custom background", isOn: $settings.cardBgCustom)
                    if settings.cardBgCustom {
                        ColorPicker("Background color", selection: Binding(
                            get: { settings.cardBgColor },
                            set: { settings.cardBgColor = $0 }
                        ), supportsOpacity: true)
                    }
                    Toggle("Custom text color", isOn: $settings.cardFgCustom)
                    if settings.cardFgCustom {
                        ColorPicker("Text color", selection: Binding(
                            get: { settings.cardFgColor },
                            set: { settings.cardFgColor = $0 }
                        ))
                    }
                    Toggle("Custom bar color", isOn: $settings.cardBarCustom)
                    if settings.cardBarCustom {
                        ColorPicker("Bar color", selection: Binding(
                            get: { settings.cardBarColor },
                            set: { settings.cardBarColor = $0 }
                        ))
                    }
                }

                DisclosureGroup(isExpanded: $advancedLayoutOpen) {
                    VStack(alignment: .leading, spacing: 13) {
                        Text("Drag the card's right edge for width, or the lower-right corner for overall size.")
                            .font(.system(size: 10))
                            .foregroundColor(Theme.muted3)
                            .fixedSize(horizontal: false, vertical: true)
                        sliderRow("Width", value: $settings.cardWidth, range: 160...460) {
                            "\(Int(settings.cardWidth))"
                        }
                        sliderRow("Pet", value: $settings.petScale, range: 0.5...2.4) {
                            "\(Int(settings.petScale * 100))%"
                        }
                        sliderRow("Forecast", value: $settings.heroScale, range: 0.7...1.8) {
                            "\(Int(settings.heroScale * 100))%"
                        }
                        sliderRow("List", value: $settings.listScale, range: 0.7...1.8) {
                            "\(Int(settings.listScale * 100))%"
                        }
                        Button("Reset layout") { settings.resetLayout() }
                            .buttonStyle(.plain)
                            .foregroundColor(Theme.accent)
                    }
                    .padding(.top, 8)
                } label: {
                    Text("ADVANCED LAYOUT")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(Theme.muted2)
                }

                Text(settings.hotKeyRegistered
                     ? "LimitHUD · \(settings.hotKeyDisplay) to toggle the card"
                     : "⚠ \(settings.hotKeyDisplay) is taken — rebind it under CARD")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(0.5)
                    .foregroundColor(settings.hotKeyRegistered ? Theme.muted3 : Theme.warning)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 18)
            .padding(.top, 30)   // clear the (transparent-titlebar) traffic lights
            .padding(.bottom, 20)
            .tint(Theme.accent)
            .font(.system(size: 13))
            .foregroundColor(Theme.ink)
        }
        .frame(width: 380, height: 560)
        // Same premium frosted-dark surface as the card.
        .background(FrostedBackground().overlay(Theme.surface.opacity(0.92)).ignoresSafeArea())
        .environment(\.colorScheme, .dark)
    }

    /// Card-style header for the window (the title bar is hidden).
    private var settingsHeader: some View {
        HStack(spacing: 7) {
            Text("SETTINGS")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .tracking(2.4)
                .foregroundColor(Theme.ink)
            Circle().fill(Theme.accent).frame(width: 5, height: 5)
            Spacer()
        }
    }

    /// All currently-available window keys ("Provider/Label") across providers.
    private var allWindows: [String] {
        store.providers.flatMap { p in p.windows.map { "\(p.name)/\($0.label)" } }
    }

    private func hourPicker(_ value: Binding<Int>) -> some View {
        Picker("", selection: value) {
            ForEach(0..<24, id: \.self) { h in
                Text(String(format: "%02d:00", h)).tag(h)
            }
        }
        .labelsHidden()
        .frame(width: 84)
    }

    private func sliderRow(_ label: String, value: Binding<Double>,
                           range: ClosedRange<Double>, _ text: @escaping () -> String) -> some View {
        HStack(spacing: 12) {
            Text(label).foregroundColor(Theme.inkDim)
            Slider(value: value, in: range)
            Text(text())
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Theme.muted2)
                .frame(width: 38, alignment: .trailing)
        }
    }

    @ViewBuilder
    private func group<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundColor(Theme.muted2)
                .padding(.leading, 2)
            VStack(alignment: .leading, spacing: 12) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(13)
                .background(Theme.surface2.opacity(0.5),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.border2, lineWidth: 1))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Click to record a new global toggle hotkey. Requires ⌘/⌃/⌥ in the combo.
private struct HotKeyRecorder: View {
    @ObservedObject var settings = Settings.shared
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("Toggle hotkey").foregroundColor(Theme.inkDim)
                Spacer()
                Button(recording ? "Press keys…" : settings.hotKeyDisplay) {
                    recording ? stop() : start()
                }
                .buttonStyle(.bordered)
                .tint(recording ? Theme.warning : (settings.hotKeyRegistered ? Theme.accent : Theme.error))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
            }
            if !settings.hotKeyRegistered && !recording {
                Text("⚠ \(settings.hotKeyDisplay) is taken by another app — pick a different combo")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onDisappear { stop() } // don't leak the key monitor if the window closes mid-record
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil // consume while recording
        }
    }

    private func stop() {
        recording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }

    private func handle(_ event: NSEvent) {
        if event.keyCode == 53 { stop(); return } // Esc cancels
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command) || flags.contains(.control) || flags.contains(.option) else { return }

        var carbon = 0
        var display = ""
        if flags.contains(.control) { carbon |= 4096; display += "⌃" }
        if flags.contains(.option)  { carbon |= 2048; display += "⌥" }
        if flags.contains(.shift)   { carbon |= 512;  display += "⇧" }
        if flags.contains(.command) { carbon |= 256;  display += "⌘" }
        display += (event.charactersIgnoringModifiers ?? "").uppercased()

        settings.hotKeyKeyCode = Int(event.keyCode)
        settings.hotKeyModifiers = carbon
        settings.hotKeyDisplay = display
        stop()
    }
}
