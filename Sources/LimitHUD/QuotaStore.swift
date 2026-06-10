import SwiftUI
import Combine

/// Holds live quota state, drives periodic refresh, and runs the reminder engine.
@MainActor
final class QuotaStore: ObservableObject {
    @Published var providers: [ProviderQuota] = []
    @Published var lastUpdated: Date?
    @Published var isRefreshing = false

    private var timer: Timer?
    private let reminders = ReminderEngine()
    private var cancellables = Set<AnyCancellable>()

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
            if let c = await claude { result.append(c) }
            if let c = await codex  { result.append(c) }

            self.providers = result
            self.lastUpdated = Date()
            self.isRefreshing = false
            self.reminders.evaluate(result, settings: s)
        }
    }

    private func seedPlaceholder() {
        var seed: [ProviderQuota] = []
        if Settings.shared.monitorClaude { seed.append(ProviderQuota(name: "Claude", windows: [], error: "Loading…")) }
        if Settings.shared.monitorCodex  { seed.append(ProviderQuota(name: "Codex",  windows: [], error: "Loading…")) }
        providers = seed
        lastUpdated = Date()
    }
}
