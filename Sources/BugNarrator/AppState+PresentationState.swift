import Foundation

extension AppState {
    var status: AppStatus {
        presentationState.status
    }

    var currentError: AppError? {
        presentationState.currentError
    }

    var transientToast: TransientToast? {
        presentationState.transientToast
    }

    var userFacingStatusMessage: String? {
        if status.phase == .error || status.phase == .idle,
           let pendingSession = transcriptStore.latestPendingTranscriptionSession {
            let provider = settingsStore.aiProvider
            if needsAPIKeySetup {
                return settingsStore.aiProviderCompatibilityIssue
                    ?? currentError?.userMessage(for: provider)
                    ?? pendingSession.transcriptionRetryMessage(for: provider)
                    ?? "Update your \(provider.displayName) settings, then retry transcription."
            }
            return "Your recording \(pendingSession.title) is saved. \(provider.displayName) is ready; retry transcription when you are ready."
        }

        if status.phase == .error,
           currentError?.suggestsProviderSettings(for: settingsStore.aiProvider) == true,
           !needsAPIKeySetup {
            return "The selected provider is configured now. Try the action again with the current settings."
        }

        return status.detail
    }
}
