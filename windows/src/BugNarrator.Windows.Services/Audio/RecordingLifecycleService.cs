using BugNarrator.Core.Models;
using BugNarrator.Core.Workflow;
using BugNarrator.Windows.Services.Capture;
using BugNarrator.Windows.Services.Diagnostics;
using BugNarrator.Windows.Services.Permissions;
using BugNarrator.Windows.Services.Storage;

namespace BugNarrator.Windows.Services.Audio;

public sealed class RecordingLifecycleService : IRecordingLifecycleService
{
    private readonly IAudioRecorderService audioRecorderService;
    private readonly WindowsDiagnostics diagnostics;
    private readonly IMicrophonePreflightService microphonePreflightService;
    private readonly IScreenCapturePreflightService screenCapturePreflightService;
    private readonly ISessionDraftStore sessionDraftStore;
    private readonly IScreenshotImageCaptureService screenshotImageCaptureService;
    private readonly IScreenshotSelectionOverlayService screenshotSelectionOverlayService;
    private readonly object syncRoot = new();

    private RecordingSessionDraft? activeSession;
    private RecordingControlState currentState = RecordingControlState.Idle();

    public RecordingLifecycleService(
        IAudioRecorderService audioRecorderService,
        IMicrophonePreflightService microphonePreflightService,
        ISessionDraftStore sessionDraftStore,
        IScreenCapturePreflightService screenCapturePreflightService,
        IScreenshotSelectionOverlayService screenshotSelectionOverlayService,
        IScreenshotImageCaptureService screenshotImageCaptureService,
        WindowsDiagnostics diagnostics)
    {
        this.audioRecorderService = audioRecorderService;
        this.microphonePreflightService = microphonePreflightService;
        this.sessionDraftStore = sessionDraftStore;
        this.screenCapturePreflightService = screenCapturePreflightService;
        this.screenshotSelectionOverlayService = screenshotSelectionOverlayService;
        this.screenshotImageCaptureService = screenshotImageCaptureService;
        this.diagnostics = diagnostics;
    }

    public RecordingControlState CurrentState
    {
        get
        {
            lock (syncRoot)
            {
                return currentState;
            }
        }
    }

    public event EventHandler<RecordingControlState>? StateChanged;

    public void Dispose()
    {
        if (screenshotSelectionOverlayService is IDisposable disposableOverlay)
        {
            disposableOverlay.Dispose();
        }

        audioRecorderService.Dispose();
    }

    public async Task StartRecordingAsync(CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        diagnostics.Info("recording", "recording start requested");

        if (CurrentState.WorkflowState is RecordingWorkflowState.Recording or RecordingWorkflowState.Stopping)
        {
            diagnostics.Warning("recording", "duplicate start request ignored");
            PublishState(CurrentState with
            {
                StatusMessage = "A recording session is already active.",
            });
            return;
        }

        var preflightResult = microphonePreflightService.CheckReadyToRecord(audioRecorderService.IsRecording);
        diagnostics.Info("recording", $"microphone preflight result: {preflightResult.Status}");

        if (!preflightResult.CanStart)
        {
            PublishState(new RecordingControlState(
                RecordingWorkflowState.Failed,
                CanStart: true,
                CanStop: false,
                CanCaptureScreenshot: false,
                preflightResult.Message,
                ActiveSession: null));
            return;
        }

        var startedAt = DateTimeOffset.UtcNow;
        RecordingSessionDraft? createdDraft = null;

        try
        {
            createdDraft = await sessionDraftStore.CreateDraftAsync(startedAt, cancellationToken);
            activeSession = createdDraft;

            await audioRecorderService.StartAsync(createdDraft.AudioFilePath, cancellationToken);

            var recordingDraft = createdDraft with
            {
                State = RecordingWorkflowState.Recording,
            };
            activeSession = recordingDraft;
            await sessionDraftStore.SaveAsync(recordingDraft, cancellationToken);

            diagnostics.Info("recording", "recording started");
            PublishState(new RecordingControlState(
                RecordingWorkflowState.Recording,
                CanStart: false,
                CanStop: true,
                CanCaptureScreenshot: true,
                $"Recording started. Draft folder: {recordingDraft.SessionDirectory}",
                recordingDraft));
        }
        catch (Exception exception)
        {
            diagnostics.Error("recording", "recording start failed", exception);

            if (createdDraft is not null)
            {
                var failedDraft = createdDraft with
                {
                    FailureMessage = exception.Message,
                    State = RecordingWorkflowState.Failed,
                };
                activeSession = null;
                await sessionDraftStore.SaveAsync(failedDraft, cancellationToken);
            }

            PublishState(new RecordingControlState(
                RecordingWorkflowState.Failed,
                CanStart: true,
                CanStop: false,
                CanCaptureScreenshot: false,
                $"Recording failed: {exception.Message}",
                ActiveSession: null));
        }
    }

