import Foundation
import LocalAuthentication
import Security

/// The storage boundary used by narration settings.
///
/// Implementations must keep the key out of logs, project files, and other
/// user defaults. The production implementation below stores it in the
/// macOS Keychain; tests and callers that need a different lifecycle can
/// provide an in-memory implementation.
public protocol APIKeyStore: Sendable {
    func save(_ apiKey: String) throws
    func read() throws -> String?
    func delete() throws
}

public enum APIKeyStoreError: Error, LocalizedError, Sendable, Equatable {
    case invalidConfiguration
    case invalidAPIKey
    case keychainFailure(operation: String, status: Int32)
    case invalidStoredValue

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "The Keychain account configuration is invalid."
        case .invalidAPIKey:
            return "Enter a non-empty ElevenLabs API key."
        case let .keychainFailure(operation, status):
            // The OSStatus is useful when diagnosing a local Keychain issue,
            // while the operation name contains no credential material.
            let safeOperation: String
            switch operation {
            case "save", "read", "delete": safeOperation = operation
            default: safeOperation = "access"
            }
            return "Could not " + safeOperation + " the ElevenLabs API key in Keychain (status " + String(status) + ")."
        case .invalidStoredValue:
            return "The ElevenLabs API key in Keychain is not valid UTF-8 data."
        }
    }
}

/// A Keychain-backed API key store.
///
/// Use `init(userID:service:)` when more than one signed-in user can use the
/// app. Each user then receives a distinct Keychain account. The item is
/// device-only and available while the Mac is unlocked; it is never synced to
/// iCloud Keychain.
public final class KeychainAPIKeyStore: APIKeyStore, @unchecked Sendable {
    public static let defaultService = "io.github.m0rg0t.takelet"
    public static let defaultAccount = "elevenlabs-api-key"
    public static let perUserAccountPrefix = "elevenlabs-api-key."

    private let service: String
    private let account: String

    /// Creates the default store, or a store with an explicit service/account.
    ///
    /// Configuration is checked when an operation is performed so this
    /// initializer remains convenient for application dependency injection.
    public init(
        service: String = KeychainAPIKeyStore.defaultService,
        account: String = KeychainAPIKeyStore.defaultAccount
    ) {
        self.service = service
        self.account = account
    }

    /// Creates a per-user Keychain account without ever putting the API key in
    /// a user-facing identifier or file path.
    public convenience init(
        userID: String,
        service: String = KeychainAPIKeyStore.defaultService
    ) throws {
        let account = Self.perUserAccountPrefix + userID
        guard Self.isValidComponent(userID), Self.isValidComponent(service),
              Self.isValidComponent(account) else {
            throw APIKeyStoreError.invalidConfiguration
        }
        self.init(service: service, account: account)
    }

    public func save(_ apiKey: String) throws {
        try validateConfiguration()
        let normalized = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidAPIKey(normalized) else {
            throw APIKeyStoreError.invalidAPIKey
        }

        let query = baseQuery
        let attributes: [String: Any] = [
            kSecValueData as String: Data(normalized.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = Data(normalized.utf8)
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
            // A concurrent writer can create the item between Update and Add.
            // Updating it is safe and avoids reporting a spurious duplicate.
            if status == errSecDuplicateItem {
                status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            }
        }

        guard status == errSecSuccess else {
            throw APIKeyStoreError.keychainFailure(operation: "save", status: status)
        }
    }

    public func read() throws -> String? {
        try validateConfiguration()
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        // Status checks happen during settings/generation actions. Never
        // trigger a Keychain unlock prompt merely because the app launches.
        let authenticationContext = LAContext()
        authenticationContext.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = authenticationContext

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw APIKeyStoreError.keychainFailure(operation: "read", status: status)
        }
        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8),
              Self.isValidAPIKey(value) else {
            throw APIKeyStoreError.invalidStoredValue
        }
        return value
    }

    public func delete() throws {
        try validateConfiguration()
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw APIKeyStoreError.keychainFailure(operation: "delete", status: status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private func validateConfiguration() throws {
        guard Self.isValidComponent(service), Self.isValidComponent(account) else {
            throw APIKeyStoreError.invalidConfiguration
        }
    }

    private static func isValidComponent(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 256 && value.unicodeScalars.allSatisfy {
            !CharacterSet.whitespacesAndNewlines.contains($0) && !CharacterSet.controlCharacters.contains($0)
        }
    }

    private static func isValidAPIKey(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 512 && value.unicodeScalars.allSatisfy {
            // API keys are ASCII HTTP-header tokens. Rejecting other scalar
            // values avoids storing a credential that URLSession cannot send
            // faithfully in `xi-api-key`.
            $0.value >= 0x21 && $0.value <= 0x7E
        }
    }
}
