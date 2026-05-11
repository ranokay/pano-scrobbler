import Foundation
import Core
import Security

public actor KeychainSecretStore: SecretStore {
    private let service: String

    public init(service: String = "com.arn.scrobble.mac.credentials") {
        self.service = service
    }

    public func loadCredentials(reference: String) async throws -> ServiceCredentials? {
        var query = baseQuery(reference: reference)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainError(status: status)
        }

        guard let data = result as? Data else {
            return nil
        }

        return try JSONDecoder().decode(ServiceCredentials.self, from: data)
    }

    public func saveCredentials(_ credentials: ServiceCredentials, reference: String) async throws {
        let data = try JSONEncoder().encode(credentials)
        var query = baseQuery(reference: reference)

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecItemNotFound {
            query.merge(attributes) { _, new in new }
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError(status: addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw KeychainError(status: updateStatus)
        }
    }

    public func deleteCredentials(reference: String) async throws {
        let status = SecItemDelete(baseQuery(reference: reference) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }

    private func baseQuery(reference: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: reference
        ]
    }

    /// Synchronous credential loading (nonisolated) for use cases where
    /// we can't await (e.g., constructing a service reference on MainActor).
    nonisolated public func loadCredentialsSync(reference: String) throws -> ServiceCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: reference,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError(status: status)
        }

        return try JSONDecoder().decode(ServiceCredentials.self, from: data)
    }
}

public struct KeychainError: LocalizedError, Sendable {
    public var status: OSStatus

    public init(status: OSStatus) {
        self.status = status
    }

    public var errorDescription: String? {
        if let message = SecCopyErrorMessageString(status, nil) as String? {
            return message
        }
        return "Keychain error \(status)."
    }
}
