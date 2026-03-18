using BugNarrator.Core.Models;
using BugNarrator.Windows.Services.Hotkeys;

namespace BugNarrator.Windows.Services.Settings;

public sealed record WindowsAppSettings(
    string TranscriptionModel,
    string LanguageHint,
    string TranscriptionPrompt,
    string IssueExtractionModel,
    string GitHubRepositoryOwner,
    string GitHubRepositoryName,
    string GitHubDefaultLabels,
    string JiraBaseUrl,
    string JiraProjectKey,
    string JiraIssueType,
    WindowsHotkeyShortcut StartRecordingHotkey = default,
    WindowsHotkeyShortcut StopRecordingHotkey = default,
    WindowsHotkeyShortcut ScreenshotHotkey = default)
{
    public static WindowsAppSettings Default { get; } = new(
        TranscriptionModel: "whisper-1",
        LanguageHint: string.Empty,
        TranscriptionPrompt: string.Empty,
        IssueExtractionModel: "gpt-4.1-mini",
        GitHubRepositoryOwner: string.Empty,
        GitHubRepositoryName: string.Empty,
        GitHubDefaultLabels: string.Empty,
        JiraBaseUrl: string.Empty,
        JiraProjectKey: string.Empty,
        JiraIssueType: "Task",
        StartRecordingHotkey: WindowsHotkeyShortcut.NotSet,
        StopRecordingHotkey: WindowsHotkeyShortcut.NotSet,
        ScreenshotHotkey: WindowsHotkeyShortcut.NotSet);

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
        .Split([',', '\n', '\r'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
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
