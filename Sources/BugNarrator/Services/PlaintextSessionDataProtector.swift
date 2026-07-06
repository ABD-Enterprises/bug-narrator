import Foundation

struct PlaintextSessionDataProtector: SessionDataProtecting {
    let writesEncryptedPayloads = false

    func protect(_ data: Data) throws -> Data {
        data
    }

    func unprotect(_ data: Data) throws -> Data {
        data
    }
}
