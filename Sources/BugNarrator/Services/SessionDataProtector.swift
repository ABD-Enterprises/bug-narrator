import CryptoKit
import Foundation
import Security

protocol SessionDataProtecting {
    var writesEncryptedPayloads: Bool { get }
    func protect(_ data: Data) throws -> Data
    func unprotect(_ data: Data) throws -> Data
}

struct PlaintextSessionDataProtector: SessionDataProtecting {
    let writesEncryptedPayloads = false

    func protect(_ data: Data) throws -> Data {
        data
    }

    func unprotect(_ data: Data) throws -> Data {
        data
    }
}
enum SessionDataProtectorFactory {
    static func automatic(
        keychainService: any KeychainServicing = KeychainService(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> any SessionDataProtecting {
        if KeychainService.shouldBypassSystemKeychain(environment: environment) {
            return PlaintextSessionDataProtector()
        }

        return KeychainSessionDataProtector(keychainService: keychainService)
    }
}
