using BugNarrator.Core.Models;
using BugNarrator.Core.Workflow;
using BugNarrator.Windows.Services.Audio;
using BugNarrator.Windows.Services.Capture;
using BugNarrator.Windows.Services.Diagnostics;
using BugNarrator.Windows.Services.Permissions;
using BugNarrator.Windows.Services.Secrets;
using BugNarrator.Windows.Services.Settings;
using BugNarrator.Windows.Services.Storage;
using BugNarrator.Windows.Services.Transcription;
using Xunit;

namespace BugNarrator.Windows.Tests;

public sealed class RecordingLifecycleServiceScreenshotTests
{
    [Fact]
    public async Task CaptureScreenshotAsync_WithoutActiveRecording_ReturnsNoActiveSession()
    {
        using var harness = new TestHarness();

        var result = await harness.Service.CaptureScreenshotAsync();

        Assert.Equal(ScreenshotCaptureResultStatus.NoActiveSession, result.Status);
        Assert.Equal("Start a recording before capturing a screenshot.", result.Message);
        Assert.Equal(0, harness.OverlayService.CallCount);
        Assert.Equal(0, harness.ImageCaptureService.CallCount);
    }

    [Fact]
    public async Task CaptureScreenshotAsync_WhenPreflightFails_ReturnsUnavailableWithoutShowingOverlay()
    {
        using var harness = new TestHarness();
        await harness.StartRecordingAsync();
        harness.ScreenCapturePreflightService.Result = new ScreenCapturePreflightResult(
            ScreenCapturePreflightStatus.Unavailable,
            CanCapture: false,
            "Screen capture unavailable.");

        var result = await harness.Service.CaptureScreenshotAsync();

        Assert.Equal(ScreenshotCaptureResultStatus.Unavailable, result.Status);
        Assert.Equal("Screen capture unavailable.", result.Message);
        Assert.Equal(0, harness.OverlayService.CallCount);
        Assert.Equal(0, harness.ImageCaptureService.CallCount);
        Assert.Equal(RecordingWorkflowState.Recording, harness.Service.CurrentState.WorkflowState);
    }

    [Fact]
    public async Task CaptureScreenshotAsync_WhenSelectionIsCancelled_KeepsRecordingActive()
    {
        using var harness = new TestHarness();
        await harness.StartRecordingAsync();
        harness.OverlayService.Result = new ScreenshotSelectionResult(
            ScreenshotSelectionStatus.Cancelled,
            Selection: null);

        var result = await harness.Service.CaptureScreenshotAsync();

        Assert.Equal(ScreenshotCaptureResultStatus.Cancelled, result.Status);
        Assert.Equal("Screenshot capture cancelled.", result.Message);
        Assert.Equal(1, harness.OverlayService.CallCount);
        Assert.Equal(0, harness.ImageCaptureService.CallCount);
        Assert.Equal(RecordingWorkflowState.Recording, harness.Service.CurrentState.WorkflowState);
        Assert.True(harness.Service.CurrentState.CanCaptureScreenshot);
    }

    [Fact]
    public async Task CaptureScreenshotAsync_WhenCaptureSucceeds_PersistsScreenshotAndTimelineMoment()
    {
        using var harness = new TestHarness();
        await harness.StartRecordingAsync();
        harness.OverlayService.Result = new ScreenshotSelectionResult(
            ScreenshotSelectionStatus.Selected,
            new ScreenshotSelection(X: 10, Y: 20, Width: 320, Height: 180));

        var result = await harness.Service.CaptureScreenshotAsync();

        var screenshot = Assert.IsType<ScreenshotArtifact>(result.Screenshot);
        var savedDraft = Assert.IsType<RecordingSessionDraft>(harness.SessionDraftStore.LastSavedDraft);

        Assert.Equal(ScreenshotCaptureResultStatus.Captured, result.Status);
        Assert.Equal("screenshots/screenshot-001.png", screenshot.RelativePath);
        Assert.Equal(1, harness.OverlayService.CallCount);
        Assert.Equal(1, harness.ImageCaptureService.CallCount);
        Assert.Equal(screenshot.AbsolutePath, harness.ImageCaptureService.LastDestinationPath);
        Assert.True(File.Exists(harness.ImageCaptureService.LastDestinationPath));
        Assert.Single(savedDraft.Screenshots);
        Assert.Single(savedDraft.TimelineMoments);
        Assert.Equal(savedDraft.Screenshots[0].ScreenshotId, savedDraft.TimelineMoments[0].RelatedScreenshotId);
        Assert.Equal(RecordingWorkflowState.Recording, harness.Service.CurrentState.WorkflowState);
        Assert.True(harness.Service.CurrentState.CanCaptureScreenshot);
    }

