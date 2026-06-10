import SwiftUI
import AppKit
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
    @Published var cardScale: Double        { didSet { d.set(cardScale, forKey: "cardScale") } } // 0.8–1.6
    @Published var launchAtLogin: Bool      { didSet { d.set(launchAtLogin, forKey: "launchAtLogin"); applyLaunchAtLogin() } }

    // Custom card background
    @Published var cardBgCustom: Bool       { didSet { d.set(cardBgCustom, forKey: "cardBgCustom") } }
    @Published var cardBgR: Double          { didSet { d.set(cardBgR, forKey: "cardBgR") } }
    @Published var cardBgG: Double          { didSet { d.set(cardBgG, forKey: "cardBgG") } }
    @Published var cardBgB: Double          { didSet { d.set(cardBgB, forKey: "cardBgB") } }
    @Published var cardBgA: Double          { didSet { d.set(cardBgA, forKey: "cardBgA") } }

    var cardBgColor: Color {
        get { Color(.sRGB, red: cardBgR, green: cardBgG, blue: cardBgB, opacity: cardBgA) }
        set {
            let ns = NSColor(newValue).usingColorSpace(.sRGB) ?? .black
            cardBgR = Double(ns.redComponent)
            cardBgG = Double(ns.greenComponent)
            cardBgB = Double(ns.blueComponent)
            cardBgA = Double(ns.alphaComponent)
        }
    }

    /// Perceived brightness of the custom background (0 dark … 1 light).
    var cardBgIsLight: Bool { (0.299 * cardBgR + 0.587 * cardBgG + 0.114 * cardBgB) > 0.55 }

    // Hotkey (Carbon virtual keycode + Carbon modifier mask)
    @Published var hotKeyKeyCode: Int       { didSet { d.set(hotKeyKeyCode, forKey: "hotKeyKeyCode") } }
    @Published var hotKeyModifiers: Int     { didSet { d.set(hotKeyModifiers, forKey: "hotKeyModifiers") } }
    @Published var hotKeyDisplay: String    { didSet { d.set(hotKeyDisplay, forKey: "hotKeyDisplay") } }

    // Card content: window keys ("Provider/Label") the user has hidden
    @Published var hiddenWindows: Set<String> { didSet { d.set(Array(hiddenWindows), forKey: "hiddenWindows") } }

    // Position memory (stored top-left so it's stable across resizes)
    @Published var rememberPosition: Bool   { didSet { d.set(rememberPosition, forKey: "rememberPosition") } }
    @Published var cardPosX: Double         { didSet { d.set(cardPosX, forKey: "cardPosX") } }
    @Published var cardPosTop: Double       { didSet { d.set(cardPosTop, forKey: "cardPosTop") } }
    @Published var cardPosSet: Bool         { didSet { d.set(cardPosSet, forKey: "cardPosSet") } }

    // Quiet hours (suppress notifications between start and end, wraps midnight)
    @Published var dndEnabled: Bool         { didSet { d.set(dndEnabled, forKey: "dndEnabled") } }
    @Published var dndStart: Int            { didSet { d.set(dndStart, forKey: "dndStart") } }
    @Published var dndEnd: Int              { didSet { d.set(dndEnd, forKey: "dndEnd") } }

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
        cardScale            = dbl("cardScale", 1.0)
        launchAtLogin        = bool("launchAtLogin", false)

        cardBgCustom         = bool("cardBgCustom", false)
        cardBgR              = dbl("cardBgR", 0.086) // default ≈ #161618
        cardBgG              = dbl("cardBgG", 0.086)
        cardBgB              = dbl("cardBgB", 0.094)
        cardBgA              = dbl("cardBgA", 1.0)

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

        rememberPosition = bool("rememberPosition", true)
        cardPosX         = dbl("cardPosX", 0)
        cardPosTop       = dbl("cardPosTop", 0)
        cardPosSet       = bool("cardPosSet", false)

        dndEnabled       = bool("dndEnabled", false)
        dndStart         = int("dndStart", 22)
        dndEnd           = int("dndEnd", 8)
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
