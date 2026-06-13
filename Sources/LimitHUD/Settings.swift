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

    // Card stays pinned (persistent floating) vs. transient peek popover
    @Published var cardPinned: Bool         { didSet { d.set(cardPinned, forKey: "cardPinned") } }

    // Menu bar display
    @Published var petStyle: String         { didSet { d.set(petStyle, forKey: "petStyle") } }          // mochi | neko | boo | inu
    @Published var menuBarSource: String    { didSet { d.set(menuBarSource, forKey: "menuBarSource") } } // tightest | claude | codex
    @Published var menuBarQuietHealthy: Bool { didSet { d.set(menuBarQuietHealthy, forKey: "menuBarQuietHealthy") } }

    // Cookie source per provider (so Claude & Codex can live in different
    // browsers/profiles / Google accounts). "auto" = try all installed.
    @Published var claudeBrowser: String    { didSet { d.set(claudeBrowser, forKey: "claudeBrowser") } }
    @Published var claudeProfile: String    { didSet { d.set(claudeProfile, forKey: "claudeProfile") } }
    @Published var codexBrowser: String     { didSet { d.set(codexBrowser, forKey: "codexBrowser") } }
    @Published var codexProfile: String     { didSet { d.set(codexProfile, forKey: "codexProfile") } }

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

    // Custom text color (applies to neutral labels; % and bars stay semantic)
    @Published var cardFgCustom: Bool       { didSet { d.set(cardFgCustom, forKey: "cardFgCustom") } }
    @Published var cardFgR: Double          { didSet { d.set(cardFgR, forKey: "cardFgR") } }
    @Published var cardFgG: Double          { didSet { d.set(cardFgG, forKey: "cardFgG") } }
    @Published var cardFgB: Double          { didSet { d.set(cardFgB, forKey: "cardFgB") } }

    var cardFgColor: Color {
        get { Color(.sRGB, red: cardFgR, green: cardFgG, blue: cardFgB, opacity: 1) }
        set {
            let ns = NSColor(newValue).usingColorSpace(.sRGB) ?? .white
            cardFgR = Double(ns.redComponent)
            cardFgG = Double(ns.greenComponent)
            cardFgB = Double(ns.blueComponent)
        }
    }

    // Custom progress-bar color (when on, replaces the green/amber/red ramp)
    @Published var cardBarCustom: Bool      { didSet { d.set(cardBarCustom, forKey: "cardBarCustom") } }
    @Published var cardBarR: Double         { didSet { d.set(cardBarR, forKey: "cardBarR") } }
    @Published var cardBarG: Double         { didSet { d.set(cardBarG, forKey: "cardBarG") } }
    @Published var cardBarB: Double         { didSet { d.set(cardBarB, forKey: "cardBarB") } }

    var cardBarColor: Color {
        get { Color(.sRGB, red: cardBarR, green: cardBarG, blue: cardBarB, opacity: 1) }
        set {
            let ns = NSColor(newValue).usingColorSpace(.sRGB) ?? .green
            cardBarR = Double(ns.redComponent)
            cardBarG = Double(ns.greenComponent)
            cardBarB = Double(ns.blueComponent)
        }
    }

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
        cardPinned           = bool("cardPinned", false)
        petStyle             = ud.string(forKey: "petStyle") ?? "mochi"
        menuBarSource        = ud.string(forKey: "menuBarSource") ?? "tightest"
        menuBarQuietHealthy  = ud.object(forKey: "menuBarQuietHealthy") == nil ? true : ud.bool(forKey: "menuBarQuietHealthy")

        claudeBrowser        = ud.string(forKey: "claudeBrowser") ?? "auto"
        claudeProfile        = ud.string(forKey: "claudeProfile") ?? "auto"
        codexBrowser         = ud.string(forKey: "codexBrowser") ?? "auto"
        codexProfile         = ud.string(forKey: "codexProfile") ?? "auto"
        refreshInterval      = int("refreshInterval", 60)
        opacity              = dbl("opacity", 1.0)
        cardScale            = dbl("cardScale", 1.0)
        launchAtLogin        = bool("launchAtLogin", false)

        cardBgCustom         = bool("cardBgCustom", false)
        cardBgR              = dbl("cardBgR", 0.086) // default ≈ #161618
        cardBgG              = dbl("cardBgG", 0.086)
        cardBgB              = dbl("cardBgB", 0.094)
        cardBgA              = dbl("cardBgA", 1.0)

        cardFgCustom         = bool("cardFgCustom", false)
        cardFgR              = dbl("cardFgR", 0.957) // default ≈ #F4F4F5
        cardFgG              = dbl("cardFgG", 0.957)
        cardFgB              = dbl("cardFgB", 0.961)

        cardBarCustom        = bool("cardBarCustom", false)
        cardBarR             = dbl("cardBarR", 0.204) // default ≈ #34C982
        cardBarG             = dbl("cardBarG", 0.788)
        cardBarB             = dbl("cardBarB", 0.510)

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