    [Fact]
    public async Task CaptureScreenshotAsync_WhenImageCaptureFails_KeepsRecordingActive()
    {
        using var harness = new TestHarness();
        await harness.StartRecordingAsync();
        harness.OverlayService.Result = new ScreenshotSelectionResult(
            ScreenshotSelectionStatus.Selected,
            new ScreenshotSelection(X: 10, Y: 20, Width: 320, Height: 180));
        harness.ImageCaptureService.ExceptionToThrow = new IOException("boom");

        var result = await harness.Service.CaptureScreenshotAsync();

        var lastSavedDraft = Assert.IsType<RecordingSessionDraft>(harness.SessionDraftStore.LastSavedDraft);

        Assert.Equal(ScreenshotCaptureResultStatus.Failed, result.Status);
        Assert.Equal("Screenshot capture failed: boom", result.Message);
        Assert.Empty(lastSavedDraft.Screenshots);
        Assert.Empty(lastSavedDraft.TimelineMoments);
        Assert.Equal(RecordingWorkflowState.Recording, harness.Service.CurrentState.WorkflowState);
        Assert.True(harness.Service.CurrentState.CanCaptureScreenshot);
    }

    private sealed class TestHarness : IDisposable
    {
        private readonly string rootDirectory;

        public TestHarness()
        {
            rootDirectory = Path.Combine(
                Path.GetTempPath(),
                "BugNarrator.Windows.Tests",
                Guid.NewGuid().ToString("N"));

            var storagePaths = new AppStoragePaths(
                RootDirectory: rootDirectory,
                SessionsDirectory: Path.Combine(rootDirectory, "Sessions"),
                LogsDirectory: Path.Combine(rootDirectory, "Logs"));
            var diagnostics = new WindowsDiagnostics(storagePaths);

            AudioRecorderService = new FakeAudioRecorderService();
            MicrophonePreflightService = new FakeMicrophonePreflightService();
            ScreenCapturePreflightService = new FakeScreenCapturePreflightService();
            OverlayService = new FakeScreenshotSelectionOverlayService();
            ImageCaptureService = new FakeScreenshotImageCaptureService();
            SessionDraftStore = new FakeSessionDraftStore(storagePaths.SessionsDirectory);
            CompletedSessionStore = new FakeCompletedSessionStore();
            SettingsStore = new FakeWindowsAppSettingsStore();
            SecretStore = new FakeSecretStore();
            TranscriptionClient = new FakeTranscriptionClient();

            Service = new RecordingLifecycleService(
                AudioRecorderService,
                MicrophonePreflightService,
                SessionDraftStore,
                CompletedSessionStore,
                ScreenCapturePreflightService,
                OverlayService,
                ImageCaptureService,
                SettingsStore,
                SecretStore,
                TranscriptionClient,
                diagnostics);
        }

