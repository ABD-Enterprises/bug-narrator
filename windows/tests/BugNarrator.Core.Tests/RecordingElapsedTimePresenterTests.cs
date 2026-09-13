using BugNarrator.Core.Models;
using BugNarrator.Core.Workflow;
using Xunit;

namespace BugNarrator.Core.Tests;

public sealed class RecordingElapsedTimePresenterTests
{
    private static readonly DateTimeOffset Start = new(2026, 9, 13, 12, 0, 0, TimeSpan.Zero);

    [Fact]
    public void Idle_BeforeAnyRecording_ShowsNothing()
    {
        var presenter = new RecordingElapsedTimePresenter();

        Assert.Equal(string.Empty, presenter.Text(RecordingControlState.Idle(), Start));
        Assert.False(RecordingElapsedTimePresenter.ShouldTick(RecordingControlState.Idle()));
    }

    [Theory]
    [InlineData(0, "00:00")]
    [InlineData(59, "00:59")]
    [InlineData(60, "01:00")]
    [InlineData(3600, "1:00:00")]
    public void Recording_DerivesElapsedFromTheDraftStartInTheMacShape(int seconds, string expected)
    {
        var presenter = new RecordingElapsedTimePresenter();
        var state = State(RecordingWorkflowState.Recording, Start);

        Assert.Equal(expected, presenter.Text(state, Start.AddSeconds(seconds)));
        Assert.True(RecordingElapsedTimePresenter.ShouldTick(state));
    }

    [Fact]
    public void Recording_DoesNotDriftWhenTicksAreMissed()
    {
        var presenter = new RecordingElapsedTimePresenter();
        var state = State(RecordingWorkflowState.Recording, Start);

        presenter.Text(state, Start.AddSeconds(1));
        // A suspended UI thread skips 40 ticks; the next one is still exact because the value is
        // computed from the start timestamp, not accumulated.
        Assert.Equal("00:42", presenter.Text(state, Start.AddSeconds(42)));
    }

    [Theory]
    [InlineData(RecordingWorkflowState.Stopping)]
    [InlineData(RecordingWorkflowState.Saving)]
    [InlineData(RecordingWorkflowState.Completed)]
    [InlineData(RecordingWorkflowState.Failed)]
    [InlineData(RecordingWorkflowState.Idle)]
    public void LeavingRecording_FreezesAtTheTransitionAndStaysFrozenThroughEveryLaterState(RecordingWorkflowState later)
    {
        var presenter = new RecordingElapsedTimePresenter();
        presenter.Text(State(RecordingWorkflowState.Recording, Start), Start.AddSeconds(75));

        // Completed, Failed, and Idle carry no draft — that is exactly why the presenter must cache.
        var laterState = later is RecordingWorkflowState.Stopping or RecordingWorkflowState.Saving
            ? State(later, Start, stoppedAt: Start.AddSeconds(76))
            : RecordingControlState.Idle() with { WorkflowState = later };

        // The transition itself lands at 76 s and freezes there...
        Assert.Equal("01:16", presenter.Text(laterState, Start.AddSeconds(76)));
        // ...and a much later render still shows 76 s, not 500 s.
        Assert.Equal("01:16", presenter.Text(laterState, Start.AddSeconds(500)));
        Assert.False(RecordingElapsedTimePresenter.ShouldTick(laterState));
    }

    [Fact]
    public void StoppingBetweenTicks_FreezesAtTheDraftStopTimestampNotTheLastTick()
    {
        var presenter = new RecordingElapsedTimePresenter();
        presenter.Text(State(RecordingWorkflowState.Recording, Start), Start.AddSeconds(74));

        // The lifecycle stops at 75.9 s, between the 74 s tick and the one that never comes.
        var stopping = State(RecordingWorkflowState.Stopping, Start, stoppedAt: Start.AddSeconds(75.9));
        Assert.Equal("01:15", presenter.Text(stopping, Start.AddSeconds(77)));
    }

    [Fact]
    public void StoppingBetweenTicks_WithoutADraft_FreezesAtTheTransitionTime()
    {
        var presenter = new RecordingElapsedTimePresenter();
        presenter.Text(State(RecordingWorkflowState.Recording, Start), Start.AddSeconds(74));

        // A transition straight to a draft-less state: the call time is the only stop time there is,
        // and it must be used rather than the stale 74 s tick.
        var failed = RecordingControlState.Idle() with { WorkflowState = RecordingWorkflowState.Failed };
        Assert.Equal("01:16", presenter.Text(failed, Start.AddSeconds(76.4)));
        // And it stays frozen there; later calls do not keep counting.
        Assert.Equal("01:16", presenter.Text(failed, Start.AddSeconds(300)));
    }

    [Fact]
    public void StoppingWithoutAStamp_ThenSavingWithOne_AdoptsTheAuthoritativeStop()
    {
        // The real lifecycle order: Stopping is published before RecordingStoppedAt is stamped, and
        // Saving arrives carrying it. The provisional value must yield to the authoritative one.
        var presenter = new RecordingElapsedTimePresenter();
        presenter.Text(State(RecordingWorkflowState.Recording, Start), Start.AddSeconds(74));

        var stopping = State(RecordingWorkflowState.Stopping, Start, stoppedAt: null);
        Assert.Equal("01:17", presenter.Text(stopping, Start.AddSeconds(77.2)));
        // Re-rendering Stopping does not keep counting.
        Assert.Equal("01:17", presenter.Text(stopping, Start.AddSeconds(90)));

        var saving = State(RecordingWorkflowState.Saving, Start, stoppedAt: Start.AddSeconds(75.9));
        Assert.Equal("01:15", presenter.Text(saving, Start.AddSeconds(91)));

        var completed = RecordingControlState.Idle() with { WorkflowState = RecordingWorkflowState.Completed };
        Assert.Equal("01:15", presenter.Text(completed, Start.AddSeconds(400)));
    }

    [Fact]
    public void NextRecording_ResetsAndCountsFromTheNewStart()
    {
        var presenter = new RecordingElapsedTimePresenter();
        presenter.Text(State(RecordingWorkflowState.Recording, Start), Start.AddSeconds(75));
        presenter.Text(RecordingControlState.Idle() with { WorkflowState = RecordingWorkflowState.Completed }, Start.AddSeconds(80));

        var secondStart = Start.AddMinutes(10);
        Assert.Equal("00:03", presenter.Text(State(RecordingWorkflowState.Recording, secondStart), secondStart.AddSeconds(3)));
    }

    private static RecordingControlState State(RecordingWorkflowState workflowState, DateTimeOffset startedAt, DateTimeOffset? stoppedAt = null)
    {
        var draft = new RecordingSessionDraft(
            SessionId: Guid.NewGuid(),
            Title: "Elapsed presenter",
            CreatedAt: startedAt,
            RecordingStartedAt: startedAt,
            RecordingStoppedAt: stoppedAt,
            SessionDirectory: string.Empty,
            AudioFilePath: string.Empty,
            MetadataFilePath: string.Empty,
            Screenshots: [],
            TimelineMoments: [],
            State: workflowState,
            FailureMessage: null);

        return new RecordingControlState(
            workflowState,
            CanStart: false,
            CanStop: workflowState == RecordingWorkflowState.Recording,
            CanCaptureScreenshot: workflowState == RecordingWorkflowState.Recording,
            StatusMessage: workflowState.ToString(),
            ActiveSession: draft);
    }
}
