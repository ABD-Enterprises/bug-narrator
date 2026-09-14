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
    public async Task StopRecordingAsync_WithAutoExtractOff_NeverCallsExtraction()
    {
        using var harness = new TestHarness();
        harness.SecretStore.Value = "sk-test";

        await harness.Service.StartRecordingAsync();
        await harness.Service.StopRecordingAsync();

        Assert.Equal(0, harness.IssueExtractionService.CallCount);
        Assert.Null(Assert.Single(await harness.CompletedSessionStore.GetAllAsync()).IssueExtraction);
    }

    [Fact]
    public async Task StopRecordingAsync_WithAutoExtractOn_ExtractsOnceAndPersistsTheResult()
    {
        // macOS PostTranscriptionPipelineController.complete with autoExtractIssues on.
        using var harness = new TestHarness();
        harness.SecretStore.Value = "sk-test";
        harness.SettingsStore.Settings = WindowsAppSettings.Default with { AutoExtractIssues = true };
        harness.TranscriptionClient.TranscriptText = "The save button is clipped.";

        await harness.Service.StartRecordingAsync();
        await harness.Service.StopRecordingAsync();

        Assert.Equal(1, harness.IssueExtractionService.CallCount);
        Assert.Equal("The save button is clipped.", harness.IssueExtractionService.LastSession!.TranscriptText);
        var saved = Assert.Single(await harness.CompletedSessionStore.GetAllAsync());
        Assert.NotNull(saved.IssueExtraction);
        Assert.Single(saved.IssueExtraction!.Issues);
        Assert.Equal(RecordingWorkflowState.Completed, harness.Service.CurrentState.WorkflowState);
    }

    [Fact]
    public async Task StopRecordingAsync_WithAutoExtractOn_AFailedExtractionKeepsTheTranscribedSession()
    {
        // macOS postTranscriptionFailure: the transcript is already saved; extraction failing must
        // not fail the recording or lose the session.
        using var harness = new TestHarness();
        harness.SecretStore.Value = "sk-test";
        harness.SettingsStore.Settings = WindowsAppSettings.Default with { AutoExtractIssues = true };
        harness.IssueExtractionService.ExceptionToThrow = new InvalidOperationException("provider rejected the request");

        await harness.Service.StartRecordingAsync();
        await harness.Service.StopRecordingAsync();

        Assert.Equal(1, harness.IssueExtractionService.CallCount);
        var saved = Assert.Single(await harness.CompletedSessionStore.GetAllAsync());
        Assert.Equal(SessionTranscriptionStatus.Completed, saved.TranscriptionStatus);
        Assert.Null(saved.IssueExtraction);
        Assert.Equal(RecordingWorkflowState.Completed, harness.Service.CurrentState.WorkflowState);
    }

    [Fact]
    public async Task StopRecordingAsync_WithAutoExtractOnAndTranscriptionOnlyProvider_TranscribesWithoutExtracting()
    {
        // macOS supportsIssueExtraction is false for Local Parakeet: the transcript is saved and
        // the pipeline stops there, without an extraction request (#1168).
        using var harness = new TestHarness();
        harness.SettingsStore.Settings = WindowsAppSettings.Default with
        {
            AiProvider = "parakeetLocal",
            AutoExtractIssues = true,
        };
        harness.TranscriptionClient.TranscriptText = "The save button is clipped.";

        await harness.Service.StartRecordingAsync();
        await harness.Service.StopRecordingAsync();

        Assert.Equal(0, harness.IssueExtractionService.CallCount);
        var saved = Assert.Single(await harness.CompletedSessionStore.GetAllAsync());
        Assert.Equal(SessionTranscriptionStatus.Completed, saved.TranscriptionStatus);
        Assert.Equal("parakeet-tdt-0.6b-v3", saved.TranscriptionModel);
        Assert.Null(saved.IssueExtraction);
    }

    [Fact]
    public async Task StartRecordingAsync_WithParakeetUnreachable_RefusesBeforeCapturingAudio()
    {
        using var harness = new TestHarness();
        harness.SettingsStore.Settings = WindowsAppSettings.Default with { AiProvider = "parakeetLocal" };
        harness.LocalServerHealthProbe.Reachable = false;

        await harness.Service.StartRecordingAsync();

        var state = harness.Service.CurrentState;
        Assert.Equal(RecordingWorkflowState.Failed, state.WorkflowState);
        Assert.Equal(BugNarrator.Windows.Services.LocalTranscription.LocalServerHealthProbe.UnreachableMessage, state.StatusMessage);
        Assert.Equal(RecoveryDestination.Settings, state.Blocker!.Destination);
        Assert.Equal("http://localhost:8422", harness.LocalServerHealthProbe.LastBaseUrl);
        Assert.Null(harness.MicrophonePreflightService.LastDeviceNumber); // never got as far as the microphone
        Assert.Empty(await harness.CompletedSessionStore.GetAllAsync());
    }

    [Fact]
    public async Task StartRecordingAsync_WithParakeetReachable_Records()
    {
        using var harness = new TestHarness();
        harness.SettingsStore.Settings = WindowsAppSettings.Default with { AiProvider = "parakeetLocal" };

        await harness.Service.StartRecordingAsync();

        Assert.Equal(RecordingWorkflowState.Recording, harness.Service.CurrentState.WorkflowState);
        Assert.Equal(1, harness.LocalServerHealthProbe.Calls);
    }

    [Fact]
    public async Task StartRecordingAsync_WithOpenAi_NeverProbesTheLocalServer()
    {
        using var harness = new TestHarness();
        harness.SecretStore.Value = "sk-test";

        await harness.Service.StartRecordingAsync();

        Assert.Equal(0, harness.LocalServerHealthProbe.Calls);
    }

    [Fact]
    public async Task StartRecordingAsync_WhenMicrophoneAccessIsDenied_PublishesAPermissionBlocker()
    {
        using var harness = new TestHarness();
        harness.MicrophonePreflightService.Result = new RecordingPreflightResult(
            RecordingPreflightStatus.PermissionDenied, CanStart: false, "Microphone access is blocked.");

        await harness.Service.StartRecordingAsync();

        var state = harness.Service.CurrentState;
        Assert.Equal(RecordingWorkflowState.Failed, state.WorkflowState);
        Assert.Equal(RecoveryBlockerCategory.Permission, state.Blocker!.Category);
        Assert.Equal(RecoveryDestination.Settings, state.Blocker.Destination);
    }

    [Fact]
    public async Task StopRecordingAsync_WithoutAProvider_PublishesACredentialBlockerOnTheCompletedState()
    {
        using var harness = new TestHarness();

        await harness.Service.StartRecordingAsync();
        await harness.Service.StopRecordingAsync();

        var state = harness.Service.CurrentState;
        Assert.Equal(RecordingWorkflowState.Completed, state.WorkflowState);
        Assert.Equal(RecoveryBlockerCategory.Credential, state.Blocker!.Category);
        Assert.Equal(RecoveryDestination.Settings, state.Blocker.Destination);
    }

    [Fact]
    public async Task StopRecordingAsync_WithATranscript_PublishesNoBlocker()
    {
        using var harness = new TestHarness();
        harness.SecretStore.Value = "sk-test";
        harness.TranscriptionClient.TranscriptText = "Transcribed.";

        await harness.Service.StartRecordingAsync();
        await harness.Service.StopRecordingAsync();

        Assert.Null(harness.Service.CurrentState.Blocker);
    }

    [Fact]
    public async Task StopRecordingAsync_WithAutoExtractOnButNoProvider_DoesNotExtract()
    {
        using var harness = new TestHarness();
        harness.SettingsStore.Settings = WindowsAppSettings.Default with { AutoExtractIssues = true };
        // No key: transcription is NotConfigured, and there is nothing to extract from.

        await harness.Service.StartRecordingAsync();
        await harness.Service.StopRecordingAsync();

        Assert.Equal(0, harness.IssueExtractionService.CallCount);
        Assert.Equal(SessionTranscriptionStatus.NotConfigured, Assert.Single(await harness.CompletedSessionStore.GetAllAsync()).TranscriptionStatus);
    }

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
        Assert.Contains("## Raw Transcript", transcriptMarkdown);
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
        Assert.Contains("Finish AI provider setup", harness.Service.CurrentState.StatusMessage);
        Assert.True(File.Exists(session.TranscriptMarkdownFilePath));
    }

    [Fact]
    public async Task StopRecordingAsync_WithLocalCompatibleProviderAndNoApiKey_Transcribes()
    {
        using var harness = new TestHarness();
        harness.SettingsStore.Settings = WindowsAppSettings.Default with
        {
            AiProvider = "localCompatible",
            AiProviderBaseUrl = "http://localhost:1234/v1",
            TranscriptionModel = "whisper-large-v3",
            IssueExtractionModel = "local-qwen",
        };
        harness.TranscriptionClient.TranscriptText = "Local provider transcribed this session.";

        await harness.Service.StartRecordingAsync();
        await harness.Service.StopRecordingAsync();

        var sessions = await harness.CompletedSessionStore.GetAllAsync();
        var session = Assert.Single(sessions);

        Assert.Equal(SessionTranscriptionStatus.Completed, session.TranscriptionStatus);
        Assert.Equal("Local provider transcribed this session.", session.TranscriptText);
        Assert.Equal(1, harness.TranscriptionClient.CallCount);
        Assert.Equal(string.Empty, harness.TranscriptionClient.LastApiKey);
        Assert.Equal("http://localhost:1234/v1", harness.TranscriptionClient.LastRequest?.ProviderBaseUrl);
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
            AudioInputDeviceCatalog = new FakeAudioInputDeviceCatalog();
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
                AudioInputDeviceCatalog,
                MicrophonePreflightService,
                DraftStore,
                CompletedSessionStore,
                ScreenCapturePreflightService,
                OverlayService,
                ImageCaptureService,
                SettingsStore,
                SecretStore,
                TranscriptionClient,
                IssueExtractionService,
                diagnostics,
                LocalServerHealthProbe);
        }

        public FakeAudioRecorderService AudioRecorderService { get; }
        public FakeAudioInputDeviceCatalog AudioInputDeviceCatalog { get; }
        public FileCompletedSessionStore CompletedSessionStore { get; }
        public FileSessionDraftStore DraftStore { get; }
        public FakeScreenshotImageCaptureService ImageCaptureService { get; }
        public FakeMicrophonePreflightService MicrophonePreflightService { get; }
        public FakeLocalServerHealthProbe LocalServerHealthProbe { get; } = new();
        public FakeScreenshotSelectionOverlayService OverlayService { get; }
        public FakeScreenCapturePreflightService ScreenCapturePreflightService { get; }
        public FakeSecretStore SecretStore { get; }
        public RecordingLifecycleService Service { get; }
        public FakeWindowsAppSettingsStore SettingsStore { get; }
        public FakeTranscriptionClient TranscriptionClient { get; }
        public TestIssueExtractionService IssueExtractionService { get; } = new();

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

        public AudioRecordingRequest? LastRequest { get; private set; }

        public Task StartAsync(string audioFilePath, AudioRecordingRequest request, CancellationToken cancellationToken = default)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(audioFilePath)!);
            File.WriteAllText(audioFilePath, "fake audio");
            LastRequest = request;
            IsRecording = true;
            return Task.CompletedTask;
        }

        public Task StopAsync(CancellationToken cancellationToken = default)
        {
            IsRecording = false;
            return Task.CompletedTask;
        }
    }

    private sealed class FakeLocalServerHealthProbe : BugNarrator.Windows.Services.LocalTranscription.ILocalServerHealthProbe
    {
        public bool Reachable { get; set; } = true;
        public int Calls { get; private set; }
        public string? LastBaseUrl { get; private set; }

        public Task<bool> IsReachableAsync(string baseUrl, CancellationToken cancellationToken = default)
        {
            Calls++;
            LastBaseUrl = baseUrl;
            return Task.FromResult(Reachable);
        }
    }

    private sealed class FakeMicrophonePreflightService : IMicrophonePreflightService
    {
        public int? LastDeviceNumber { get; private set; }
        public RecordingPreflightResult? Result { get; set; }

        public RecordingPreflightResult CheckReadyToRecord(bool isAlreadyRecording, int deviceNumber)
        {
            LastDeviceNumber = deviceNumber;
            return Result ?? new RecordingPreflightResult(
                RecordingPreflightStatus.Ready,
                CanStart: true,
                "Microphone ready.");
        }
    }

    private sealed class FakeAudioInputDeviceCatalog : IAudioInputDeviceCatalog
    {
        public IReadOnlyList<AudioInputDeviceOption> Devices { get; set; } =
        [
            new AudioInputDeviceOption(0, "Built-in Microphone"),
            new AudioInputDeviceOption(1, "USB Headset")
        ];

        public IReadOnlyList<AudioInputDeviceOption> GetAvailableInputDevices()
        {
            return Devices;
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
        public string? LastApiKey { get; private set; }
        public OpenAiTranscriptionRequest? LastRequest { get; private set; }
        public string TranscriptText { get; set; } = "Example transcript.";

        public Task<string> TranscribeToTextAsync(
            string audioFilePath,
            string apiKey,
            OpenAiTranscriptionRequest request,
            CancellationToken cancellationToken = default)
        {
            CallCount++;
            LastApiKey = apiKey;
            LastRequest = request;

            if (ExceptionToThrow is not null)
            {
                throw ExceptionToThrow;
            }

            return Task.FromResult(TranscriptText);
        }

        public Task ValidateApiKeyAsync(
            string apiKey,
            string? providerBaseUrl = null,
            CancellationToken cancellationToken = default)
        {
            return Task.CompletedTask;
        }
    }
}
