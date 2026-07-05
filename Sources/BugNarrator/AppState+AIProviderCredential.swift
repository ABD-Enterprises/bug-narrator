import Foundation

extension AppState {
    func validateAPIKey() async {
        await aiProviderSettings.validateConnection()
    }

    func removeAPIKey() {
        aiProviderSettings.removeCredential()
    }
}
