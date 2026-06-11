import Foundation

/// Builds a User-Agent matching the installed Chrome's major version. Modern Chrome
/// freezes its UA to `Chrome/<major>.0.0.0`, so matching the major lets a `cf_clearance`
/// cookie (bound to UA) validate — which is what gets us past Cloudflare's challenge.
enum UserAgent {
    static let major: Int = chromiumMajor() ?? 131
    static let value: String =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " +
        "(KHTML, like Gecko) Chrome/\(major).0.0.0 Safari/537.36"

    /// Read the Chromium major version from an installed browser whose bundle
    /// version tracks Chromium (Chrome, Edge). Brave/Arc/Vivaldi version their
    /// own way, so we skip those here and fall back to a sane default.
    private static func chromiumMajor() -> Int? {
        let apps = ["/Applications/Google Chrome.app",
                    "/Applications/Microsoft Edge.app",
                    "/Applications/Chromium.app"]
        for app in apps {
            let plist = app + "/Contents/Info.plist"
            if let d = NSDictionary(contentsOfFile: plist),
               let v = d["CFBundleShortVersionString"] as? String,
               let first = v.split(separator: ".").first, let major = Int(first) {
                return major
            }
        }
        return nil
    }
}

enum Net {
    /// Apply the headers a real Chrome XHR sends, so first-party APIs behind
    /// Cloudflare are more likely to accept the request with the session cookie.
    static func applyChromiumHeaders(_ req: inout URLRequest, cookie: String) {
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(UserAgent.value, forHTTPHeaderField: "User-Agent")
        req.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        req.setValue("\"Not_A Brand\";v=\"8\", \"Chromium\";v=\"\(UserAgent.major)\", \"Google Chrome\";v=\"\(UserAgent.major)\"",
                     forHTTPHeaderField: "sec-ch-ua")
        req.setValue("?0", forHTTPHeaderField: "sec-ch-ua-mobile")
        req.setValue("\"macOS\"", forHTTPHeaderField: "sec-ch-ua-platform")
        req.setValue("empty", forHTTPHeaderField: "Sec-Fetch-Dest")
        req.setValue("cors", forHTTPHeaderField: "Sec-Fetch-Mode")
        req.setValue("same-origin", forHTTPHeaderField: "Sec-Fetch-Site")
        req.setValue(cookie, forHTTPHeaderField: "Cookie")
    }

    /// Did this response come back as a Cloudflare challenge page?
    static func isCloudflareChallenge(status: Int, body: String, response: URLResponse?) -> Bool {
        guard status == 403 || status == 503 || status == 429 else { return false }
        let html = (response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Type")?.contains("text/html") ?? false
        return html || body.contains("Just a moment")
            || body.contains("challenges.cloudflare.com")
            || body.contains("cf-browser-verification")
            || body.contains("__cf_chl")
    }
}
