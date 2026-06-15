import SwiftUI
import Combine

/// Holds live quota state, drives periodic refresh, and runs the reminder engine.
@MainActor
final class QuotaStore: ObservableObject {
    @Published var providers: [ProviderQuota] = []
    @Published var lastUpdated: Date?
    @Published var isRefreshing = false
    /// Set whenever a window's remaining jumps back up (quota reset) — drives
    /// the refill celebration in the card and menu bar.
    @Published var lastRefill: Date?

    private var timer: Timer?
    private let reminders = ReminderEngine()
    private var cancellables = Set<AnyCancellable>()
    private var lastGood: [String: (quota: ProviderQuota, at: Date)] = [:]
    private var prevRemaining: [String: Double] = [:]
    private var demoTimer: Timer?
    private var demoStep = 0
    private var demoClock: Double = 0   // synthetic, spaced timestamps for demo history

    init() {
        seedPlaceholder()
        refresh()
        startTimer(interval: TimeInterval(Settings.shared.refreshInterval))

        // React to settings changes: interval restarts the timer; source toggles refresh.
        Settings.shared.$refreshInterval
            .dropFirst()
            .sink { [weak self] iv in self?.startTimer(interval: TimeInterval(iv)) }
            .store(in: &cancellables)
        Settings.shared.$monitorClaude.dropFirst()
            .sink { [weak self] _ in self?.refresh() }.store(in: &cancellables)
        Settings.shared.$monitorCodex.dropFirst()
            .sink { [weak self] _ in self?.refresh() }.store(in: &cancellables)
        for pub in [Settings.shared.$claudeBrowser, Settings.shared.$claudeProfile,
                    Settings.shared.$codexBrowser, Settings.shared.$codexProfile] {
            pub.dropFirst().sink { [weak self] _ in self?.refresh() }.store(in: &cancellables)
        }
        Settings.shared.$demoMode
            .dropFirst()
            .sink { [weak self] on in on ? self?.startDemo() : self?.stopDemo() }
            .store(in: &cancellables)
        if Settings.shared.demoMode { startDemo() }
    }

