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
    }

    func startTimer(interval: TimeInterval) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: max(15, interval), repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
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

    private func seedPlaceholder() {
        var seed: [ProviderQuota] = []
        if Settings.shared.monitorClaude { seed.append(ProviderQuota(name: "Claude", windows: [], error: "Loading…")) }
        if Settings.shared.monitorCodex  { seed.append(ProviderQuota(name: "Codex",  windows: [], error: "Loading…")) }
        providers = seed
        lastUpdated = Date()
    }
}
