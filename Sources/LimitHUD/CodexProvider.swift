import Foundation

/// Fetches Codex (ChatGPT) quota using Chrome session cookies.
/// chatgpt.com cookies → /api/auth/session (accessToken) → /backend-api/codex/usage.
/// Parsing is defensive + logs raw JSON, since the usage shape is verified at runtime.
enum CodexProvider {

    static func fetch() async -> ProviderQuota {
        do {
            let cookies = try ChromeCookieReader().cookies(forHostSuffix: "chatgpt.com")
            guard !cookies.isEmpty else { return err("Not signed in (Chrome)") }
            let cookieHeader = cookies.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")

            guard let token = try await accessToken(cookieHeader: cookieHeader) else {
                return err("Session expired")
            }

            guard let url = URL(string: "https://chatgpt.com/backend-api/codex/usage") else {
                return err("Bad URL")
            }
            var req = URLRequest(url: url)
            req.timeoutInterval = 15
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
            req.setValue(userAgent, forHTTPHeaderField: "User-Agent")

            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
                log("codex usage HTTP \(http.statusCode): \(string(data))")
                if http.statusCode == 401 || http.statusCode == 403 { return err("Session expired") }
                return err("HTTP \(http.statusCode)")
            }
            log("codex usage raw: \(string(data))")
            return parse(data)
        } catch let e as CookieError {
            return err(e.description)
        } catch {
            return err("Read failed")
        }
    }

    // MARK: Access token

    private static func accessToken(cookieHeader: String) async throws -> String? {
        guard let url = URL(string: "https://chatgpt.com/api/auth/session") else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            log("codex session HTTP \(http.statusCode): \(string(data))")
            return nil
        }
        let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let token = obj?["accessToken"] as? String, !token.isEmpty { return token }
        log("codex session had no accessToken: \(string(data))")
        return nil
    }

    // MARK: Parsing

    private static func parse(_ data: Data) -> ProviderQuota {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return err("Parse failed")
        }
        let rate = (obj["rate_limit"] as? [String: Any])
            ?? (obj["rate_limits"] as? [String: Any])
            ?? obj
        var windows: [QuotaWindow] = []
        if let w = makeWindow(rate["primary_window"] ?? rate["primary"], label: "5-Hour") {
            windows.append(w)
        }
        if let w = makeWindow(rate["secondary_window"] ?? rate["secondary"], label: "7-Day") {
            windows.append(w)
        }
        if windows.isEmpty { return err("No quota fields") }
        return ProviderQuota(name: "Codex", windows: windows)
    }

    private static func makeWindow(_ any: Any?, label: String) -> QuotaWindow? {
        guard let w = any as? [String: Any] else { return nil }
        let pct = numeric(w["used_percent"]) ?? numeric(w["utilization"])
            ?? numeric(w["percent_used"]) ?? numeric(w["used"]) ?? 0
        let usedFraction = min(1, max(0, pct / 100)) // API percent is 0–100
        let reset = relativeReset(w) ?? parseDate(w["resets_at"]) ?? parseDate(w["reset_at"])
        return QuotaWindow(label: label, utilization: usedFraction, resetsAt: reset)
    }

    private static func relativeReset(_ w: [String: Any]) -> Date? {
        for key in ["resets_in_seconds", "reset_after_seconds", "reset_in_seconds", "seconds_until_reset"] {
            if let s = numeric(w[key]) { return Date(timeIntervalSinceNow: s) }
        }
        if let mins = numeric(w["resets_in_minutes"]) { return Date(timeIntervalSinceNow: mins * 60) }
        return nil
    }

    // MARK: Helpers

    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " +
        "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"

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

    private static func err(_ msg: String) -> ProviderQuota {
        ProviderQuota(name: "Codex", windows: [], error: msg)
    }

    private static func string(_ data: Data) -> String {
        String(data: data, encoding: .utf8) ?? "<\(data.count) bytes>"
    }

    private static func log(_ msg: String) {
        FileHandle.standardError.write(Data(("[LimitHUD] " + msg + "\n").utf8))
    }
}
