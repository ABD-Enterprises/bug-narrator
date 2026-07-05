import Foundation

extension AppState {
    // MARK: - Methods

    func validateAPIKey() async {
        await aiProviderSettings.validateConnection()
    }

    func removeAPIKey() {
        aiProviderSettings.removeCredential()
    }

    // MARK: - Computed properties

    var apiKeyValidationState: APIKeyValidationState {
        aiProviderSettings.apiKeyValidationState
    }
}
