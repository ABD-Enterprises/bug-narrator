using System.Text.Json;
using BugNarrator.Windows.Services.Hotkeys;
using BugNarrator.Windows.Services.Storage;

namespace BugNarrator.Windows.Services.Settings;

public sealed class FileWindowsAppSettingsStore : IWindowsAppSettingsStore
{
    private const long MaxSettingsBytes = 256 * 1024;

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = true,
    };

    private readonly string settingsFilePath;

    public FileWindowsAppSettingsStore(AppStoragePaths storagePaths)
    {
        settingsFilePath = storagePaths.SettingsFilePath;
    }

    public async ValueTask<WindowsAppSettings> LoadAsync(CancellationToken cancellationToken = default)
    {
        if (!File.Exists(settingsFilePath))
        {
            return WindowsAppSettings.Default;
        }

        try
        {
            var fileInfo = new FileInfo(settingsFilePath);
            if (fileInfo.Length > MaxSettingsBytes)
            {
                return WindowsAppSettings.Default;
            }

            var json = await File.ReadAllTextAsync(settingsFilePath, cancellationToken);
            return JsonSerializer.Deserialize<WindowsAppSettings>(json, JsonOptions) ?? WindowsAppSettings.Default;
        }
        catch
        {
            return WindowsAppSettings.Default;
        }
    }

    public async ValueTask SaveAsync(WindowsAppSettings settings, CancellationToken cancellationToken = default)
    {
        var normalizedSettings = new WindowsAppSettings(
            settings.EffectiveTranscriptionModel,
            settings.EffectiveLanguageHint ?? string.Empty,
            settings.EffectiveTranscriptionPrompt ?? string.Empty,
            settings.EffectiveIssueExtractionModel,
            settings.NormalizedGitHubRepositoryOwner,
            settings.NormalizedGitHubRepositoryName,
            string.Join(", ", settings.GitHubDefaultLabelsList),
            settings.NormalizedJiraBaseUrl,
            settings.NormalizedJiraProjectKey,
            settings.EffectiveJiraIssueType,
            settings.EffectiveStartRecordingHotkey.Normalize(),
            settings.EffectiveStopRecordingHotkey.Normalize(),
            settings.EffectiveScreenshotHotkey.Normalize());

        var json = JsonSerializer.Serialize(normalizedSettings, JsonOptions);
        await AtomicFileOperations.WriteAllTextAsync(settingsFilePath, json, cancellationToken);
    }
}
