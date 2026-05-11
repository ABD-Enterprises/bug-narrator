using BugNarrator.Core.Workflow;
using BugNarrator.Windows.Services.Shell;
using Xunit;

namespace BugNarrator.Windows.Tests;

public sealed class TrayPresentationStateTests
{
    [Fact]
    public void FromRecordingState_MapsIdleToStartableTrayState()
    {
        var state = RecordingControlState.Idle();

        var presentation = TrayPresentationState.FromRecordingState(state);

        Assert.Equal("Status: Ready", presentation.StatusLabel);
        Assert.Equal("BugNarrator - Ready", presentation.IconText);
        Assert.True(presentation.CanStartRecording);
        Assert.False(presentation.CanStopRecording);
        Assert.False(presentation.CanCaptureScreenshot);
    }

    [Fact]
    public void FromRecordingState_MapsRecordingToCaptureCapableTrayState()
    {
        var state = new RecordingControlState(
            RecordingWorkflowState.Recording,
            CanStart: false,
            CanStop: true,
            CanCaptureScreenshot: true,
            "Recording is active.",
            ActiveSession: null);

        var presentation = TrayPresentationState.FromRecordingState(state);

        Assert.Equal("Status: Recording", presentation.StatusLabel);
        Assert.Equal("BugNarrator - Recording", presentation.IconText);
        Assert.False(presentation.CanStartRecording);
        Assert.True(presentation.CanStopRecording);
        Assert.True(presentation.CanCaptureScreenshot);
    }

    [Fact]
    public void FromRecordingState_MapsFailuresToAttentionState()
    {
        var state = new RecordingControlState(
            RecordingWorkflowState.Failed,
            CanStart: true,
            CanStop: false,
            CanCaptureScreenshot: false,
            "Microphone is unavailable.",
            ActiveSession: null);

        var presentation = TrayPresentationState.FromRecordingState(state);

        Assert.Equal("Status: Needs Attention", presentation.StatusLabel);
        Assert.Equal("BugNarrator - Needs Attention", presentation.IconText);
        Assert.True(presentation.CanStartRecording);
        Assert.False(presentation.CanStopRecording);
        Assert.False(presentation.CanCaptureScreenshot);
    }
}
