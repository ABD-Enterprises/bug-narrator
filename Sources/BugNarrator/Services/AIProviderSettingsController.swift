import Combine
import Foundation

@MainActor
final class AIProviderSettingsController: ObservableObject {
    @Published private(set) var apiKeyValidationState: APIKeyValidationState = .idle

    var showSettingsWindow: (() -> Void)?

    private let settingsStore: SettingsStore
    private let transcriptionClient: any TranscriptionServing
    private let logger = DiagnosticsLogger(category: .settings)
    private var isValidating = false

    init(
        settingsStore: SettingsStore,
        transcriptionClient: any TranscriptionServing
    ) {
        self.settingsStore = settingsStore
        self.transcriptionClient = transcriptionClient
    }

    func validateConnection() async {
        guard !isValidating else {
            return
        }

        if let compatibilityIssue = settingsStore.aiProviderCompatibilityIssue {
            apiKeyValidationState = .failure(compatibilityIssue)
            showSettingsWindow?()
            return
        }

        guard let providerCredential = settingsStore.aiProviderCredentialForUserInitiatedAccess() else {
            let provider = settingsStore.aiProvider
            let message = provider.requiresAPIKey
                ? AppError.missingAPIKey.userMessage(for: provider)
                : "Choose a valid \(provider.displayName) base URL before validating the connection."
            apiKeyValidationState = .failure(message)
            showSettingsWindow?()
            return
        }

        isValidating = true
        apiKeyValidationState = .validating
        defer { isValidating = false }

        do {
            try await transcriptionClient.validateAPIKey(
                providerCredential,
                apiBaseURL: settingsStore.openAIBaseURLValue
            )
            apiKeyValidationState = .success(settingsStore.aiProvider.successMessage)
            logger.info(
                .validateAIProviderSucceeded,
                "The AI provider validation flow succeeded.",
                metadata: ["provider": settingsStore.aiProvider.rawValue]
            )
        } catch {
            let appError = (error as? AppError) ?? .transcriptionFailure(error.localizedDescription)
            apiKeyValidationState = .failure(appError.userMessage(for: settingsStore.aiProvider))
            logger.warning(
                .validateAIProviderFailed,
                appError.userMessage(for: settingsStore.aiProvider),
                metadata: ["provider": settingsStore.aiProvider.rawValue]
            )
        }
    }

    func removeCredential() {
        settingsStore.removeAPIKey()
        apiKeyValidationState = .idle
        logger.info(
            .removeAIProviderCredential,
            "The AI provider credential was removed from local storage.",
            metadata: ["provider": settingsStore.aiProvider.rawValue]
        )
    }
}
