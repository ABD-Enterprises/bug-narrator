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
    private DateTimeOffset? recordingStartedAt;

    /// <summary>
    /// The text to show for <paramref name="state"/> at <paramref name="now"/>, or an empty string
    /// when nothing should be shown.
    /// </summary>
    public string Text(RecordingControlState state, DateTimeOffset now)
    {
        if (state.WorkflowState == RecordingWorkflowState.Recording && state.ActiveSession is not null)
        {
            recordingStartedAt = state.ActiveSession.RecordingStartedAt;
            cachedText = SessionTimeFormatter.FormatDuration(now - recordingStartedAt.Value);
            return cachedText;
        }

        // Leaving Recording: freeze at the transition, not at the last timer tick, which can be up to
        // a full interval (or more, if the UI thread was busy) behind the real stop. The draft carries
        // the authoritative RecordingStoppedAt while it still exists (Stopping, Saving); when the
        // transition lands directly in a draft-less state, the call time is the best available.
        if (recordingStartedAt is { } startedAt)
        {
            var stoppedAt = state.ActiveSession?.RecordingStoppedAt ?? now;
            cachedText = SessionTimeFormatter.FormatDuration(stoppedAt - startedAt);
            recordingStartedAt = null;
            return cachedText;
        }

        // Idle before any recording in this presenter's lifetime: nothing to show. Every later state
        // keeps the frozen final duration until the next recording starts.
        return cachedText;
    }

    /// <summary>True while the window should be ticking; false in every other state.</summary>
    public static bool ShouldTick(RecordingControlState state)
    {
        return state.WorkflowState == RecordingWorkflowState.Recording && state.ActiveSession is not null;
    }
}
