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

struct KeychainSessionDataProtector: SessionDataProtecting {
    static let service = "BugNarrator.SessionData"
    static let account = "session-data-encryption-key"

    private static let payloadPrefix = Data("BNENC1\n".utf8)

    let writesEncryptedPayloads = true

    private let keychainService: any KeychainServicing

    init(keychainService: any KeychainServicing = KeychainService()) {
        self.keychainService = keychainService
    }

    func protect(_ data: Data) throws -> Data {
        let sealedBox = try AES.GCM.seal(data, using: symmetricKey())
        guard let combined = sealedBox.combined else {
            throw AppError.storageFailure("Encrypted session data could not be prepared.")
        }

        return Self.payloadPrefix + combined
    }

    func unprotect(_ data: Data) throws -> Data {
        guard data.starts(with: Self.payloadPrefix) else {
            return data
        }

        let encryptedData = data.dropFirst(Self.payloadPrefix.count)
        let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
        return try AES.GCM.open(sealedBox, using: symmetricKey())
    }

    private func symmetricKey() throws -> SymmetricKey {
        if let storedValue = try keychainService.string(
            forService: Self.service,
            account: Self.account,
            allowInteraction: true
        ),
           let keyData = Data(base64Encoded: storedValue),
           keyData.count == 32 {
            return SymmetricKey(data: keyData)
        }

        var keyData = Data(count: 32)
        let status = keyData.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, 32, buffer.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw AppError.storageFailure("A local session encryption key could not be generated.")
        }

        try keychainService.setString(
            keyData.base64EncodedString(),
            service: Self.service,
            account: Self.account
        )
        return SymmetricKey(data: keyData)
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
