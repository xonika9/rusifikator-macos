import Foundation
import Security

protocol CredentialStore {
    func saveAPIKey(_ apiKey: String, for providerURL: URL) throws
    func apiKey(for providerURL: URL) throws -> String?
    func deleteAPIKey() throws
}

enum CredentialStoreError: Error, Equatable, LocalizedError {
    case invalidProviderOrigin
    case providerOriginMismatch
    case keychainFailure(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidProviderOrigin:
            "Адрес провайдера должен быть корректным HTTPS-адресом без логина и пароля."
        case .providerOriginMismatch:
            "Адрес провайдера изменился. Введи и сохрани API-ключ заново."
        case let .keychainFailure(status):
            "Не удалось обратиться к Keychain (код \(status))."
        }
    }
}

protocol KeychainBackend {
    func readValue(service: String, account: String) throws -> Data?
    func upsert(_ data: Data, service: String, account: String) throws
    func deleteValue(service: String, account: String) throws
}

private struct SecurityKeychainBackend: KeychainBackend {
    func readValue(service: String, account: String) throws -> Data? {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw CredentialStoreError.keychainFailure(errSecDecode)
            }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw CredentialStoreError.keychainFailure(status)
        }
    }

    func upsert(_ data: Data, service: String, account: String) throws {
        let query = baseQuery(service: service, account: account)
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData: data] as CFDictionary
        )

        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var item = query
            item[kSecValueData] = data
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw CredentialStoreError.keychainFailure(addStatus)
            }
        default:
            throw CredentialStoreError.keychainFailure(updateStatus)
        }
    }

    func deleteValue(service: String, account: String) throws {
        let status = SecItemDelete(
            baseQuery(service: service, account: account) as CFDictionary
        )
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.keychainFailure(status)
        }
    }

    private func baseQuery(
        service: String,
        account: String
    ) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
    }
}

struct KeychainCredentialStore: CredentialStore {
    static let defaultService = "dev.gotacat.Rusifikator"
    static let defaultAPIKeyAccount = "provider-api-key"
    static let defaultOriginAccount = "provider-origin"

    private let service: String
    private let apiKeyAccount: String
    private let originAccount: String
    private let backend: any KeychainBackend

    init(
        service: String = Self.defaultService,
        apiKeyAccount: String = Self.defaultAPIKeyAccount,
        originAccount: String = Self.defaultOriginAccount,
        backend: any KeychainBackend = SecurityKeychainBackend()
    ) {
        self.service = service
        self.apiKeyAccount = apiKeyAccount
        self.originAccount = originAccount
        self.backend = backend
    }

    func saveAPIKey(_ apiKey: String, for providerURL: URL) throws {
        let origin = try canonicalOrigin(for: providerURL)
        let previousAPIKey = try readValue(account: apiKeyAccount)
        let previousOrigin = try readValue(account: originAccount)

        do {
            try upsert(Data(apiKey.utf8), account: apiKeyAccount)
            try upsert(Data(origin.utf8), account: originAccount)
        } catch let saveError {
            do {
                try restore(
                    apiKey: previousAPIKey,
                    origin: previousOrigin
                )
            } catch let restoreError {
                throw restoreError
            }
            throw saveError
        }
    }

    func apiKey(for providerURL: URL) throws -> String? {
        let requestedOrigin = try canonicalOrigin(for: providerURL)
        guard let keyData = try readValue(account: apiKeyAccount) else {
            return nil
        }
        guard
            let originData = try readValue(account: originAccount),
            let savedOrigin = String(data: originData, encoding: .utf8),
            savedOrigin == requestedOrigin
        else {
            throw CredentialStoreError.providerOriginMismatch
        }
        guard let apiKey = String(data: keyData, encoding: .utf8) else {
            throw CredentialStoreError.keychainFailure(errSecDecode)
        }
        return apiKey
    }

    func deleteAPIKey() throws {
        var firstError: Error?
        do {
            try deleteValue(account: apiKeyAccount)
        } catch {
            firstError = error
        }
        do {
            try deleteValue(account: originAccount)
        } catch {
            if firstError == nil {
                firstError = error
            }
        }
        if let firstError {
            throw firstError
        }
    }

    private func canonicalOrigin(for url: URL) throws -> String {
        do {
            return try ProviderOrigin.canonicalString(for: url)
        } catch {
            throw CredentialStoreError.invalidProviderOrigin
        }
    }

    private func readValue(account: String) throws -> Data? {
        try backend.readValue(service: service, account: account)
    }

    private func upsert(_ data: Data, account: String) throws {
        try backend.upsert(data, service: service, account: account)
    }

    private func deleteValue(account: String) throws {
        try backend.deleteValue(service: service, account: account)
    }

    private func restore(apiKey: Data?, origin: Data?) throws {
        var firstError: Error?

        do {
            try restore(apiKey, account: apiKeyAccount)
        } catch {
            firstError = error
        }
        do {
            try restore(origin, account: originAccount)
        } catch {
            if firstError == nil {
                firstError = error
            }
        }

        if let firstError {
            throw firstError
        }
    }

    private func restore(_ value: Data?, account: String) throws {
        if let value {
            try upsert(value, account: account)
        } else {
            try deleteValue(account: account)
        }
    }
}
