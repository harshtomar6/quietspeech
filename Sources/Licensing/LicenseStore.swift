import Foundation
import Security

public protocol LicenseStore: AnyObject {
    func string(for key: String) -> String?
    func set(_ value: String?, for key: String)
}

public final class KeychainLicenseStore: LicenseStore {
    private let service: String

    public init(service: String = "dev.harsh.quietspeech.license") {
        self.service = service
    }

    private func query(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }

    public func string(for key: String) -> String? {
        var query = query(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    public func set(_ value: String?, for key: String) {
        let base = query(for: key)
        SecItemDelete(base as CFDictionary)

        guard let value, !value.isEmpty else { return }
        var query = base
        query[kSecValueData as String] = Data(value.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(query as CFDictionary, nil)
    }
}

final class MemoryLicenseStore: LicenseStore {
    private var values: [String: String] = [:]

    func string(for key: String) -> String? { values[key] }

    func set(_ value: String?, for key: String) {
        values[key] = value
    }
}
