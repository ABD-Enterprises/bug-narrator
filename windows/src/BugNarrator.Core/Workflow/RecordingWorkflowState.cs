namespace BugNarrator.Core.Workflow;

public enum RecordingWorkflowState
{
    Idle,
    Recording,
    Stopping,
    Saving,
    Completed,
    Failed,
}
