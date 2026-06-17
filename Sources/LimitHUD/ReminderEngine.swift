import Foundation

/// Edge-detects quota events per window and fires reminders:
/// - threshold: drops below threshold → "running low"; climbs back → "recovered"
/// - forecast:  projected to run dry before reset, within 30 min → "running dry"
/// - pace:      burning ≥2× the usual baseline while under 50% → "burning fast"
/// Forecast/pace use a rising-edge + 2h-per-window-per-type cooldown so they never spam.
@MainActor
final class ReminderEngine {
    private var belowThreshold: [String: Bool] = [:]
    private var activeState: [String: Bool] = [:]   // rising-edge latch per alert key
    private var lastFire: [String: Date] = [:]       // cooldown per alert key
    private let cooldown: TimeInterval = 2 * 3600
    private let etaWarn: TimeInterval = 30 * 60      // warn when empty within 30 min
    private let paceWarn = 2.0                        // ≥2× the usual pace

    func evaluate(_ providers: [ProviderQuota], settings s: Settings) {
        let quiet = inQuietHours(s)
        let threshold = Double(s.thresholdPercent) / 100

        for provider in providers {
            for window in provider.windows {
                let key = "\(provider.name)/\(window.label)"
                let pct = Int(window.remaining * 100)

                // ── Threshold: running low / recovered ──
                if s.thresholdEnabled {
                    let isBelow = window.remaining < threshold
                    let wasBelow = belowThreshold[key] ?? false
                    if isBelow && !wasBelow {
                        belowThreshold[key] = true
                        if !quiet {
                            Notifier.send(
                                title: "\(provider.name) \(window.label) running low",
                                body: "\(pct)% left" + (window.resetCountdown.map { " · resets in \($0)" } ?? ""),
                                notify: s.notificationsEnabled, sound: s.soundEnabled)
                        }
                    } else if !isBelow && wasBelow {
                        belowThreshold[key] = false
                        if s.recoveryEnabled && !quiet {
                            Notifier.send(
                                title: "\(provider.name) \(window.label) recovered",
                                body: "\(pct)% available again",
                                notify: s.notificationsEnabled, sound: s.soundEnabled)
                        }
                    }
                }

                // ── Forecast: about to run dry before the window resets ──
                if s.forecastAlertEnabled, !quiet {
                    let eta = UsageHistory.shared.burnETA(
                        provider: provider.name, label: window.label, remaining: window.remaining)
                    let untilReset = window.resetsAt?.timeIntervalSinceNow
                    let beforeReset = untilReset.map { $0 <= 0 || (eta ?? .infinity) < $0 } ?? true
                    let fire = (eta.map { $0 < etaWarn } ?? false) && beforeReset
                    if shouldFire(key + "#eta", fire) {
                        Notifier.send(
                            title: "\(provider.name) \(window.label) running dry",
                            body: "empty in \(etaString(eta!)) at this rate · \(pct)% left",
                            notify: s.notificationsEnabled, sound: s.soundEnabled)
                    }
                }

                // ── Pace: burning much faster than usual, and getting low ──
                if s.paceAlertEnabled, !quiet {
                    let pace = UsageHistory.shared.pace(provider: provider.name, label: window.label)
                    let fire = (pace ?? 0) >= paceWarn && window.remaining < 0.5
                    if shouldFire(key + "#pace", fire) {
                        Notifier.send(
                            title: "Burning \(provider.name) \(window.label) fast",
                            body: "\(paceString(pace!)) your usual pace · \(pct)% left",
                            notify: s.notificationsEnabled, sound: s.soundEnabled)
                    }
                }
            }
        }
    }

    /// True only when `condition` newly becomes true (rising edge) and the last fire
    /// for this key was over the cooldown ago. Always updates the edge latch, so a
    /// sustained condition fires once, not on every refresh.
    private func shouldFire(_ key: String, _ condition: Bool) -> Bool {
        let was = activeState[key] ?? false
        activeState[key] = condition
        guard condition && !was else { return false }
        if let last = lastFire[key], Date().timeIntervalSince(last) < cooldown { return false }
        lastFire[key] = Date()
        return true
    }

    private func inQuietHours(_ s: Settings) -> Bool {
        guard s.dndEnabled, s.dndStart != s.dndEnd else { return false }
        let h = Calendar.current.component(.hour, from: Date())
        return s.dndStart < s.dndEnd
            ? (h >= s.dndStart && h < s.dndEnd)        // same-day window
            : (h >= s.dndStart || h < s.dndEnd)        // wraps midnight
    }
}
