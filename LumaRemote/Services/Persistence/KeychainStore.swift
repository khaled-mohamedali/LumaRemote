import Foundation
import Security

/// Stores the TV-issued `client-key` for each paired TV. The key is never logged or
/// written anywhere else. Items are device-only (not synced to iCloud, not in backups
/// restored to other devices).
struct KeychainStore {
    private let service = "com.lumaremote.webos.client-key"

    func clientKey(for deviceID: UUID) -> String? {
        var query = baseQuery(deviceID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    func setClientKey(_ key: String, for deviceID: UUID) -> Bool {
        let data = Data(key.utf8)
        let query = baseQuery(deviceID)
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    func deleteClientKey(for deviceID: UUID) {
        SecItemDelete(baseQuery(deviceID) as CFDictionary)
    }

    func hasClientKey(for deviceID: UUID) -> Bool { clientKey(for: deviceID) != nil }

    private func baseQuery(_ deviceID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: deviceID.uuidString,
        ]
    }
}
