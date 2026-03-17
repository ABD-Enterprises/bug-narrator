using BugNarrator.Core.Workflow;
using NAudio.Wave;

namespace BugNarrator.Windows.Services.Permissions;

public sealed class MicrophonePreflightService : IMicrophonePreflightService
{
    public RecordingPreflightResult CheckReadyToRecord(bool isAlreadyRecording)
    {
        if (isAlreadyRecording)
        {
            return new RecordingPreflightResult(
                RecordingPreflightStatus.AlreadyRecording,
                CanStart: false,
                "A recording session is already active.");
        }

        if (WaveInEvent.DeviceCount <= 0)
        {
            return new RecordingPreflightResult(
                RecordingPreflightStatus.DeviceUnavailable,
                CanStart: false,
                "No microphone device is available.");
        }

        try
        {
            using var probe = new WaveInEvent
            {
                BufferMilliseconds = 125,
                DeviceNumber = 0,
                WaveFormat = new WaveFormat(16000, 16, 1),
            };

            return new RecordingPreflightResult(
                RecordingPreflightStatus.Ready,
                CanStart: true,
                "Microphone ready.");
        }
        catch (UnauthorizedAccessException exception)
        {
            return new RecordingPreflightResult(
                RecordingPreflightStatus.PermissionDenied,
                CanStart: false,
                $"Microphone access is blocked: {exception.Message}");
        }
        catch (Exception exception)
        {
            return new RecordingPreflightResult(
                RecordingPreflightStatus.CaptureSetupFailed,
                CanStart: false,
                $"Microphone capture setup failed: {exception.Message}");
        }
    }
}
