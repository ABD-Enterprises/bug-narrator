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

public sealed class AudioInputDeviceSelectionTests
{
    [Fact]
    public void Resolve_UsesNamedDeviceWhenAvailable()
    {
        var selection = AudioInputDeviceSelection.Resolve(
            "USB Headset",
            [
                new AudioInputDeviceOption(0, "Built-in Microphone"),
                new AudioInputDeviceOption(1, "USB Headset")
            ]);

        Assert.True(selection.IsResolved);
        Assert.Equal(1, selection.DeviceNumber);
        Assert.Equal("USB Headset", selection.DisplayName);
    }

    [Fact]
    public void Resolve_ReturnsActionableFailureWhenSavedDeviceIsMissing()
    {
        var selection = AudioInputDeviceSelection.Resolve(
            "USB Headset",
            [
                new AudioInputDeviceOption(0, "Built-in Microphone")
            ]);

        Assert.False(selection.IsResolved);
        Assert.Contains("USB Headset", selection.ErrorMessage);
    }

    [Fact]
    public async Task StartRecordingAsync_FailsClearlyWhenSavedDeviceIsUnavailable()
    {
        using var harness = new RecordingHarness();
        harness.SettingsStore.Settings = WindowsAppSettings.Default with
        {
            AudioInputDeviceName = "Missing Microphone"
        };
        harness.AudioInputDeviceCatalog.Devices =
        [
            new AudioInputDeviceOption(0, "Built-in Microphone")
        ];

        await harness.Service.StartRecordingAsync();

        Assert.Equal(RecordingWorkflowState.Failed, harness.Service.CurrentState.WorkflowState);
        Assert.Contains("Missing Microphone", harness.Service.CurrentState.StatusMessage);
        Assert.False(harness.AudioRecorderService.IsRecording);
    }

    [Fact]
    public async Task StartRecordingAsync_WithSystemAudioAndConsent_StartsLoopbackWithoutMicrophone()
    {
        using var harness = new RecordingHarness();
        harness.SettingsStore.Settings = WindowsAppSettings.Default with
        {
            RecordingAudioSource = "systemAudio",
            HasAcceptedSystemAudioRecordingConsent = true,
        };
        harness.AudioInputDeviceCatalog.Devices = [];

        await harness.Service.StartRecordingAsync();

        Assert.Equal(RecordingWorkflowState.Recording, harness.Service.CurrentState.WorkflowState);
        Assert.True(harness.AudioRecorderService.IsRecording);
        Assert.Equal(AudioRecordingSource.SystemAudio, harness.AudioRecorderService.LastRequest?.Source);
        Assert.Null(harness.AudioRecorderService.LastRequest?.MicrophoneDeviceNumber);
        Assert.Equal(0, harness.MicrophonePreflightService.CallCount);
    }

    [Fact]
    public async Task StartRecordingAsync_WithSystemAudioWithoutConsent_FailsBeforeCapture()
    {
        using var harness = new RecordingHarness();
        harness.SettingsStore.Settings = WindowsAppSettings.Default with
        {
            RecordingAudioSource = "systemAudio",
            HasAcceptedSystemAudioRecordingConsent = false,
        };

        await harness.Service.StartRecordingAsync();

        Assert.Equal(RecordingWorkflowState.Failed, harness.Service.CurrentState.WorkflowState);
        Assert.Contains("Accept the system audio recording notice", harness.Service.CurrentState.StatusMessage);
        Assert.False(harness.AudioRecorderService.IsRecording);
    }

    [Fact]
    public async Task StartRecordingAsync_WithMixedAudio_ReportsTrackedLimitation()
    {
        using var harness = new RecordingHarness();
        harness.SettingsStore.Settings = WindowsAppSettings.Default with
        {
            RecordingAudioSource = "microphoneAndSystemAudio",
            HasAcceptedSystemAudioRecordingConsent = true,
        };

        await harness.Service.StartRecordingAsync();

        Assert.Equal(RecordingWorkflowState.Failed, harness.Service.CurrentState.WorkflowState);
        Assert.Contains("Microphone plus system audio recording is not implemented yet", harness.Service.CurrentState.StatusMessage);
        Assert.False(harness.AudioRecorderService.IsRecording);
    }

    private sealed class RecordingHarness : IDisposable
    {
        private readonly string rootDirectory;

        public RecordingHarness()
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
            SessionDraftStore = new FileSessionDraftStore(storagePaths);
            CompletedSessionStore = new FileCompletedSessionStore(storagePaths);
            ScreenCapturePreflightService = new FakeScreenCapturePreflightService();
            OverlayService = new FakeScreenshotSelectionOverlayService();
            ImageCaptureService = new FakeScreenshotImageCaptureService();
            SettingsStore = new FakeWindowsAppSettingsStore();
            SecretStore = new FakeSecretStore();
            TranscriptionClient = new FakeTranscriptionClient();

            Service = new RecordingLifecycleService(
                AudioRecorderService,
                AudioInputDeviceCatalog,
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
        public FakeAudioInputDeviceCatalog AudioInputDeviceCatalog { get; }
        public FileCompletedSessionStore CompletedSessionStore { get; }
        public FakeScreenshotImageCaptureService ImageCaptureService { get; }
        public FakeMicrophonePreflightService MicrophonePreflightService { get; }
        public FakeScreenshotSelectionOverlayService OverlayService { get; }
        public FakeScreenCapturePreflightService ScreenCapturePreflightService { get; }
        public FakeSecretStore SecretStore { get; }
        public FileSessionDraftStore SessionDraftStore { get; }
        public FakeWindowsAppSettingsStore SettingsStore { get; }
        public RecordingLifecycleService Service { get; }
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

        public AudioRecordingRequest? LastRequest { get; private set; }

        public Task StartAsync(string audioFilePath, AudioRecordingRequest request, CancellationToken cancellationToken = default)
        {
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

    private sealed class FakeAudioInputDeviceCatalog : IAudioInputDeviceCatalog
    {
        public IReadOnlyList<AudioInputDeviceOption> Devices { get; set; } = [];

        public IReadOnlyList<AudioInputDeviceOption> GetAvailableInputDevices()
        {
            return Devices;
        }
    }

    private sealed class FakeMicrophonePreflightService : IMicrophonePreflightService
    {
        public int CallCount { get; private set; }

        public RecordingPreflightResult CheckReadyToRecord(bool isAlreadyRecording, int deviceNumber)
        {
            CallCount++;
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
        public ValueTask<string?> GetAsync(string key, CancellationToken cancellationToken = default)
        {
            return ValueTask.FromResult<string?>(null);
        }

        public ValueTask SetAsync(string key, string value, CancellationToken cancellationToken = default)
        {
            return ValueTask.CompletedTask;
        }

        public ValueTask RemoveAsync(string key, CancellationToken cancellationToken = default)
        {
            return ValueTask.CompletedTask;
        }
    }

    private sealed class FakeTranscriptionClient : ITranscriptionClient
    {
        public Task<string> TranscribeToTextAsync(
            string audioFilePath,
            string apiKey,
            OpenAiTranscriptionRequest request,
            CancellationToken cancellationToken = default)
        {
            return Task.FromResult("Example transcript.");
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
