using BugNarrator.Core.Models;

namespace BugNarrator.Core.Workflow;

/// <summary>
/// Decides what the Recording Controls elapsed-time display shows. Pure, so it is testable with a
/// fake clock; the window owns the timer and calls <see cref="Text"/> on each tick.
///
/// Lifecycle: empty until the first recording; live while <see cref="RecordingWorkflowState.Recording"/>;
/// frozen at the value from the moment the state left Recording through Stopping, Saving, Completed,
/// and Failed (the draft is gone by then, so the value has to be cached here); reset by the next
/// Recording. Elapsed is always derived from the draft's start timestamp, never accumulated, so a
/// throttled or suspended UI thread cannot drift it.
/// </summary>
public sealed class RecordingElapsedTimePresenter
{
    private string cachedText = string.Empty;
    private bool wasRecording;

    /// <summary>
    /// The text to show for <paramref name="state"/> at <paramref name="now"/>, or an empty string
    /// when nothing should be shown.
    /// </summary>
    public string Text(RecordingControlState state, DateTimeOffset now)
    {
        if (state.WorkflowState == RecordingWorkflowState.Recording && state.ActiveSession is not null)
        {
            wasRecording = true;
            cachedText = SessionTimeFormatter.FormatDuration(now - state.ActiveSession.RecordingStartedAt);
            return cachedText;
        }

        // Idle before any recording in this presenter's lifetime: nothing to show. Idle *after* one
        // (the app returns to Idle from Completed on the next tick of the lifecycle) keeps the final
        // duration, like every other post-recording state, until the next recording starts.
        return wasRecording ? cachedText : string.Empty;
    }

    /// <summary>True while the window should be ticking; false in every other state.</summary>
    public static bool ShouldTick(RecordingControlState state)
    {
        return state.WorkflowState == RecordingWorkflowState.Recording && state.ActiveSession is not null;
    }
}
