namespace BugNarrator.Core.Workflow;

/// <summary>What kind of thing is stopping progress, so the tray can word and route a Fix entry.</summary>
public enum RecoveryBlockerCategory
{
    Permission,
    Credential,
    Storage,
    Other,
}

/// <summary>Where the app can take the user to resolve a blocker. None means the guidance is all there is.</summary>
public enum RecoveryDestination
{
    None,
    Settings,
    RecordingControls,
    SessionLibrary,
}

/// <summary>
/// Structured recovery guidance carried on <see cref="RecordingControlState"/> when a permission,
/// credential, storage, or other blocker has stopped progress (product-spec compact launch surface;
/// the macOS setup banner and status area play this role). The free-form StatusMessage stays the
/// human explanation; this is what lets the tray offer a Fix entry that opens the right place.
/// </summary>
public sealed record RecoveryBlocker(
    RecoveryBlockerCategory Category,
    string Guidance,
    RecoveryDestination Destination)
{
    /// <summary>Maps a failed microphone preflight to its blocker; null for Ready.</summary>
    public static RecoveryBlocker? FromPreflight(RecordingPreflightStatus status) => status switch
    {
        RecordingPreflightStatus.PermissionDenied => new(
            RecoveryBlockerCategory.Permission,
            "Allow microphone access for desktop apps in Windows Settings > Privacy & security > Microphone, then check the input device in Settings.",
            RecoveryDestination.Settings),
        RecordingPreflightStatus.DeviceUnavailable => new(
            RecoveryBlockerCategory.Other,
            "Connect a microphone or choose a different input device in Settings.",
            RecoveryDestination.Settings),
        RecordingPreflightStatus.CaptureSetupFailed => new(
            RecoveryBlockerCategory.Other,
            "Choose a different input device in Settings, or check that no other app holds the microphone.",
            RecoveryDestination.Settings),
        RecordingPreflightStatus.AlreadyRecording => new(
            RecoveryBlockerCategory.Other,
            "Stop the active recording from the recording controls before starting another.",
            RecoveryDestination.RecordingControls),
        _ => null,
    };

    /// <summary>
    /// Classifies a start/stop exception: file-system failures are Storage (the session directory
    /// could not be written), everything else is Other with the recording controls as the retry point.
    /// </summary>
    public static RecoveryBlocker FromException(Exception exception) => exception switch
    {
        IOException or UnauthorizedAccessException => new(
            RecoveryBlockerCategory.Storage,
            "BugNarrator could not write to its sessions folder. Free up disk space or check the folder's permissions, then try again.",
            RecoveryDestination.RecordingControls),
        _ => new(
            RecoveryBlockerCategory.Other,
            "Try recording again from the recording controls. If it keeps failing, check the diagnostics log.",
            RecoveryDestination.RecordingControls),
    };

    public static RecoveryBlocker ProviderNotConfigured { get; } = new(
        RecoveryBlockerCategory.Credential,
        "Finish AI provider setup in Settings to enable transcription.",
        RecoveryDestination.Settings);

    public static RecoveryBlocker AudioSourceNeedsSettings { get; } = new(
        RecoveryBlockerCategory.Other,
        "Review the recording audio source and its consent in Settings.",
        RecoveryDestination.Settings);

    public static RecoveryBlocker LocalServerUnreachable { get; } = new(
        RecoveryBlockerCategory.Other,
        "Start the local Parakeet transcription server in Settings, or choose another AI provider.",
        RecoveryDestination.Settings);

    public static RecoveryBlocker TranscriptionFailed { get; } = new(
        RecoveryBlockerCategory.Other,
        "The recording is saved. Retry transcription from the session library.",
        RecoveryDestination.SessionLibrary);
}
