import Foundation

/// One rolling quota window (e.g. Claude's 5-hour or 7-day window).
struct QuotaWindow: Identifiable {
    let id = UUID()
    let label: String          // "5小时" / "7天"
    var utilization: Double     // fraction used, 0...1
    var resetsAt: Date?

    var remaining: Double { max(0, min(1, 1 - utilization)) }

    /// Human countdown until reset, e.g. "2h18m" or "4d".
    var resetCountdown: String? {
        guard let resetsAt else { return nil }
        let secs = resetsAt.timeIntervalSinceNow
        if secs <= 0 { return "reset" }
        let days = Int(secs) / 86400
        if days >= 1 {
            let hours = (Int(secs) % 86400) / 3600
            return "\(days)d\(hours)h"
        }
        let hours = Int(secs) / 3600
        let mins = (Int(secs) % 3600) / 60
        if hours >= 1 { return "\(hours)h\(mins)m" }
        return "\(mins)m"
    }
}

/// A provider (Claude / Codex) and its set of quota windows.
struct ProviderQuota: Identifiable {
    let id = UUID()
    let name: String           // "Claude" / "Codex"
    var windows: [QuotaWindow]
    var error: String?         // non-nil → show error state (e.g. not logged in)
    var stale: Bool = false    // showing last-good data because the latest refresh failed
    var lastGood: Date? = nil  // when the shown data was actually fetched
    var staleReason: String? = nil // latest refresh failure while showing last-good data
}
