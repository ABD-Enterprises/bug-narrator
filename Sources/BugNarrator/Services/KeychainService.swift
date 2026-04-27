import Foundation
import LocalAuthentication
import Security

final class KeychainService: KeychainServicing {
    static func shouldBypassSystemKeychain(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil
    }

    static func makeReadQuery(
        forService service: String,
        account: String,
        allowInteraction: Bool
    ) -> [CFString: Any] {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        if !allowInteraction {
            let context = LAContext()
            context.interactionNotAllowed = true
            query[kSecUseAuthenticationContext] = context
        }

        return query
    }

    func string(forService service: String, account: String, allowInteraction: Bool) throws -> String? {
        if Self.shouldBypassSystemKeychain() {
            return nil
        }

        let query = Self.makeReadQuery(
            forService: service,
            account: account,
            allowInteraction: allowInteraction
        )

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data else {
                return nil
            }
            return String(data: data, encoding: .utf8)
        case errSecItemNotFound:
            return nil
        case errSecInteractionNotAllowed, errSecAuthFailed:
            throw KeychainError.interactionRequired
        default:
            throw KeychainError.unhandledStatus(status)
        }
    }

    func setString(_ value: String, service: String, account: String) throws {
        if Self.shouldBypassSystemKeychain() {
            return
        }

        let data = Data(value.utf8)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]

        let attributes: [CFString: Any] = [
            kSecValueData: data
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var addQuery = query
            addQuery[kSecValueData] = data

            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unhandledStatus(addStatus)
            }
        default:
            throw KeychainError.unhandledStatus(updateStatus)
        }
    }

    func deleteValue(service: String, account: String) throws {
        if Self.shouldBypassSystemKeychain() {
            return
        }

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledStatus(status)
        }
    }
}

enum KeychainError: LocalizedError {
    case interactionRequired
    case unhandledStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .interactionRequired:
            return "Keychain access requires user approval."
        case .unhandledStatus(let status):
            return "Keychain returned OSStatus \(status)."
        }
    }
}
