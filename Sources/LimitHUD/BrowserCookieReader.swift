import Foundation
import Security
import CBridge

enum CookieError: Error, CustomStringConvertible {
    case noCookieDB
    case noKeychainKey
    case sqlite(String)

    var description: String {
        switch self {
        case .noCookieDB:    return "No browser cookies found"
        case .noKeychainKey: return "Keychain access denied"
        case .sqlite(let m): return "DB error: \(m)"
        }
    }
}

/// A supported Chromium-based browser: where its cookies live + its Keychain key name.
struct Browser: Identifiable, Hashable {
    let id: String
    let name: String
    let base: String            // relative to ~/Library/Application Support
    let keychainService: String
}

/// Which browser/profile to read. "auto" = try all installed.
struct CookiePrefs: Sendable {
    let browser: String
    let profile: String
    static let auto = CookiePrefs(browser: "auto", profile: "auto")
}

/// Reads & decrypts cookies from any supported Chromium browser on macOS.
/// All Chromium browsers share the AES-128-CBC + Keychain scheme; only the
/// cookie path and the "<Browser> Safe Storage" Keychain name differ.
struct BrowserCookieReader {

    static let supported: [Browser] = [
        Browser(id: "chrome",   name: "Chrome",   base: "Google/Chrome",                keychainService: "Chrome Safe Storage"),
        Browser(id: "brave",    name: "Brave",    base: "BraveSoftware/Brave-Browser",  keychainService: "Brave Safe Storage"),
        Browser(id: "edge",     name: "Edge",     base: "Microsoft Edge",               keychainService: "Microsoft Edge Safe Storage"),
        Browser(id: "arc",      name: "Arc",      base: "Arc/User Data",                keychainService: "Arc Safe Storage"),
        Browser(id: "vivaldi",  name: "Vivaldi",  base: "Vivaldi",                      keychainService: "Vivaldi Safe Storage"),
        Browser(id: "chromium", name: "Chromium", base: "Chromium",                     keychainService: "Chromium Safe Storage"),
        Browser(id: "opera",    name: "Opera",    base: "com.operasoftware.Opera",      keychainService: "Opera Safe Storage"),
    ]

    private var appSupport: String { NSHomeDirectory() + "/Library/Application Support" }

    // MARK: Discovery (main-thread friendly: only filesystem checks)

    func installedBrowsers() -> [Browser] {
        Self.supported.filter { !profiles(for: $0).isEmpty }
    }

