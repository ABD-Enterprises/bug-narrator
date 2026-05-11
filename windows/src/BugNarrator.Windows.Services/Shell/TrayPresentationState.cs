using BugNarrator.Core.Workflow;

namespace BugNarrator.Windows.Services.Shell;

public sealed record TrayPresentationState(
    string StatusLabel,
    string IconText,
    bool CanStartRecording,
    bool CanStopRecording,
    bool CanCaptureScreenshot)
{
    public static TrayPresentationState FromRecordingState(RecordingControlState state)
    {
        var statusLabel = state.WorkflowState switch
        {
            RecordingWorkflowState.Idle => "Status: Ready",
            RecordingWorkflowState.Recording => "Status: Recording",
            RecordingWorkflowState.Stopping => "Status: Stopping",
            RecordingWorkflowState.Saving => "Status: Saving Session",
            RecordingWorkflowState.Completed => "Status: Session Saved",
            RecordingWorkflowState.Failed => "Status: Needs Attention",
            _ => "Status: BugNarrator"
        };

        var iconText = $"BugNarrator - {statusLabel["Status: ".Length..]}";
        if (iconText.Length > 63)
        {
            iconText = iconText[..63];
        }

        return new TrayPresentationState(
            statusLabel,
            iconText,
            state.CanStart,
            state.CanStop,
            state.CanCaptureScreenshot);
    }
}