    func startTimer(interval: TimeInterval) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: max(15, interval), repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        guard !Settings.shared.demoMode else { return }   // demo drives `providers` itself
        guard !isRefreshing else { return }
        isRefreshing = true
        Task { @MainActor in
            let s = Settings.shared
            let claudePrefs = CookiePrefs(browser: s.claudeBrowser, profile: s.claudeProfile)
            let codexPrefs  = CookiePrefs(browser: s.codexBrowser,  profile: s.codexProfile)
            async let claude: ProviderQuota? = s.monitorClaude ? ClaudeProvider.fetch(prefs: claudePrefs) : nil
            async let codex:  ProviderQuota? = s.monitorCodex  ? CodexProvider.fetch(prefs: codexPrefs)  : nil

            var result: [ProviderQuota] = []
            if let c = await claude { result.append(self.resolve(c)) }
            if let c = await codex  { result.append(self.resolve(c)) }

            self.providers = result
            self.lastUpdated = Date()
            self.isRefreshing = false
            self.recordHistory(result)
            self.reminders.evaluate(result, settings: s)
        }
    }

    /// On success, remember it. On failure, fall back to the last-good data
    /// (marked stale) instead of replacing it with an error.
    private func resolve(_ r: ProviderQuota) -> ProviderQuota {
        if !r.windows.isEmpty {
            lastGood[r.name] = (r, Date())
            return r
        }
        if let good = lastGood[r.name] {
            var q = good.quota
            q.stale = true
            q.lastGood = good.at
            q.staleReason = r.error
            return q
        }
        return r // error, and we have no good data yet
    }

    /// Feed fresh (non-stale) readings into the forecast history, and detect
    /// refills: a visible window whose remaining jumped up notably = a reset.
    private func recordHistory(_ providers: [ProviderQuota]) {
        let at = Date()
        let hidden = Settings.shared.hiddenWindows
        var refilled = false
        for p in providers where p.error == nil && !p.stale {
            for w in p.windows {
                UsageHistory.shared.record(provider: p.name, label: w.label, remaining: w.remaining, at: at)
                let key = "\(p.name)/\(w.label)"
                if let prev = prevRemaining[key], w.remaining - prev > 0.15, !hidden.contains(key) {
                    refilled = true
                }
                prevRemaining[key] = w.remaining
            }
        }
        if refilled { lastRefill = at }
    }

    // MARK: Demo mode — simulated quota cycling every state for testing / screenshots.

    /// Remaining fraction at each step; `party` marks the post-refill celebration.
    private static let demoCycle: [(r: Double, party: Bool)] = [
        (1.00, false), (0.93, false), (0.86, false), (0.79, false), (0.72, false), // gentle — sets the "usual" baseline
        (0.56, false), (0.40, false), (0.24, false), (0.10, false),                // steep burst → "faster than usual"
        (0.02, false),                                                             // dead / dozing
        (1.00, true),  (1.00, true),                                              // refill → celebration
    ]

    /// Demo windows mirror the real provider structure (5-Hour + 7-Day per source).
    /// `offset` lifts the 7-Day / Codex windows above the 5-Hour bottleneck; `slow`
    /// windows reset in days rather than hours.
    private static let demoWindows: [(provider: String, label: String, offset: Double, slow: Bool)] = [
        ("Claude", "5-Hour", 0.00, false),
        ("Claude", "7-Day",  0.28, true),
        ("Codex",  "5-Hour", 0.12, false),
        ("Codex",  "7-Day",  0.40, true),
    ]

    private func clearDemoHistory() {
        for w in Self.demoWindows { UsageHistory.shared.forget(provider: w.provider, label: w.label) }
    }

    private func startDemo() {
        timer?.invalidate()                     // pause real refresh
        demoStep = 0
        demoClock = Date().timeIntervalSince1970
        clearDemoHistory()
        demoTick()
        demoTimer?.invalidate()
        demoTimer = Timer.scheduledTimer(withTimeInterval: 1.3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.demoTick() }
        }
    }

    private func stopDemo() {
        demoTimer?.invalidate(); demoTimer = nil
        lastRefill = nil
        prevRemaining.removeAll()
        clearDemoHistory()   // drop synthetic trend
        seedPlaceholder()
        refresh()
        startTimer(interval: TimeInterval(Settings.shared.refreshInterval))
    }

    private func demoTick() {
        let step = Self.demoCycle[demoStep % Self.demoCycle.count]
        demoStep += 1
        // Spaced synthetic timestamps so the sparkline + burn-down ETA populate
        // (real data needs minutes of spread; demo fakes it). Keys match the real
        // ones and are dropped via clearDemoHistory() when demo stops.
        demoClock += 180
        let at = Date(timeIntervalSince1970: demoClock)

        var windows: [String: [QuotaWindow]] = [:]
        var order: [String] = []
        for d in Self.demoWindows {
            let r = min(1, step.r + d.offset)
            let resetIn = step.party
                ? (d.slow ? 7 * 86400.0 : 5 * 3600.0)
                : (d.slow ? max(0.5, r * 7) * 86400 : max(0.5, r * 5) * 3600)
            let w = QuotaWindow(label: d.label, utilization: 1 - r,
                                resetsAt: Date().addingTimeInterval(resetIn))
            if windows[d.provider] == nil { order.append(d.provider) }
            windows[d.provider, default: []].append(w)
            UsageHistory.shared.record(provider: d.provider, label: d.label, remaining: r, at: at)
        }
        providers = order.map { ProviderQuota(name: $0, windows: windows[$0] ?? []) }
        lastUpdated = Date()
        lastRefill = step.party ? Date() : nil
    }

    private func seedPlaceholder() {
        var seed: [ProviderQuota] = []
        if Settings.shared.monitorClaude { seed.append(ProviderQuota(name: "Claude", windows: [], error: "Loading…")) }
        if Settings.shared.monitorCodex  { seed.append(ProviderQuota(name: "Codex",  windows: [], error: "Loading…")) }
        providers = seed
        lastUpdated = nil
    }
}