        public FakeAudioRecorderService AudioRecorderService { get; }
        public FakeCompletedSessionStore CompletedSessionStore { get; }
        public FakeScreenshotImageCaptureService ImageCaptureService { get; }
        public FakeMicrophonePreflightService MicrophonePreflightService { get; }
        public FakeScreenshotSelectionOverlayService OverlayService { get; }
        public FakeScreenCapturePreflightService ScreenCapturePreflightService { get; }
        public FakeSecretStore SecretStore { get; }
        public FakeSessionDraftStore SessionDraftStore { get; }
        public FakeWindowsAppSettingsStore SettingsStore { get; }
        public RecordingLifecycleService Service { get; }
        public FakeTranscriptionClient TranscriptionClient { get; }

        public Task StartRecordingAsync()
        {
            return Service.StartRecordingAsync();
        }

        public void Dispose()
        {
            Service.Dispose();

            if (Directory.Exists(rootDirectory))
            {
                Directory.Delete(rootDirectory, recursive: true);
            }
        }
    }

    private sealed class FakeAudioRecorderService : IAudioRecorderService
    {
        public bool IsRecording { get; private set; }

        public void Dispose()
        {
        }

        public Task StartAsync(string audioFilePath, CancellationToken cancellationToken = default)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(audioFilePath)!);
            File.WriteAllText(audioFilePath, string.Empty);
            IsRecording = true;
            return Task.CompletedTask;
        }

        public Task StopAsync(CancellationToken cancellationToken = default)
        {
            IsRecording = false;
            return Task.CompletedTask;
        }
    }

    private sealed class FakeMicrophonePreflightService : IMicrophonePreflightService
    {
        public RecordingPreflightResult Result { get; set; } = new(
            RecordingPreflightStatus.Ready,
            CanStart: true,
            "Microphone ready.");

        public RecordingPreflightResult CheckReadyToRecord(bool isAlreadyRecording)
        {
            return Result;
        }
    }

    private sealed class FakeScreenCapturePreflightService : IScreenCapturePreflightService
    {
        public ScreenCapturePreflightResult Result { get; set; } = new(
            ScreenCapturePreflightStatus.Ready,
            CanCapture: true,
            "Screen capture ready.");

        public ScreenCapturePreflightResult CheckReady()
        {
            return Result;
        }
    }

    private sealed class FakeScreenshotSelectionOverlayService : IScreenshotSelectionOverlayService
    {
        public int CallCount { get; private set; }

        public ScreenshotSelectionResult Result { get; set; } = new(
            ScreenshotSelectionStatus.Selected,
            new ScreenshotSelection(X: 10, Y: 20, Width: 320, Height: 180));

        public Task<ScreenshotSelectionResult> SelectRegionAsync(CancellationToken cancellationToken = default)
        {
            CallCount++;
            return Task.FromResult(Result);
        }
    }

    private sealed class FakeScreenshotImageCaptureService : IScreenshotImageCaptureService
    {
        public int CallCount { get; private set; }
        public string LastDestinationPath { get; private set; } = string.Empty;
        public Exception? ExceptionToThrow { get; set; }

        public Task CaptureAsync(ScreenshotSelection selection, string destinationPath, CancellationToken cancellationToken = default)
        {
            CallCount++;
            LastDestinationPath = destinationPath;

            if (ExceptionToThrow is not null)
            {
                throw ExceptionToThrow;
            }

            Directory.CreateDirectory(Path.GetDirectoryName(destinationPath)!);
            return File.WriteAllTextAsync(destinationPath, "fake screenshot", cancellationToken);
        }
    }

    private sealed class FakeSessionDraftStore : ISessionDraftStore
    {
        private readonly string sessionsDirectory;

        public FakeSessionDraftStore(string sessionsDirectory)
        {
            this.sessionsDirectory = sessionsDirectory;
        }

        public RecordingSessionDraft? LastSavedDraft { get; private set; }

        public Task<RecordingSessionDraft> CreateDraftAsync(DateTimeOffset startedAt, CancellationToken cancellationToken = default)
        {
            var sessionId = Guid.NewGuid();
            var sessionDirectory = Path.Combine(sessionsDirectory, sessionId.ToString("N"));
            var draft = new RecordingSessionDraft(
                SessionId: sessionId,
                Title: $"Session {startedAt:yyyy-MM-dd HH:mm:ss}",
                CreatedAt: startedAt,
                RecordingStartedAt: startedAt,
                RecordingStoppedAt: null,
                SessionDirectory: sessionDirectory,
                AudioFilePath: Path.Combine(sessionDirectory, "session.wav"),
                MetadataFilePath: Path.Combine(sessionDirectory, "session-draft.json"),
                Screenshots: Array.Empty<ScreenshotArtifact>(),
                TimelineMoments: Array.Empty<SessionTimelineMoment>(),
                State: RecordingWorkflowState.Idle,
                FailureMessage: null);

            Directory.CreateDirectory(sessionDirectory);
            LastSavedDraft = draft;
            return Task.FromResult(draft);
        }

        public Task SaveAsync(RecordingSessionDraft draft, CancellationToken cancellationToken = default)
        {
            Directory.CreateDirectory(draft.SessionDirectory);
            LastSavedDraft = draft;
            return Task.CompletedTask;
        }
    }

    private sealed class FakeCompletedSessionStore : ICompletedSessionStore
    {
        public CompletedSession? LastSavedSession { get; private set; }

        public Task<IReadOnlyList<CompletedSession>> GetAllAsync(CancellationToken cancellationToken = default)
        {
            IReadOnlyList<CompletedSession> sessions = LastSavedSession is null
                ? Array.Empty<CompletedSession>()
                : new[] { LastSavedSession };
            return Task.FromResult(sessions);
        }

        public Task SaveAsync(CompletedSession session, CancellationToken cancellationToken = default)
        {
            LastSavedSession = session;
            return Task.CompletedTask;
        }

        public Task DeleteAsync(CompletedSession session, CancellationToken cancellationToken = default)
        {
            if (LastSavedSession?.SessionId == session.SessionId)
            {
                LastSavedSession = null;
            }

            return Task.CompletedTask;
        }
    }

    private sealed class FakeWindowsAppSettingsStore : IWindowsAppSettingsStore
    {
        public WindowsAppSettings Settings { get; set; } = WindowsAppSettings.Default;

        public ValueTask<WindowsAppSettings> LoadAsync(CancellationToken cancellationToken = default)
        {
            return ValueTask.FromResult(Settings);
        }

        public ValueTask SaveAsync(WindowsAppSettings settings, CancellationToken cancellationToken = default)
        {
            Settings = settings;
            return ValueTask.CompletedTask;
        }
    }

    private sealed class FakeSecretStore : ISecretStore
    {
        public string? Value { get; set; }

        public ValueTask<string?> GetAsync(string key, CancellationToken cancellationToken = default)
        {
            return ValueTask.FromResult(Value);
        }

        public ValueTask SetAsync(string key, string value, CancellationToken cancellationToken = default)
        {
            Value = value;
            return ValueTask.CompletedTask;
        }

        public ValueTask RemoveAsync(string key, CancellationToken cancellationToken = default)
        {
            Value = null;
            return ValueTask.CompletedTask;
        }
    }

    private sealed class FakeTranscriptionClient : ITranscriptionClient
    {
        public int CallCount { get; private set; }
        public Exception? ExceptionToThrow { get; set; }
        public string TranscriptText { get; set; } = "Example transcript.";

        public Task<string> TranscribeToTextAsync(
            string audioFilePath,
            string apiKey,
            OpenAiTranscriptionRequest request,
            CancellationToken cancellationToken = default)
        {
            CallCount++;

            if (ExceptionToThrow is not null)
            {
                throw ExceptionToThrow;
            }

            return Task.FromResult(TranscriptText);
        }

        public Task ValidateApiKeyAsync(string apiKey, CancellationToken cancellationToken = default)
        {
            return Task.CompletedTask;
        }
    }
}
