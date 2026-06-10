import SwiftUI

/// Settings window content — Framea-styled, appearance-adaptive.
struct SettingsView: View {
    @ObservedObject var store: QuotaStore
    @ObservedObject var settings = Settings.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

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
                }

                group("SOURCES") {
                    Toggle("Claude", isOn: $settings.monitorClaude)
                    Toggle("Codex", isOn: $settings.monitorCodex)
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
                    HStack(spacing: 12) {
                        Text("Opacity").foregroundColor(Theme.inkDim)
                        Slider(value: $settings.opacity, in: 0.4...1.0)
                        Text("\(Int(settings.opacity * 100))%")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(Theme.muted2)
                            .frame(width: 34, alignment: .trailing)
                    }
                }

                Text("LimitHUD · \(settings.hotKeyDisplay) to toggle the card")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(0.5)
                    .foregroundColor(Theme.muted3)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)
            }
            .padding(20)
            .tint(Theme.accent)
            .font(.system(size: 13))
        }
        .frame(width: 360, height: 540)
        .background(Theme.bg)
    }

    /// All currently-available window keys ("Provider/Label") across providers.
    private var allWindows: [String] {
        store.providers.flatMap { p in p.windows.map { "\(p.name)/\($0.label)" } }
    }

    @ViewBuilder
    private func group<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundColor(Theme.muted2)
            content()
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
        HStack {
            Text("Toggle hotkey").foregroundColor(Theme.inkDim)
            Spacer()
            Button(recording ? "Press keys…" : settings.hotKeyDisplay) {
                recording ? stop() : start()
            }
            .buttonStyle(.bordered)
            .tint(recording ? Theme.warning : Theme.accent)
            .font(.system(size: 12, weight: .medium, design: .monospaced))
        }
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
