using BugNarrator.Core.Models;
using BugNarrator.Windows.Services.Audio;
using BugNarrator.Windows.Services.Http;
using BugNarrator.Windows.Services.Hotkeys;

namespace BugNarrator.Windows.Services.Settings;

public sealed record WindowsAppSettings(
    string TranscriptionModel,
    string LanguageHint,
    string TranscriptionPrompt,
    string IssueExtractionModel,
    string AiProviderBaseUrl,
    string AudioInputDeviceName,
    string GitHubRepositoryOwner,
    string GitHubRepositoryName,
    string GitHubDefaultLabels,
    string JiraBaseUrl,
    string JiraProjectKey,
    string JiraIssueType,
    WindowsHotkeyShortcut StartRecordingHotkey = default,
    WindowsHotkeyShortcut StopRecordingHotkey = default,
    WindowsHotkeyShortcut ScreenshotHotkey = default,
    string AiProvider = "openAI",
    string RecordingAudioSource = "microphone",
    bool HasAcceptedSystemAudioRecordingConsent = false)
{
    public static WindowsAppSettings Default { get; } = new(
        TranscriptionModel: "whisper-1",
        LanguageHint: string.Empty,
        TranscriptionPrompt: string.Empty,
        IssueExtractionModel: "gpt-4.1-mini",
        AiProviderBaseUrl: string.Empty,
        AudioInputDeviceName: string.Empty,
        GitHubRepositoryOwner: string.Empty,
        GitHubRepositoryName: string.Empty,
        GitHubDefaultLabels: string.Empty,
        JiraBaseUrl: string.Empty,
        JiraProjectKey: string.Empty,
        JiraIssueType: "Task",
        StartRecordingHotkey: WindowsHotkeyShortcut.NotSet,
        StopRecordingHotkey: WindowsHotkeyShortcut.NotSet,
        ScreenshotHotkey: WindowsHotkeyShortcut.NotSet,
        AiProvider: WindowsAiProviderProfile.Default.StorageValue,
        RecordingAudioSource: AudioRecordingSourceProfile.Default.StorageValue,
        HasAcceptedSystemAudioRecordingConsent: false);

    public WindowsAiProviderProfile EffectiveAiProviderProfile =>
        WindowsAiProviderProfile.FromStorageValue(AiProvider);

    public string NormalizedAiProvider =>
        EffectiveAiProviderProfile.StorageValue;

    public AudioRecordingSourceProfile EffectiveRecordingAudioSourceProfile =>
        AudioRecordingSourceProfile.FromStorageValue(RecordingAudioSource);

    public string NormalizedRecordingAudioSource =>
        EffectiveRecordingAudioSourceProfile.StorageValue;

    public string? RecordingAudioSourceCompatibilityIssue
    {
        get
        {
            var source = EffectiveRecordingAudioSourceProfile.Source;

            if (source == AudioRecordingSource.MicrophoneAndSystemAudio)
            {
                return "Microphone plus system audio recording is not implemented yet. Choose Microphone or System Audio for this build.";
            }

            if (EffectiveRecordingAudioSourceProfile.UsesSystemAudio
                && !HasAcceptedSystemAudioRecordingConsent)
            {
                return "Accept the system audio recording notice in Settings before recording system audio.";
            }

            return null;
        }
    }

    public string EffectiveTranscriptionModel =>
        string.IsNullOrWhiteSpace(TranscriptionModel)
            ? Default.TranscriptionModel
            : TranscriptionModel.Trim();

    public string? EffectiveLanguageHint =>
        string.IsNullOrWhiteSpace(LanguageHint)
            ? null
            : LanguageHint.Trim();

    public string? EffectiveTranscriptionPrompt =>
        string.IsNullOrWhiteSpace(TranscriptionPrompt)
            ? null
            : TranscriptionPrompt.Trim();

    public string EffectiveIssueExtractionModel =>
        string.IsNullOrWhiteSpace(IssueExtractionModel)
            ? Default.IssueExtractionModel
            : IssueExtractionModel.Trim();

    public string? EffectiveAiProviderBaseUrl =>
        string.IsNullOrWhiteSpace(AiProviderBaseUrl)
            ? null
            : OpenAiCompatibleEndpoint.NormalizeForStorage(AiProviderBaseUrl);

    public string? AiProviderCompatibilityIssue
    {
        get
        {
            var profile = EffectiveAiProviderProfile;
            var hasBaseUrl = !string.IsNullOrWhiteSpace(AiProviderBaseUrl);

            return profile.Provider switch
            {
                WindowsAiProvider.OpenAI => null,
                WindowsAiProvider.OpenAICompatible when !hasBaseUrl =>
                    "Choose a non-default API base URL for the OpenAI-Compatible provider.",
                WindowsAiProvider.LocalCompatible when !hasBaseUrl =>
                    "Choose your local-compatible base URL before validating or transcribing.",
                WindowsAiProvider.LocalCompatible when EffectiveTranscriptionModel == Default.TranscriptionModel =>
                    "Choose a local transcription model instead of whisper-1 for the Local-Compatible provider.",
                WindowsAiProvider.LocalCompatible when EffectiveIssueExtractionModel == Default.IssueExtractionModel =>
                    "Choose a local issue extraction model instead of gpt-4.1-mini for the Local-Compatible provider.",
                _ => null,
            };
        }
    }

    public string? AiProviderCredentialForWorkflow(string? credential)
    {
        if (AiProviderCompatibilityIssue is not null)
        {
            return null;
        }

        var trimmedCredential = credential?.Trim();
        if (EffectiveAiProviderProfile.RequiresCredential)
        {
            return string.IsNullOrWhiteSpace(trimmedCredential) ? null : trimmedCredential;
        }

        return trimmedCredential ?? string.Empty;
    }

    public string? EffectiveAudioInputDeviceName =>
        string.IsNullOrWhiteSpace(AudioInputDeviceName)
            ? null
            : AudioInputDeviceName.Trim();

    public string NormalizedGitHubRepositoryOwner =>
        string.IsNullOrWhiteSpace(GitHubRepositoryOwner)
            ? string.Empty
            : GitHubRepositoryOwner.Trim();

    public string NormalizedGitHubRepositoryName =>
        string.IsNullOrWhiteSpace(GitHubRepositoryName)
            ? string.Empty
            : GitHubRepositoryName.Trim();

    public IReadOnlyList<string> GitHubDefaultLabelsList =>
        (GitHubDefaultLabels ?? string.Empty)
        .Split(new[] { ',', '\n', '\r' }, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
        .Where(label => !string.IsNullOrWhiteSpace(label))
        .ToArray();

    public string NormalizedJiraBaseUrl =>
        string.IsNullOrWhiteSpace(JiraBaseUrl)
            ? string.Empty
            : JiraBaseUrl.Trim();

    public string NormalizedJiraProjectKey =>
        string.IsNullOrWhiteSpace(JiraProjectKey)
            ? string.Empty
            : JiraProjectKey.Trim();

    public string EffectiveJiraIssueType =>
        string.IsNullOrWhiteSpace(JiraIssueType)
            ? Default.JiraIssueType
            : JiraIssueType.Trim();

    public WindowsHotkeyShortcut EffectiveStartRecordingHotkey =>
        StartRecordingHotkey.Normalize();

    public WindowsHotkeyShortcut EffectiveStopRecordingHotkey =>
        StopRecordingHotkey.Normalize();

    public WindowsHotkeyShortcut EffectiveScreenshotHotkey =>
        ScreenshotHotkey.Normalize();

    public IReadOnlyDictionary<WindowsHotkeyAction, WindowsHotkeyShortcut> GetHotkeyAssignments()
    {
        return new Dictionary<WindowsHotkeyAction, WindowsHotkeyShortcut>
        {
            [WindowsHotkeyAction.StartRecording] = EffectiveStartRecordingHotkey,
            [WindowsHotkeyAction.StopRecording] = EffectiveStopRecordingHotkey,
            [WindowsHotkeyAction.CaptureScreenshot] = EffectiveScreenshotHotkey,
        };
    }

    public GitHubExportConfiguration? CreateGitHubExportConfiguration(string? token)
    {
        var configuration = new GitHubExportConfiguration(
            Token: token?.Trim() ?? string.Empty,
            Owner: NormalizedGitHubRepositoryOwner,
            Repository: NormalizedGitHubRepositoryName,
            Labels: GitHubDefaultLabelsList);

        return configuration.IsComplete ? configuration : null;
    }

    public JiraExportConfiguration? CreateJiraExportConfiguration(string? email, string? apiToken)
    {
        if (!Uri.TryCreate(NormalizedJiraBaseUrl, UriKind.Absolute, out var baseUrl))
        {
            return null;
        }

        var configuration = new JiraExportConfiguration(
            BaseUrl: baseUrl,
            Email: email?.Trim() ?? string.Empty,
            ApiToken: apiToken?.Trim() ?? string.Empty,
            ProjectKey: NormalizedJiraProjectKey,
            IssueType: EffectiveJiraIssueType);

        return configuration.IsComplete ? configuration : null;
    }
}
