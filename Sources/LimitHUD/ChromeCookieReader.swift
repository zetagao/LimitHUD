import Foundation
import Security
import CBridge

enum CookieError: Error, CustomStringConvertible {
    case noCookieDB
    case noKeychainKey
    case sqlite(String)

    var description: String {
        switch self {
        case .noCookieDB:    return "Chrome cookies not found"
        case .noKeychainKey: return "Keychain access denied"
        case .sqlite(let m): return "DB error: \(m)"
        }
    }
}

/// Reads & decrypts cookies from Chrome's local store on macOS.
/// Chrome encrypts cookie values with AES-128-CBC; the key is derived from a
/// password kept in the login Keychain ("Chrome Safe Storage").
struct ChromeCookieReader {

    /// Decrypted name→value cookies whose host ends with `suffix` (e.g. "claude.ai").
    func cookies(forHostSuffix suffix: String) throws -> [String: String] {
        guard let dbPath = locateCookieDB() else { throw CookieError.noCookieDB }
        guard let key = try deriveKey() else { throw CookieError.noKeychainKey }

        var db: OpaquePointer?
        let uri = "file:\(dbPath)?immutable=1"
        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else {
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
                let enc = Data(bytes: blob, count: encLen)
                if let dec = decrypt(enc, key: key, version: version) {
                    result[name] = dec
                }
            } else if let valPtr = sqlite3_column_text(stmt, 1) {
                let v = String(cString: valPtr)
                if !v.isEmpty { result[name] = v }
            }
        }
        return result
    }

    // MARK: Cookie DB location

    private func locateCookieDB() -> String? {
        let base = NSHomeDirectory() + "/Library/Application Support/Google/Chrome"
        let fm = FileManager.default
        for profile in ["Default", "Profile 1", "Profile 2", "Profile 3"] {
            let p = "\(base)/\(profile)/Cookies"
            if fm.fileExists(atPath: p) { return p }
        }
        // fallback: any profile dir with a Cookies file
        if let items = try? fm.contentsOfDirectory(atPath: base) {
            for item in items {
                let p = "\(base)/\(item)/Cookies"
                if fm.fileExists(atPath: p) { return p }
            }
        }
        return nil
    }

    // MARK: Key derivation

    private func deriveKey() throws -> Data? {
        guard let password = chromeSafeStoragePassword() else { return nil }
        let salt = Data("saltysalt".utf8)
        return pbkdf2SHA1(password: password, salt: salt, rounds: 1003, keyLen: 16)
    }

    /// The "Chrome Safe Storage" generic password from the login Keychain.
    /// First access triggers the macOS keychain authorization prompt.
    private func chromeSafeStoragePassword() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Chrome Safe Storage",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return data
    }

    // MARK: Decryption

    private func decrypt(_ enc: Data, key: Data, version: Int) -> String? {
        // "v10" prefix marks AES-encrypted values on macOS.
        guard enc.count > 3,
              let prefix = String(data: enc.prefix(3), encoding: .utf8), prefix == "v10" else {
            return String(data: enc, encoding: .utf8)
        }
        let body = Data(enc.dropFirst(3))
        let iv = Data(repeating: 0x20, count: 16) // 16 spaces
        guard var plain = aesCBCDecrypt(body, key: key, iv: iv) else { return nil }
        // Chrome ≥ v24 prepends a 32-byte SHA256 domain hash to the plaintext.
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

    // MARK: CommonCrypto primitives

    private func pbkdf2SHA1(password: Data, salt: Data, rounds: Int, keyLen: Int) -> Data? {
        var derived = [UInt8](repeating: 0, count: keyLen)
        let status = password.withUnsafeBytes { pw -> Int32 in
            salt.withUnsafeBytes { st -> Int32 in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    pw.bindMemory(to: Int8.self).baseAddress, password.count,
                    st.bindMemory(to: UInt8.self).baseAddress, salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                    UInt32(rounds),
                    &derived, keyLen
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
                    CCCrypt(
                        CCOperation(kCCDecrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionPKCS7Padding),
                        k.baseAddress, key.count,
                        v.baseAddress,
                        d.baseAddress, data.count,
                        &out, out.count, &moved
                    )
                }
            }
        }
        guard status == Int32(kCCSuccess) else { return nil }
        return Data(out.prefix(moved))
    }
}
