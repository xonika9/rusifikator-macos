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

struct KeychainCredentialStore: CredentialStore {
    static let defaultService = "dev.gotacat.Rusifikator"
    static let defaultAPIKeyAccount = "provider-api-key"
    static let defaultOriginAccount = "provider-origin"

    private let service: String
    private let apiKeyAccount: String
    private let originAccount: String

    init(
        service: String = Self.defaultService,
        apiKeyAccount: String = Self.defaultAPIKeyAccount,
        originAccount: String = Self.defaultOriginAccount
    ) {
        self.service = service
        self.apiKeyAccount = apiKeyAccount
        self.originAccount = originAccount
    }

    func saveAPIKey(_ apiKey: String, for providerURL: URL) throws {
        let origin = try canonicalOrigin(for: providerURL)

        try deleteValue(account: originAccount)
        do {
            try upsert(Data(apiKey.utf8), account: apiKeyAccount)
            try upsert(Data(origin.utf8), account: originAccount)
        } catch {
            try? deleteValue(account: apiKeyAccount)
            try? deleteValue(account: originAccount)
            throw error
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
        var query = baseQuery(account: account)
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

    private func upsert(_ data: Data, account: String) throws {
        let query = baseQuery(account: account)
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

    private func deleteValue(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.keychainFailure(status)
        }
    }

    private func baseQuery(account: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
    }
}
