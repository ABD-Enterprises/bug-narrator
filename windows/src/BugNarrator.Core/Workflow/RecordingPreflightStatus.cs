namespace BugNarrator.Core.Workflow;

public enum RecordingPreflightStatus
{
    Ready,
    AlreadyRecording,
    PermissionDenied,
    DeviceUnavailable,
    CaptureSetupFailed,
}
