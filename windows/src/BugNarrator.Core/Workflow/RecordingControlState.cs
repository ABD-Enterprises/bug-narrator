using BugNarrator.Core.Models;

namespace BugNarrator.Core.Workflow;

public sealed record RecordingControlState(
    RecordingWorkflowState WorkflowState,
    bool CanStart,
    bool CanStop,
    bool CanCaptureScreenshot,
    string StatusMessage,
    RecordingSessionDraft? ActiveSession
)
{
    public static RecordingControlState Idle(string statusMessage = "Ready to record.")
    {
        return new RecordingControlState(
            RecordingWorkflowState.Idle,
            CanStart: true,
            CanStop: false,
            CanCaptureScreenshot: false,
            statusMessage,
            ActiveSession: null);
    }
}
