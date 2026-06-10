import SwiftUI
import ServiceManagement

/// User preferences, persisted in UserDefaults. Observable so UI + engine react.
@MainActor
final class Settings: ObservableObject {
    static let shared = Settings()
    private let d = UserDefaults.standard

    // Reminders
    @Published var thresholdEnabled: Bool   { didSet { d.set(thresholdEnabled, forKey: "thresholdEnabled") } }
    @Published var thresholdPercent: Int    { didSet { d.set(thresholdPercent, forKey: "thresholdPercent") } }
    @Published var recoveryEnabled: Bool    { didSet { d.set(recoveryEnabled, forKey: "recoveryEnabled") } }
    @Published var soundEnabled: Bool       { didSet { d.set(soundEnabled, forKey: "soundEnabled") } }
    @Published var notificationsEnabled: Bool { didSet { d.set(notificationsEnabled, forKey: "notificationsEnabled") } }

    // Sources
    @Published var monitorClaude: Bool      { didSet { d.set(monitorClaude, forKey: "monitorClaude") } }
    @Published var monitorCodex: Bool       { didSet { d.set(monitorCodex, forKey: "monitorCodex") } }

    // Cookie source: which browser / profile ("auto" = try all installed)
    @Published var cookieBrowser: String    { didSet { d.set(cookieBrowser, forKey: "cookieBrowser") } }
    @Published var cookieProfile: String    { didSet { d.set(cookieProfile, forKey: "cookieProfile") } }

    // Refresh
    @Published var refreshInterval: Int     { didSet { d.set(refreshInterval, forKey: "refreshInterval") } } // seconds

    // Card
    @Published var opacity: Double          { didSet { d.set(opacity, forKey: "opacity") } }
    @Published var launchAtLogin: Bool      { didSet { d.set(launchAtLogin, forKey: "launchAtLogin"); applyLaunchAtLogin() } }

    // Hotkey (Carbon virtual keycode + Carbon modifier mask)
    @Published var hotKeyKeyCode: Int       { didSet { d.set(hotKeyKeyCode, forKey: "hotKeyKeyCode") } }
    @Published var hotKeyModifiers: Int     { didSet { d.set(hotKeyModifiers, forKey: "hotKeyModifiers") } }
    @Published var hotKeyDisplay: String    { didSet { d.set(hotKeyDisplay, forKey: "hotKeyDisplay") } }

    // Card content: window keys ("Provider/Label") the user has hidden
    @Published var hiddenWindows: Set<String> { didSet { d.set(Array(hiddenWindows), forKey: "hiddenWindows") } }

    private init() {
        let ud = UserDefaults.standard
        func bool(_ k: String, _ def: Bool) -> Bool { ud.object(forKey: k) == nil ? def : ud.bool(forKey: k) }
        func int(_ k: String, _ def: Int) -> Int { ud.object(forKey: k) == nil ? def : ud.integer(forKey: k) }
        func dbl(_ k: String, _ def: Double) -> Double { ud.object(forKey: k) == nil ? def : ud.double(forKey: k) }

        thresholdEnabled     = bool("thresholdEnabled", true)
        thresholdPercent     = int("thresholdPercent", 20)
        recoveryEnabled      = bool("recoveryEnabled", true)
        soundEnabled         = bool("soundEnabled", true)
        notificationsEnabled = bool("notificationsEnabled", true)
        monitorClaude        = bool("monitorClaude", true)
        monitorCodex         = bool("monitorCodex", true)
        cookieBrowser        = ud.string(forKey: "cookieBrowser") ?? "auto"
        cookieProfile        = ud.string(forKey: "cookieProfile") ?? "auto"
        refreshInterval      = int("refreshInterval", 60)
        opacity              = dbl("opacity", 1.0)
        launchAtLogin        = bool("launchAtLogin", false)

        // default ⌘⇧L : keyCode 37 (L), modifiers cmdKey(256)|shiftKey(512)
        hotKeyKeyCode        = int("hotKeyKeyCode", 37)
        hotKeyModifiers      = int("hotKeyModifiers", 256 | 512)
        hotKeyDisplay        = ud.string(forKey: "hotKeyDisplay") ?? "⌘⇧L"

        // per-model windows hidden by default; seeded once
        if let saved = ud.stringArray(forKey: "hiddenWindows") {
            hiddenWindows = Set(saved)
        } else {
            hiddenWindows = ["Claude/Opus", "Claude/Sonnet"]
        }
    }

    private func applyLaunchAtLogin() {
        do {
            if launchAtLogin { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("[LimitHUD] launch-at-login error: \(error.localizedDescription)")
        }
    }
}
