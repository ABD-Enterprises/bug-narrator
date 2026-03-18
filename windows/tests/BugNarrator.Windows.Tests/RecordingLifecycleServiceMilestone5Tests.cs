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

public sealed class RecordingLifecycleServiceMilestone5Tests
{
    [Fact]
    public async Task StopRecordingAsync_WithConfiguredApiKey_TranscribesAndPersistsCompletedSession()
    {
        using var harness = new TestHarness();
        harness.SecretStore.Value = "sk-test";
        harness.TranscriptionClient.TranscriptText = "Tester opens Settings and validates the OpenAI API key.";

        await harness.Service.StartRecordingAsync();
        await harness.Service.StopRecordingAsync();

        var sessions = await harness.CompletedSessionStore.GetAllAsync();
        var session = Assert.Single(sessions);

        Assert.Equal(SessionTranscriptionStatus.Completed, session.TranscriptionStatus);
        Assert.Equal("Tester opens Settings and validates the OpenAI API key.", session.TranscriptText);
        Assert.Equal(1, harness.TranscriptionClient.CallCount);
        Assert.Equal(RecordingWorkflowState.Completed, harness.Service.CurrentState.WorkflowState);
        Assert.True(harness.Service.CurrentState.CanStart);
        Assert.True(File.Exists(session.MetadataFilePath));
        Assert.True(File.Exists(session.TranscriptMarkdownFilePath));

        var transcriptMarkdown = await File.ReadAllTextAsync(session.TranscriptMarkdownFilePath);
        Assert.Contains("## Transcript", transcriptMarkdown);
        Assert.Contains("Tester opens Settings and validates the OpenAI API key.", transcriptMarkdown);
    }

    [Fact]
    public async Task StopRecordingAsync_WithoutApiKey_SavesSessionAsNotConfigured()
    {
        using var harness = new TestHarness();

        await harness.Service.StartRecordingAsync();
        await harness.Service.StopRecordingAsync();

        var sessions = await harness.CompletedSessionStore.GetAllAsync();
        var session = Assert.Single(sessions);

        Assert.Equal(SessionTranscriptionStatus.NotConfigured, session.TranscriptionStatus);
        Assert.Equal(string.Empty, session.TranscriptText);
        Assert.Equal(0, harness.TranscriptionClient.CallCount);
        Assert.Equal(RecordingWorkflowState.Completed, harness.Service.CurrentState.WorkflowState);
        Assert.Contains("Add an OpenAI API key", harness.Service.CurrentState.StatusMessage);
        Assert.True(File.Exists(session.TranscriptMarkdownFilePath));
    }

    [Fact]
    public async Task StopRecordingAsync_WhenTranscriptionFails_PersistsFailureWithoutBreakingLifecycle()
    {
        using var harness = new TestHarness();
        harness.SecretStore.Value = "sk-test";
        harness.TranscriptionClient.ExceptionToThrow = new InvalidOperationException("boom");

        await harness.Service.StartRecordingAsync();
        await harness.Service.StopRecordingAsync();

        var sessions = await harness.CompletedSessionStore.GetAllAsync();
        var session = Assert.Single(sessions);

        Assert.Equal(SessionTranscriptionStatus.Failed, session.TranscriptionStatus);
        Assert.Equal("boom", session.TranscriptionFailureMessage);
        Assert.Equal(1, harness.TranscriptionClient.CallCount);
        Assert.Equal(RecordingWorkflowState.Completed, harness.Service.CurrentState.WorkflowState);
        Assert.Contains("boom", harness.Service.CurrentState.StatusMessage);

        var transcriptMarkdown = await File.ReadAllTextAsync(session.TranscriptMarkdownFilePath);
        Assert.Contains("Transcription Note: boom", transcriptMarkdown);
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
            DraftStore = new FileSessionDraftStore(storagePaths);
            CompletedSessionStore = new FileCompletedSessionStore(storagePaths);
            SettingsStore = new FakeWindowsAppSettingsStore();
            SecretStore = new FakeSecretStore();
            TranscriptionClient = new FakeTranscriptionClient();

            Service = new RecordingLifecycleService(
                AudioRecorderService,
                MicrophonePreflightService,
                DraftStore,
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
        public FileCompletedSessionStore CompletedSessionStore { get; }
        public FileSessionDraftStore DraftStore { get; }
        public FakeScreenshotImageCaptureService ImageCaptureService { get; }
        public FakeMicrophonePreflightService MicrophonePreflightService { get; }
        public FakeScreenshotSelectionOverlayService OverlayService { get; }
        public FakeScreenCapturePreflightService ScreenCapturePreflightService { get; }
        public FakeSecretStore SecretStore { get; }
        public RecordingLifecycleService Service { get; }
        public FakeWindowsAppSettingsStore SettingsStore { get; }
        public FakeTranscriptionClient TranscriptionClient { get; }

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
            File.WriteAllText(audioFilePath, "fake audio");
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
        public RecordingPreflightResult CheckReadyToRecord(bool isAlreadyRecording)
        {
            return new RecordingPreflightResult(
                RecordingPreflightStatus.Ready,
                CanStart: true,
                "Microphone ready.");
        }
    }

    private sealed class FakeScreenCapturePreflightService : IScreenCapturePreflightService
    {
        public ScreenCapturePreflightResult CheckReady()
        {
            return new ScreenCapturePreflightResult(
                ScreenCapturePreflightStatus.Ready,
                CanCapture: true,
                "Screen capture ready.");
        }
    }

    private sealed class FakeScreenshotSelectionOverlayService : IScreenshotSelectionOverlayService
    {
        public Task<ScreenshotSelectionResult> SelectRegionAsync(CancellationToken cancellationToken = default)
        {
            return Task.FromResult(new ScreenshotSelectionResult(
                ScreenshotSelectionStatus.Cancelled,
                Selection: null));
        }
    }

    private sealed class FakeScreenshotImageCaptureService : IScreenshotImageCaptureService
    {
        public Task CaptureAsync(ScreenshotSelection selection, string destinationPath, CancellationToken cancellationToken = default)
        {
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
