import Foundation

/// Fetches Claude's real quota from claude.ai using Chrome session cookies.
/// Never throws — failures are surfaced as `ProviderQuota.error` for the card.
enum ClaudeProvider {

    static func fetch(prefs: CookiePrefs) async -> ProviderQuota {
        do {
            let cookies = try BrowserCookieReader().cookies(forHostSuffix: "claude.ai", prefs: prefs)
            guard !cookies.isEmpty else { return err("Not signed in") }
            guard let org = cookies["lastActiveOrg"], !org.isEmpty else { return err("No org ID") }

            let cookieHeader = cookies.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
            guard let url = URL(string: "https://claude.ai/api/organizations/\(org)/usage") else {
                return err("Bad URL")
            }
            var req = URLRequest(url: url)
            req.timeoutInterval = 15
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue("https://claude.ai", forHTTPHeaderField: "Origin")
            req.setValue("https://claude.ai/settings/usage", forHTTPHeaderField: "Referer")
            req.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
            req.setValue(userAgent, forHTTPHeaderField: "User-Agent")

            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
                log("claude usage HTTP \(http.statusCode): \(string(data))")
                if http.statusCode == 401 || http.statusCode == 403 { return err("Session expired") }
                return err("HTTP \(http.statusCode)")
            }
            log("claude usage raw: \(string(data))")
            return parse(data)
        } catch let e as CookieError {
            return err(e.description)
        } catch {
            return err("Read failed")
        }
    }

    // MARK: Parsing

    private static func parse(_ data: Data) -> ProviderQuota {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return err("Parse failed")
        }
        var windows: [QuotaWindow] = []
        if let w = makeWindow(obj["five_hour"], label: "5-Hour") { windows.append(w) }
        if let w = makeWindow(obj["seven_day"], label: "7-Day") { windows.append(w) }
        // per-model 7-day sub-limits (present only on some plans; hidden by default)
        if let w = makeWindow(obj["seven_day_opus"], label: "Opus") { windows.append(w) }
        if let w = makeWindow(obj["seven_day_sonnet"], label: "Sonnet") { windows.append(w) }
        if windows.isEmpty { return err("No quota fields") }
        return ProviderQuota(name: "Claude", windows: windows)
    }

    private static func makeWindow(_ any: Any?, label: String) -> QuotaWindow? {
        guard let w = any as? [String: Any] else { return nil }
        let rawUtil = numeric(w["utilization"]) ?? numeric(w["used"]) ?? 0
        let usedFraction = min(1, max(0, rawUtil / 100)) // API percent is 0–100
        let reset = parseDate(w["resets_at"]) ?? parseDate(w["reset_at"])
        return QuotaWindow(label: label, utilization: usedFraction, resetsAt: reset)
    }

    private static func numeric(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let s = any as? String { return Double(s) }
        return nil
    }

    private static func parseDate(_ any: Any?) -> Date? {
        if let s = any as? String {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = iso.date(from: s) { return d }
            iso.formatOptions = [.withInternetDateTime]
            if let d = iso.date(from: s) { return d }
        }
        if let n = numeric(any) { return Date(timeIntervalSince1970: n > 1e12 ? n / 1000 : n) }
        return nil
    }

    // MARK: Helpers

    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " +
        "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"

    private static func err(_ msg: String) -> ProviderQuota {
        ProviderQuota(name: "Claude", windows: [], error: msg)
    }

    private static func string(_ data: Data) -> String {
        String(data: data, encoding: .utf8) ?? "<\(data.count) bytes>"
    }

    private static func log(_ msg: String) {
        FileHandle.standardError.write(Data(("[LimitHUD] " + msg + "\n").utf8))
    }
}
