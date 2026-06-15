import Foundation

/// Rolling per-window history of `remaining` over time, used to forecast a
/// burn-down ETA and draw a sparkline. Keyed by "Provider/Label" because a
/// QuotaWindow's id is regenerated on every refresh.
@MainActor
final class UsageHistory {
    static let shared = UsageHistory()

    struct Sample: Codable { let t: Double; let r: Double } // unix time, remaining 0…1

    private var series: [String: [Sample]] = [:]
    private var baseline: [String: Double] = [:]   // EWMA of burn/sec per window — the "usual" pace
    private let cap = 240                 // ~4h at 1-min refresh
    private let maxAge: TimeInterval = 6 * 3600
    private let key = "usageHistory.v1"
    private let baselineKey = "usageBaseline.v1"
    private let baselineAlpha = 0.04      // slow → baseline = pace over many sessions

    private init() { load() }

    /// Record the latest reading for a window. Drops near-duplicate timestamps
    /// and trims old/oversized history, then persists.
    func record(provider: String, label: String, remaining: Double, at: Date = Date()) {
        let k = "\(provider)/\(label)"
        var arr = series[k] ?? []
        let now = at.timeIntervalSince1970
        if let last = arr.last, now - last.t < 5 { arr.removeLast() } // coalesce rapid refreshes
        arr.append(Sample(t: now, r: max(0, min(1, remaining))))
        arr = arr.filter { now - $0.t <= maxAge }
        if arr.count > cap { arr.removeFirst(arr.count - cap) }
        series[k] = arr
        save()
        // Blend the current short-term burn into the long-run "usual" baseline.
        if let burn = currentBurn(provider: provider, label: label) {
            baseline[k] = baseline[k].map { $0 * (1 - baselineAlpha) + burn * baselineAlpha } ?? burn
            saveBaseline()
        }
    }

    /// Drop a window's history + baseline (used when demo mode releases its keys).
    func forget(provider: String, label: String) {
        let k = "\(provider)/\(label)"
        series[k] = nil
        baseline[k] = nil
        save(); saveBaseline()
    }

    /// Recent samples for a window (oldest → newest), within `window` seconds.
    func recent(provider: String, label: String, window: TimeInterval = 1800) -> [Sample] {
        let k = "\(provider)/\(label)"
        guard let arr = series[k], let last = arr.last else { return [] }
        return arr.filter { last.t - $0.t <= window }
    }

    /// Estimated seconds until this window hits 0% at the current burn rate.
    /// nil when there isn't enough data, or usage is flat / refilling.
    func burnETA(provider: String, label: String, remaining: Double) -> TimeInterval? {
        let pts = recent(provider: provider, label: label)
        guard pts.count >= 3 else { return nil }
        let span = pts.last!.t - pts.first!.t
        guard span >= 120 else { return nil } // need a couple minutes of spread

        // Least-squares slope of remaining vs. time (per second).
        let n = Double(pts.count)
        let mx = pts.reduce(0) { $0 + $1.t } / n
        let my = pts.reduce(0) { $0 + $1.r } / n
        var sxx = 0.0, sxy = 0.0
        for p in pts { let dx = p.t - mx; sxx += dx * dx; sxy += dx * (p.r - my) }
        guard sxx > 0 else { return nil }
        let slope = sxy / sxx // Δremaining per second (negative = burning)

        let burn = -slope
        guard burn > 1e-7 else { return nil }      // ~>0.036%/hr to count as burning
        let eta = remaining / burn
        guard eta.isFinite, eta > 0 else { return nil }
        return eta
    }

    /// Least-squares slope of remaining vs. time (per second; negative = burning).
    private func slope(_ pts: [Sample], minSpan: TimeInterval) -> Double? {
        guard pts.count >= 2, pts.last!.t - pts.first!.t >= minSpan else { return nil }
        let n = Double(pts.count)
        let mx = pts.reduce(0) { $0 + $1.t } / n
        let my = pts.reduce(0) { $0 + $1.r } / n
        var sxx = 0.0, sxy = 0.0
        for p in pts { let dx = p.t - mx; sxx += dx * dx; sxy += dx * (p.r - my) }
        guard sxx > 0 else { return nil }
        return sxy / sxx
    }

    /// Short-term burn rate (per second, positive = burning) over `window` seconds.
    func currentBurn(provider: String, label: String, window: TimeInterval = 900) -> Double? {
        guard let s = slope(recent(provider: provider, label: label, window: window), minSpan: 60),
              s < 0 else { return nil }
        return -s
    }

    /// How fast this window is burning vs. its usual baseline (1 = typical, 2 = twice
    /// as fast). nil when not burning, or there's no established baseline yet.
    func pace(provider: String, label: String) -> Double? {
        guard let cur = currentBurn(provider: provider, label: label),
              let base = baseline["\(provider)/\(label)"], base > 1e-9
        else { return nil }
        return cur / base
    }

    // MARK: Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(series) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private func saveBaseline() {
        guard let data = try? JSONEncoder().encode(baseline) else { return }
        UserDefaults.standard.set(data, forKey: baselineKey)
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([String: [Sample]].self, from: data) {
            series = decoded
        }
        if let data = UserDefaults.standard.data(forKey: baselineKey),
           let decoded = try? JSONDecoder().decode([String: Double].self, from: data) {
            baseline = decoded
        }
    }
}

/// Format a pace multiple like "~2×" / "~1.5×" (nearest half, min 1.5).
func paceString(_ ratio: Double) -> String {
    let n = max(1.5, (ratio * 2).rounded() / 2)
    return n == n.rounded() ? "~\(Int(n))×" : "~\(n)×"
}

/// Format an ETA like "~22m" / "~3h10m" / "~2d".
func etaString(_ secs: TimeInterval) -> String {
    let s = Int(secs)
    if s >= 86400 { return "~\(s / 86400)d" }
    if s >= 3600 { let h = s / 3600, m = (s % 3600) / 60; return m > 0 ? "~\(h)h\(m)m" : "~\(h)h" }
    if s >= 60 { return "~\(s / 60)m" }
    return "~1m"
}