    public async Task StopRecordingAsync(CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();

        if (CurrentState.WorkflowState == RecordingWorkflowState.Stopping)
        {
            diagnostics.Warning("recording", "duplicate stop request ignored while already stopping");
            return;
        }

        if (CurrentState.WorkflowState != RecordingWorkflowState.Recording || activeSession is null)
        {
            diagnostics.Warning("recording", "stop requested without an active session");
            PublishState(CurrentState with
            {
                StatusMessage = "No active recording to stop.",
            });
            return;
        }

        diagnostics.Info("recording", "recording stop requested");
        PublishState(new RecordingControlState(
            RecordingWorkflowState.Stopping,
            CanStart: false,
            CanStop: false,
            CanCaptureScreenshot: false,
            "Stopping recording...",
            activeSession));

        try
        {
            await audioRecorderService.StopAsync(cancellationToken);

            var completedDraft = activeSession with
            {
                FailureMessage = null,
                RecordingStoppedAt = DateTimeOffset.UtcNow,
                State = RecordingWorkflowState.Completed,
            };

            await sessionDraftStore.SaveAsync(completedDraft, cancellationToken);
            activeSession = null;

            diagnostics.Info("recording", "recording stopped");
            PublishState(new RecordingControlState(
                RecordingWorkflowState.Completed,
                CanStart: true,
                CanStop: false,
                CanCaptureScreenshot: false,
                $"Recording saved to {completedDraft.SessionDirectory}",
                ActiveSession: null));
        }
        catch (Exception exception)
        {
            diagnostics.Error("recording", "recording stop failed", exception);

            if (activeSession is not null)
            {
                var failedDraft = activeSession with
                {
                    FailureMessage = exception.Message,
                    RecordingStoppedAt = DateTimeOffset.UtcNow,
                    State = RecordingWorkflowState.Failed,
                };

                await sessionDraftStore.SaveAsync(failedDraft, cancellationToken);
            }

            activeSession = null;
            PublishState(new RecordingControlState(
                RecordingWorkflowState.Failed,
                CanStart: true,
                CanStop: false,
                CanCaptureScreenshot: false,
                $"Recording stop failed: {exception.Message}",
                ActiveSession: null));
        }
    }

    public async Task<ScreenshotCaptureResult> CaptureScreenshotAsync(CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        diagnostics.Info("screenshot", "screenshot capture requested");

        RecordingSessionDraft? currentSession;
        lock (syncRoot)
        {
            currentSession = activeSession;
        }

        if (CurrentState.WorkflowState != RecordingWorkflowState.Recording || currentSession is null)
        {
            diagnostics.Warning("screenshot", "capture requested without an active session");
            PublishState(CurrentState with
            {
                StatusMessage = "Start a recording before capturing a screenshot.",
            });
            return new ScreenshotCaptureResult(
                ScreenshotCaptureResultStatus.NoActiveSession,
                "Start a recording before capturing a screenshot.",
                Screenshot: null);
        }

        var preflightResult = screenCapturePreflightService.CheckReady();
        diagnostics.Info("screenshot", $"screen capture preflight result: {preflightResult.Status}");

        if (!preflightResult.CanCapture)
        {
            PublishState(CurrentState with
            {
                StatusMessage = preflightResult.Message,
            });
            return new ScreenshotCaptureResult(
                ScreenshotCaptureResultStatus.Unavailable,
                preflightResult.Message,
                Screenshot: null);
        }

        var selectionResult = await screenshotSelectionOverlayService.SelectRegionAsync(cancellationToken);
        if (selectionResult.Status == ScreenshotSelectionStatus.Cancelled || selectionResult.Selection is null)
        {
            diagnostics.Info("screenshot", "screenshot selection cancelled");
            PublishState(CurrentState with
            {
                StatusMessage = "Screenshot capture cancelled.",
            });
            return new ScreenshotCaptureResult(
                ScreenshotCaptureResultStatus.Cancelled,
                "Screenshot capture cancelled.",
                Screenshot: null);
        }

        try
        {
            var capturedAt = DateTimeOffset.UtcNow;
            var plan = ScreenshotCapturePlanner.CreatePlan(
                currentSession,
                capturedAt,
                selectionResult.Selection.Value.Width,
                selectionResult.Selection.Value.Height);

            await screenshotImageCaptureService.CaptureAsync(
                selectionResult.Selection.Value,
                plan.Screenshot.AbsolutePath,
                cancellationToken);

            RecordingSessionDraft updatedDraft;
            lock (syncRoot)
            {
                var latestSession = activeSession ?? currentSession;
                updatedDraft = latestSession with
                {
                    Screenshots = latestSession.Screenshots.Append(plan.Screenshot).ToArray(),
                    TimelineMoments = latestSession.TimelineMoments.Append(plan.TimelineMoment).ToArray(),
                };
                activeSession = updatedDraft;
            }

            await sessionDraftStore.SaveAsync(updatedDraft, cancellationToken);

            diagnostics.Info("screenshot", $"screenshot captured: {plan.Screenshot.RelativePath}");
            PublishState(CurrentState with
            {
                ActiveSession = updatedDraft,
                StatusMessage = $"Screenshot captured: {plan.Screenshot.RelativePath}",
            });

            return new ScreenshotCaptureResult(
                ScreenshotCaptureResultStatus.Captured,
                $"Screenshot captured: {plan.Screenshot.RelativePath}",
                plan.Screenshot);
        }
        catch (Exception exception)
        {
            diagnostics.Error("screenshot", "screenshot capture failed", exception);
            PublishState(CurrentState with
            {
                StatusMessage = $"Screenshot capture failed: {exception.Message}",
            });

            return new ScreenshotCaptureResult(
                ScreenshotCaptureResultStatus.Failed,
                $"Screenshot capture failed: {exception.Message}",
                Screenshot: null);
        }
    }

    private void PublishState(RecordingControlState nextState)
    {
        lock (syncRoot)
        {
            currentState = nextState;
        }

        StateChanged?.Invoke(this, nextState);
    }
}
