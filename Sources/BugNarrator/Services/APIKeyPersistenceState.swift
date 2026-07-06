import Foundation

enum APIKeyPersistenceState: Equatable {
    case empty
    case keychain
    case keychainLocked
    case sessionOnly
    case pendingSave
}
