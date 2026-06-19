import Foundation
import Security

/// 제공자별 API 키를 기기 Keychain에 저장. (코드/리포에 키를 넣지 않습니다.)
enum KeychainStore {
    private static let service = "com.oneul.app.aikeys"

    @discardableResult
    static func save(_ key: String, for provider: AIProvider) -> Bool {
        let account = provider.keychainAccount
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(base as CFDictionary)

        guard !key.isEmpty else { return true }   // 빈 값이면 삭제만
        var attrs = base
        attrs[kSecValueData as String] = Data(key.utf8)
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(attrs as CFDictionary, nil) == errSecSuccess
    }

    static func load(for provider: AIProvider) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8) else { return nil }
        return key
    }

    static func delete(for provider: AIProvider) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
    }
}