    /// Friendly profile label from the browser's "Local State" (name + account email),
    /// so users can tell e.g. a "Work" Google account from "Personal".
    func profileDisplayName(_ b: Browser, _ profile: String) -> String {
        if profile == "." { return "Main" }
        let lsPath = "\(appSupport)/\(b.base)/Local State"
        guard let data = FileManager.default.contents(atPath: lsPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cache = (json["profile"] as? [String: Any])?["info_cache"] as? [String: Any],
              let info = cache[profile] as? [String: Any] else { return profile }
        let name = (info["name"] as? String) ?? ""
        let email = (info["user_name"] as? String) ?? ""
        if !name.isEmpty && !email.isEmpty && name != email { return "\(name) · \(email)" }
        if !name.isEmpty { return name }
        if !email.isEmpty { return email }
        return profile
    }

    /// Profile folder names that contain a Cookies DB. "." means the base itself (Opera).
    func profiles(for b: Browser) -> [String] {
        let base = "\(appSupport)/\(b.base)"
        let fm = FileManager.default
        var out: [String] = []
        if fm.fileExists(atPath: "\(base)/Cookies") { out.append(".") }
        if let items = try? fm.contentsOfDirectory(atPath: base) {
            for item in items where fm.fileExists(atPath: "\(base)/\(item)/Cookies") { out.append(item) }
        }
        // Default first, then the rest alphabetically
        return out.sorted { ($0 == "Default" ? "" : $0) < ($1 == "Default" ? "" : $1) }
    }

    // MARK: Cookie reading

    private struct Candidate { let browser: Browser; let dbPath: String }

    private func candidates(_ prefs: CookiePrefs) -> [Candidate] {
        let browsers = prefs.browser == "auto"
            ? installedBrowsers()
            : Self.supported.filter { $0.id == prefs.browser }
        var out: [Candidate] = []
        for b in browsers {
            let base = "\(appSupport)/\(b.base)"
            let profs = prefs.profile == "auto" ? profiles(for: b) : [prefs.profile]
            for p in profs {
                let db = (p == ".") ? "\(base)/Cookies" : "\(base)/\(p)/Cookies"
                if FileManager.default.fileExists(atPath: db) {
                    out.append(Candidate(browser: b, dbPath: db))
                }
            }
        }
        return out
    }

    /// Decrypted name→value cookies for a host suffix, from the first candidate
    /// (browser/profile) that yields any cookies for that host.
    func cookies(forHostSuffix suffix: String, prefs: CookiePrefs = .auto) throws -> [String: String] {
        let cands = candidates(prefs)
        guard !cands.isEmpty else { throw CookieError.noCookieDB }

        var keyByBrowser: [String: Data] = [:]
        var gotAnyKey = false

        for cand in cands {
            let key: Data
            if let cached = keyByBrowser[cand.browser.id] {
                key = cached
            } else if let derived = deriveKey(service: cand.browser.keychainService) {
                keyByBrowser[cand.browser.id] = derived
                key = derived
                gotAnyKey = true
            } else {
                continue // key denied/missing for this browser — try the next one
            }
            if let result = try? readAndDecrypt(dbPath: cand.dbPath, key: key, suffix: suffix),
               !result.isEmpty {
                return result
            }
        }
        if !gotAnyKey { throw CookieError.noKeychainKey }
        return [:] // DBs + key OK but nothing for this host → caller treats as "not signed in"
    }

    private func readAndDecrypt(dbPath: String, key: Data, suffix: String) throws -> [String: String] {
        var db: OpaquePointer?
        guard sqlite3_open_v2("file:\(dbPath)?immutable=1", &db,
                              SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            sqlite3_close(db)
            throw CookieError.sqlite(msg)
        }
        defer { sqlite3_close(db) }

        let version = metaVersion(db)
        var result: [String: String] = [:]
        var stmt: OpaquePointer?
        let sql = "SELECT name, value, encrypted_value FROM cookies WHERE host_key LIKE '%\(suffix)'"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw CookieError.sqlite(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let namePtr = sqlite3_column_text(stmt, 0) else { continue }
            let name = String(cString: namePtr)
            let encLen = Int(sqlite3_column_bytes(stmt, 2))
            if encLen > 0, let blob = sqlite3_column_blob(stmt, 2) {
                if let dec = decrypt(Data(bytes: blob, count: encLen), key: key, version: version) {
                    result[name] = dec
                }
            } else if let valPtr = sqlite3_column_text(stmt, 1) {
                let v = String(cString: valPtr)
                if !v.isEmpty { result[name] = v }
            }
        }
        return result
    }

    // MARK: Key derivation

    private func deriveKey(service: String) -> Data? {
        guard let password = safeStoragePassword(service: service) else { return nil }
        return pbkdf2SHA1(password: password, salt: Data("saltysalt".utf8), rounds: 1003, keyLen: 16)
    }

    private func safeStoragePassword(service: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return data
    }

    // MARK: Decryption

    private func decrypt(_ enc: Data, key: Data, version: Int) -> String? {
        guard enc.count > 3,
              let prefix = String(data: enc.prefix(3), encoding: .utf8), prefix == "v10" else {
            return String(data: enc, encoding: .utf8)
        }
        let body = Data(enc.dropFirst(3))
        let iv = Data(repeating: 0x20, count: 16)
        guard var plain = aesCBCDecrypt(body, key: key, iv: iv) else { return nil }
        if version >= 24, plain.count > 32 { plain = Data(plain.dropFirst(32)) }
        return String(data: plain, encoding: .utf8)
    }

    private func metaVersion(_ db: OpaquePointer?) -> Int {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT value FROM meta WHERE key='version'", -1, &stmt, nil) == SQLITE_OK
        else { return 0 }
        defer { sqlite3_finalize(stmt) }
        if sqlite3_step(stmt) == SQLITE_ROW, let p = sqlite3_column_text(stmt, 0) {
            return Int(String(cString: p)) ?? 0
        }
        return 0
    }

    private func pbkdf2SHA1(password: Data, salt: Data, rounds: Int, keyLen: Int) -> Data? {
        var derived = [UInt8](repeating: 0, count: keyLen)
        let status = password.withUnsafeBytes { pw -> Int32 in
            salt.withUnsafeBytes { st -> Int32 in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    pw.bindMemory(to: Int8.self).baseAddress, password.count,
                    st.bindMemory(to: UInt8.self).baseAddress, salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                    UInt32(rounds), &derived, keyLen
                )
            }
        }
        return status == Int32(kCCSuccess) ? Data(derived) : nil
    }

    private func aesCBCDecrypt(_ data: Data, key: Data, iv: Data) -> Data? {
        var out = [UInt8](repeating: 0, count: data.count + kCCBlockSizeAES128)
        var moved = 0
        let status = data.withUnsafeBytes { d -> Int32 in
            key.withUnsafeBytes { k -> Int32 in
                iv.withUnsafeBytes { v -> Int32 in
                    CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            k.baseAddress, key.count, v.baseAddress,
                            d.baseAddress, data.count, &out, out.count, &moved)
                }
            }
        }
        guard status == Int32(kCCSuccess) else { return nil }
        return Data(out.prefix(moved))
    }
}
