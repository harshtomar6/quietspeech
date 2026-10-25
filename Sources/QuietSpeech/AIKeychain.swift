import Foundation
import Security

enum AIKeychain {

    private static let service = "dev.harsh.quietspeech.ai"
    private static let legacyAccount = "api-key"

    private static func account(for provider: AIProvider) -> String {
        "api-key.\(provider.rawValue)"
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func hasLegacyKey() -> Bool {
        read(account: legacyAccount)?.isEmpty == false
    }

    static func hasKey(for provider: AIProvider) -> Bool {
        read(for: provider)?.isEmpty == false
    }

    static func read(for provider: AIProvider) -> String? {
        read(account: account(for: provider))
    }

    private static func read(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    @discardableResult
    static func save(_ value: String, for provider: AIProvider) -> Bool {
        delete(for: provider)
        var query = baseQuery(account: account(for: provider))
        query[kSecValueData as String] = Data(value.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func delete(for provider: AIProvider) {
        delete(account: account(for: provider))
    }

    private static func delete(account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }

    static func migrateLegacyKey(to provider: AIProvider) {
        guard provider.usesEndpoint, let value = read(account: legacyAccount), !value.isEmpty else {
            return
        }
        if read(for: provider) == nil {
            _ = save(value, for: provider)
        }
        delete(account: legacyAccount)
    }
}
