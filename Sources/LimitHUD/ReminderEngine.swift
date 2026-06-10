import Foundation

/// Edge-detects threshold crossings per quota window and fires reminders.
/// - drops below threshold  → "running low" alert (once)
/// - climbs back above       → "recovered" alert (when window resets)
@MainActor
final class ReminderEngine {
    private var belowThreshold: [String: Bool] = [:]

    func evaluate(_ providers: [ProviderQuota], settings s: Settings) {
        guard s.thresholdEnabled else { return }
        let threshold = Double(s.thresholdPercent) / 100

        for provider in providers {
            for window in provider.windows {
                let key = "\(provider.name)/\(window.label)"
                let isBelow = window.remaining < threshold
                let wasBelow = belowThreshold[key] ?? false
                let pct = Int(window.remaining * 100)

                if isBelow && !wasBelow {
                    belowThreshold[key] = true
                    Notifier.send(
                        title: "\(provider.name) \(window.label) running low",
                        body: "\(pct)% left" + (window.resetCountdown.map { " · resets in \($0)" } ?? ""),
                        notify: s.notificationsEnabled, sound: s.soundEnabled
                    )
                } else if !isBelow && wasBelow {
                    belowThreshold[key] = false
                    if s.recoveryEnabled {
                        Notifier.send(
                            title: "\(provider.name) \(window.label) recovered",
                            body: "\(pct)% available again",
                            notify: s.notificationsEnabled, sound: s.soundEnabled
                        )
                    }
                }
            }
        }
    }
}
