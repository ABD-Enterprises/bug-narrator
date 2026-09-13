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
    private string? provisionalStopText;

    /// <summary>
    /// The text to show for <paramref name="state"/> at <paramref name="now"/>, or an empty string
    /// when nothing should be shown.
    /// </summary>
    public string Text(RecordingControlState state, DateTimeOffset now)
    {
        if (state.WorkflowState == RecordingWorkflowState.Recording && state.ActiveSession is not null)
        {
            recordingStartedAt = state.ActiveSession.RecordingStartedAt;
            provisionalStopText = null;
            cachedText = SessionTimeFormatter.FormatDuration(now - recordingStartedAt.Value);
            return cachedText;
        }

        // Leaving Recording: freeze at the transition, not at the last timer tick, which can be up to
        // a full interval (or more, if the UI thread was busy) behind the real stop. The lifecycle
        // publishes Stopping *before* it stamps RecordingStoppedAt and publishes Saving with it, so
        // the first post-Recording render uses the call time as a provisional stop and the start is
        // kept until a draft arrives carrying the authoritative timestamp, which then replaces it.
        // The start is released once that timestamp is seen or the draft is gone for good.
        if (recordingStartedAt is { } startedAt)
        {
            if (state.ActiveSession?.RecordingStoppedAt is { } stoppedAt)
            {
                cachedText = SessionTimeFormatter.FormatDuration(stoppedAt - startedAt);
                recordingStartedAt = null;
            }
            else if (state.ActiveSession is not null)
            {
                // Stopping with no stamp yet: provisional, keep waiting for the authoritative one.
                cachedText = provisionalStopText ??= SessionTimeFormatter.FormatDuration(now - startedAt);
            }
            else
            {
                // No draft and none coming: the provisional value (or the call time) is final.
                cachedText = provisionalStopText ?? SessionTimeFormatter.FormatDuration(now - startedAt);
                recordingStartedAt = null;
            }

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
