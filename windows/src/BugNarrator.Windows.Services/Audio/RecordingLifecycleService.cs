using BugNarrator.Core.Models;
using BugNarrator.Core.Workflow;
using BugNarrator.Windows.Services.Capture;
using BugNarrator.Windows.Services.Diagnostics;
using BugNarrator.Windows.Services.Permissions;
using BugNarrator.Windows.Services.Secrets;
using BugNarrator.Windows.Services.Settings;
using BugNarrator.Windows.Services.Storage;
using BugNarrator.Windows.Services.Transcription;

namespace BugNarrator.Windows.Services.Audio;

public sealed class RecordingLifecycleService : IRecordingLifecycleService
{
    private readonly IAudioRecorderService audioRecorderService;
    private readonly ICompletedSessionStore completedSessionStore;
    private readonly WindowsDiagnostics diagnostics;
    private readonly IMicrophonePreflightService microphonePreflightService;
    private readonly IScreenCapturePreflightService screenCapturePreflightService;
    private readonly ISecretStore secretStore;
    private readonly ISessionDraftStore sessionDraftStore;
    private readonly IScreenshotImageCaptureService screenshotImageCaptureService;
    private readonly IScreenshotSelectionOverlayService screenshotSelectionOverlayService;
    private readonly IWindowsAppSettingsStore settingsStore;
    private readonly object syncRoot = new();
    private readonly ITranscriptionClient transcriptionClient;

    private RecordingSessionDraft? activeSession;
    private RecordingControlState currentState = RecordingControlState.Idle();

