import Foundation
import Security

/// Thin wrapper around the Security framework so the rest of the app can
/// stash short string secrets (OAuth refresh/access tokens, webhook URLs
/// if we ever stop using @AppStorage) without hand-rolling SecItem dicts
/// at every call site.
///
/// One service identifier per call — this matches the Apple Keychain model
/// where (service, account) is the unique primary key. We treat `service`
/// as the namespace (e.g. "spotify") and `account` as the field name
/// (e.g. "refresh_token") so a single integration can store multiple values.
enum KeychainStorage {

    enum KeychainError: Error {
        case unexpectedStatus(OSStatus)
        case invalidData
    }

    /// Writes the value, overwriting any existing entry. Empty / nil clears
    /// the entry so callers can use the same code path for sign-out.
    static func setString(_ value: String?, service: String, account: String) throws {
        guard let value = value, !value.isEmpty else {
            try delete(service: service, account: account)
            return
        }
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.invalidData
        }

        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        // Try update first; fall back to add. SecItemUpdate is the only way
        // to avoid a duplicate-item error when a key already exists.
        //
        // Re-apply `kSecAttrAccessible` on every update path so a future
        // change to the default accessibility (e.g. tightening it) actually
        // takes effect on existing items, not just freshly-added ones.
        let attributesToUpdate: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributesToUpdate as CFDictionary)

        if updateStatus == errSecSuccess {
            return
        }

        if updateStatus == errSecItemNotFound {
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = data
            // Restrict access to "this device only" — refresh tokens should
            // never sync to a different machine via iCloud Keychain.
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            if addStatus != errSecSuccess {
                throw KeychainError.unexpectedStatus(addStatus)
            }
            return
        }

        throw KeychainError.unexpectedStatus(updateStatus)
    }

    static func getString(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func delete(service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
