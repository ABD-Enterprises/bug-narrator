import Foundation

enum DiagnosticsEvent {
    static let appError = DiagnosticsEventName("app_error")
    static let sessionStartRequested = DiagnosticsEventName("session_start_requested")
    static let sessionStartIgnored = DiagnosticsEventName("session_start_ignored")
    static let sessionStartRejected = DiagnosticsEventName("session_start_rejected")
    static let sessionStartPreflightFailed = DiagnosticsEventName("session_start_preflight_failed")
    static let sessionStarted = DiagnosticsEventName("session_started")
    static let sessionStopRequested = DiagnosticsEventName("session_stop_requested")
    static let sessionStopIgnored = DiagnosticsEventName("session_stop_ignored")
    static let sessionStopRejected = DiagnosticsEventName("session_stop_rejected")
    static let transcriptionCompleted = DiagnosticsEventName("transcription_completed")
    static let validateAIProviderSucceeded = DiagnosticsEventName("validate_ai_provider_succeeded")
    static let validateAIProviderFailed = DiagnosticsEventName("validate_ai_provider_failed")
    static let removeAIProviderCredential = DiagnosticsEventName("remove_ai_provider_credential")
    static let validateGitHubConfigurationSucceeded = DiagnosticsEventName("validate_github_configuration_succeeded")
    static let validateGitHubConfigurationFailed = DiagnosticsEventName("validate_github_configuration_failed")
    static let validateJiraConfigurationSucceeded = DiagnosticsEventName("validate_jira_configuration_succeeded")
    static let validateJiraConfigurationFailed = DiagnosticsEventName("validate_jira_configuration_failed")
}

extension DiagnosticsEventName {
    static let appError = DiagnosticsEvent.appError
    static let sessionStartRequested = DiagnosticsEvent.sessionStartRequested
    static let sessionStartIgnored = DiagnosticsEvent.sessionStartIgnored
    static let sessionStartRejected = DiagnosticsEvent.sessionStartRejected
    static let sessionStartPreflightFailed = DiagnosticsEvent.sessionStartPreflightFailed
    static let sessionStarted = DiagnosticsEvent.sessionStarted
    static let sessionStopRequested = DiagnosticsEvent.sessionStopRequested
    static let sessionStopIgnored = DiagnosticsEvent.sessionStopIgnored
    static let sessionStopRejected = DiagnosticsEvent.sessionStopRejected
    static let transcriptionCompleted = DiagnosticsEvent.transcriptionCompleted
    static let validateAIProviderSucceeded = DiagnosticsEvent.validateAIProviderSucceeded
    static let validateAIProviderFailed = DiagnosticsEvent.validateAIProviderFailed
    static let removeAIProviderCredential = DiagnosticsEvent.removeAIProviderCredential
    static let validateGitHubConfigurationSucceeded = DiagnosticsEvent.validateGitHubConfigurationSucceeded
    static let validateGitHubConfigurationFailed = DiagnosticsEvent.validateGitHubConfigurationFailed
    static let validateJiraConfigurationSucceeded = DiagnosticsEvent.validateJiraConfigurationSucceeded
    static let validateJiraConfigurationFailed = DiagnosticsEvent.validateJiraConfigurationFailed
}
