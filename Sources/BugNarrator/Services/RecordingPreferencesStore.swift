import Foundation

/// Owns the `UserDefaults` persistence and the normalization rule for the
/// recording-audio preferences, extracted from `SettingsStore` (#429 slice 1).
///
/// This is a plain value type, **not** an `ObservableObject`: `SettingsStore`
/// remains the observable facade — it keeps the `@Published` audio properties and
/// forwards their persistence and load-time normalization here. The default keys
/// are unchanged from `SettingsStore`, so no migration is required.
///
/// Reads intentionally stay in `SettingsStore` (via its `boolValue`/`stringValue`
/// helpers) so the legacy-defaults-domain migration those perform is preserved;
/// this store owns the writes and the normalization rule.
struct RecordingPreferencesStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    enum Keys {
        static let systemAudioCaptureEnabled = "settings.systemAudioCaptureEnabled"
        static let recordingAudioSource = "settings.recordingAudioSource"
        static let hasAcceptedSystemAudioRecordingConsent = "settings.hasAcceptedSystemAudioRecordingConsent"
        static let suppressSystemAudioExplainer = "settings.suppressSystemAudioExplainer"
    }

    /// A stored system-audio source is invalid while system-audio capture is
    /// disabled; it normalizes to `.microphone`. Callers persist the result when
    /// it differs from the stored value.
    func normalizedRecordingAudioSource(
        _ source: RecordingAudioSource,
        systemAudioCaptureEnabled: Bool
    ) -> RecordingAudioSource {
        (!systemAudioCaptureEnabled && source.usesSystemAudio) ? .microphone : source
    }

    func persist(systemAudioCaptureEnabled: Bool) {
        defaults.set(systemAudioCaptureEnabled, forKey: Keys.systemAudioCaptureEnabled)
    }

    func persist(recordingAudioSource: RecordingAudioSource) {
        defaults.set(recordingAudioSource.rawValue, forKey: Keys.recordingAudioSource)
    }

    func persist(hasAcceptedSystemAudioRecordingConsent: Bool) {
        defaults.set(hasAcceptedSystemAudioRecordingConsent, forKey: Keys.hasAcceptedSystemAudioRecordingConsent)
    }

    func persist(suppressSystemAudioExplainer: Bool) {
        defaults.set(suppressSystemAudioExplainer, forKey: Keys.suppressSystemAudioExplainer)
    }
}
