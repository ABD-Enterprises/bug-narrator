using BugNarrator.Core.Workflow;

namespace BugNarrator.Windows.Services.Permissions;

public interface IMicrophonePreflightService
{
    RecordingPreflightResult CheckReadyToRecord(bool isAlreadyRecording);
}
