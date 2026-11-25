import Foundation
import Security

/// Stores the VPN password as a generic password in the login keychain.
enum Keychain {
    private static let service = "local.OpenBar"

    private static func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func password(for account: String) -> String? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func setPassword(_ password: String, for account: String) -> Bool {
        let data = Data(password.utf8)
        let update = [kSecValueData as String: data]
        var status = SecItemUpdate(query(account) as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var q = query(account)
            q[kSecValueData as String] = data
            status = SecItemAdd(q as CFDictionary, nil)
        }
        return status == errSecSuccess
    }

    static func deletePassword(for account: String) {
        SecItemDelete(query(account) as CFDictionary)
    }
}