    public RecordingLifecycleService(
        IAudioRecorderService audioRecorderService,
        IMicrophonePreflightService microphonePreflightService,
        ISessionDraftStore sessionDraftStore,
        ICompletedSessionStore completedSessionStore,
        IScreenCapturePreflightService screenCapturePreflightService,
        IScreenshotSelectionOverlayService screenshotSelectionOverlayService,
        IScreenshotImageCaptureService screenshotImageCaptureService,
        IWindowsAppSettingsStore settingsStore,
        ISecretStore secretStore,
        ITranscriptionClient transcriptionClient,
        WindowsDiagnostics diagnostics)
    {
        this.audioRecorderService = audioRecorderService;
        this.microphonePreflightService = microphonePreflightService;
        this.sessionDraftStore = sessionDraftStore;
        this.completedSessionStore = completedSessionStore;
        this.screenCapturePreflightService = screenCapturePreflightService;
        this.screenshotSelectionOverlayService = screenshotSelectionOverlayService;
        this.screenshotImageCaptureService = screenshotImageCaptureService;
        this.settingsStore = settingsStore;
        this.secretStore = secretStore;
        this.transcriptionClient = transcriptionClient;
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

        if (CurrentState.WorkflowState is RecordingWorkflowState.Recording
            or RecordingWorkflowState.Stopping
            or RecordingWorkflowState.Saving)
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

        if (CurrentState.WorkflowState is RecordingWorkflowState.Stopping or RecordingWorkflowState.Saving)
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

            var stoppedDraft = activeSession with
            {
                FailureMessage = null,
                RecordingStoppedAt = DateTimeOffset.UtcNow,
                State = RecordingWorkflowState.Saving,
            };
            activeSession = stoppedDraft;

            await sessionDraftStore.SaveAsync(stoppedDraft, cancellationToken);
            PublishState(new RecordingControlState(
                RecordingWorkflowState.Saving,
                CanStart: false,
                CanStop: false,
                CanCaptureScreenshot: false,
                "Preparing session review...",
                stoppedDraft));

            var completedSession = await BuildCompletedSessionAsync(stoppedDraft, cancellationToken);
            var finalizedDraft = stoppedDraft with
            {
                FailureMessage = completedSession.TranscriptionStatus == SessionTranscriptionStatus.Failed
                    ? completedSession.TranscriptionFailureMessage
                    : null,
                State = RecordingWorkflowState.Completed,
            };

            await sessionDraftStore.SaveAsync(finalizedDraft, cancellationToken);
            await completedSessionStore.SaveAsync(completedSession, cancellationToken);
            activeSession = null;

            diagnostics.Info("recording", $"recording stopped and review session saved: {completedSession.MetadataFilePath}");
            PublishState(new RecordingControlState(
                RecordingWorkflowState.Completed,
                CanStart: true,
                CanStop: false,
                CanCaptureScreenshot: false,
                BuildCompletedStatusMessage(completedSession),
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

    private async Task<CompletedSession> BuildCompletedSessionAsync(
        RecordingSessionDraft draft,
        CancellationToken cancellationToken)
    {
        var settings = await settingsStore.LoadAsync(cancellationToken);
        var request = new OpenAiTranscriptionRequest(
            settings.EffectiveTranscriptionModel,
            settings.EffectiveLanguageHint,
            settings.EffectiveTranscriptionPrompt);
        var apiKey = await secretStore.GetAsync(SecretKeys.OpenAiApiKey, cancellationToken);

        if (string.IsNullOrWhiteSpace(apiKey))
        {
            diagnostics.Warning("transcription", "transcription skipped because the OpenAI API key is not configured");
            return CreateCompletedSession(
                draft,
                request,
                transcriptText: string.Empty,
                transcriptionStatus: SessionTranscriptionStatus.NotConfigured,
                transcriptionFailureMessage: null);
        }

        try
        {
            PublishState(new RecordingControlState(
                RecordingWorkflowState.Saving,
                CanStart: false,
                CanStop: false,
                CanCaptureScreenshot: false,
                "Transcribing session with OpenAI...",
                draft));

            diagnostics.Info("transcription", $"transcription requested using model {request.Model}");
            var transcriptText = await transcriptionClient.TranscribeToTextAsync(
                draft.AudioFilePath,
                apiKey,
                request,
                cancellationToken);

            diagnostics.Info("transcription", "transcription completed");
            return CreateCompletedSession(
                draft,
                request,
                transcriptText,
                SessionTranscriptionStatus.Completed,
                transcriptionFailureMessage: null);
        }
        catch (Exception exception)
        {
            diagnostics.Error("transcription", "transcription failed", exception);
            return CreateCompletedSession(
                draft,
                request,
                transcriptText: string.Empty,
                transcriptionStatus: SessionTranscriptionStatus.Failed,
                transcriptionFailureMessage: exception.Message);
        }
    }

    private static CompletedSession CreateCompletedSession(
        RecordingSessionDraft draft,
        OpenAiTranscriptionRequest request,
        string transcriptText,
        SessionTranscriptionStatus transcriptionStatus,
        string? transcriptionFailureMessage)
    {
        var metadataFilePath = Path.Combine(draft.SessionDirectory, "session.json");
        var transcriptMarkdownFilePath = Path.Combine(draft.SessionDirectory, "transcript.md");
        var stoppedAt = draft.RecordingStoppedAt ?? draft.CreatedAt;
        var reviewSummary = SessionSummaryBuilder.Build(
            transcriptText,
            transcriptionStatus,
            transcriptionFailureMessage,
            draft.Screenshots.Count,
            stoppedAt - draft.RecordingStartedAt);

        return new CompletedSession(
            SessionId: draft.SessionId,
            Title: BuildSessionTitle(draft.Title, transcriptText),
            CreatedAt: draft.CreatedAt,
            RecordingStartedAt: draft.RecordingStartedAt,
            RecordingStoppedAt: stoppedAt,
            SessionDirectory: draft.SessionDirectory,
            AudioFilePath: draft.AudioFilePath,
            MetadataFilePath: metadataFilePath,
            TranscriptMarkdownFilePath: transcriptMarkdownFilePath,
            TranscriptText: transcriptText,
            ReviewSummary: reviewSummary,
            TranscriptionStatus: transcriptionStatus,
            TranscriptionModel: request.Model,
            LanguageHint: request.LanguageHint,
            Prompt: request.Prompt,
            TranscriptionFailureMessage: transcriptionFailureMessage,
            IssueExtraction: null,
            Screenshots: draft.Screenshots.ToArray(),
            TimelineMoments: draft.TimelineMoments.OrderBy(moment => moment.ElapsedSeconds).ToArray());
    }

    private static string BuildCompletedStatusMessage(CompletedSession session)
    {
        return session.TranscriptionStatus switch
        {
            SessionTranscriptionStatus.Completed =>
                $"Recording transcribed and saved to {session.SessionDirectory}",
            SessionTranscriptionStatus.NotConfigured =>
                $"Recording saved to {session.SessionDirectory}. Add an OpenAI API key in Settings to enable transcription.",
            SessionTranscriptionStatus.Failed =>
                $"Recording saved to {session.SessionDirectory}, but transcription failed: {session.TranscriptionFailureMessage}",
            _ => $"Recording saved to {session.SessionDirectory}",
        };
    }

    private static string BuildSessionTitle(string fallbackTitle, string transcriptText)
    {
        if (string.IsNullOrWhiteSpace(transcriptText))
        {
            return fallbackTitle;
        }

        var trimmedTranscript = transcriptText.Trim();
        var sentenceBreak = trimmedTranscript.IndexOfAny(['.', '!', '?', '\r', '\n']);
        var title = sentenceBreak >= 0
            ? trimmedTranscript[..sentenceBreak]
            : trimmedTranscript;

        title = title.Trim();
        if (title.Length == 0)
        {
            return fallbackTitle;
        }

        return title.Length <= 80
            ? title
            : $"{title[..80].Trim()}...";
    }
}
