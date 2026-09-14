using BugNarrator.Windows.Services.Settings;
using System.Runtime.CompilerServices;
using Xunit;

namespace BugNarrator.Windows.Tests;

public sealed class WindowsAiProviderSettingsTests
{
    [Fact]
    public void DefaultSettings_UseOpenAiProvider()
    {
        var settings = WindowsAppSettings.Default;

        Assert.Equal("openAI", settings.NormalizedAiProvider);
        Assert.Equal("OpenAI", settings.EffectiveAiProviderProfile.DisplayName);
        Assert.Null(settings.AiProviderCompatibilityIssue);
    }

    [Fact]
    public void OpenAiCompatibleProvider_RequiresNonDefaultBaseUrl()
    {
        var settings = WindowsAppSettings.Default with
        {
            AiProvider = "openAICompatible",
            AiProviderBaseUrl = string.Empty,
        };

        Assert.Equal(
            "Choose a non-default API base URL for the OpenAI-Compatible provider.",
            settings.AiProviderCompatibilityIssue);
        Assert.Null(settings.AiProviderCredentialForWorkflow("provider-key"));
    }

    [Fact]
    public void LocalCompatibleProvider_RequiresBaseUrlAndLocalModels()
    {
        var missingBaseUrl = WindowsAppSettings.Default with
        {
            AiProvider = "localCompatible",
        };
        var defaultTranscriptionModel = missingBaseUrl with
        {
            AiProviderBaseUrl = "http://localhost:1234/v1",
        };
        var defaultIssueModel = defaultTranscriptionModel with
        {
            TranscriptionModel = "whisper-large-v3",
        };

        Assert.Equal(
            "Choose your local-compatible base URL before validating or transcribing.",
            missingBaseUrl.AiProviderCompatibilityIssue);
        Assert.Equal(
            "Choose a local transcription model instead of whisper-1 for the Local-Compatible provider.",
            defaultTranscriptionModel.AiProviderCompatibilityIssue);
        Assert.Equal(
            "Choose a local issue extraction model instead of gpt-4.1-mini for the Local-Compatible provider.",
            defaultIssueModel.AiProviderCompatibilityIssue);
    }

    [Fact]
    public void LocalCompatibleProvider_AllowsMissingCredentialWhenCompatible()
    {
        var settings = WindowsAppSettings.Default with
        {
            AiProvider = "localCompatible",
            AiProviderBaseUrl = "http://localhost:1234/v1",
            TranscriptionModel = "whisper-large-v3",
            IssueExtractionModel = "local-qwen",
        };

        Assert.Null(settings.AiProviderCompatibilityIssue);
        Assert.Equal(string.Empty, settings.AiProviderCredentialForWorkflow(null));
    }

    [Fact]
    public void ParakeetLocalProfile_IsTranscriptionOnlyWithNoKeyOnPort8422()
    {
        var profile = WindowsAiProviderProfile.FromStorageValue("parakeetLocal");

        Assert.Equal(WindowsAiProvider.ParakeetLocal, profile.Provider);
        Assert.Equal("Local (Parakeet)", profile.DisplayName);
        Assert.Equal("http://localhost:8422", profile.BaseUrlPlaceholder);
        Assert.False(profile.RequiresCredential);
        Assert.False(profile.SupportsIssueExtraction);
        Assert.All(
            WindowsAiProviderProfile.All.Where(candidate => candidate.Provider != WindowsAiProvider.ParakeetLocal),
            candidate => Assert.True(candidate.SupportsIssueExtraction));
    }

    [Fact]
    public void ParakeetLocalProfile_MatchesTheMacProviderEnum()
    {
        // The storage value, display name, base URL, model, and guidance sentence are read from
        // the Swift sources so the two apps cannot drift apart silently.
        var providerSwift = File.ReadAllText(SwiftPath("Services", "AIProvider.swift"));
        var modelsSwift = File.ReadAllText(SwiftPath("Services", "SettingsStore+Models.swift"));
        var setupSwift = File.ReadAllText(SwiftPath("Views", "AISetupSectionsView.swift"));
        var profile = WindowsAiProviderProfile.FromProvider(WindowsAiProvider.ParakeetLocal);

        Assert.Contains($"case {profile.StorageValue}", providerSwift, StringComparison.Ordinal);
        Assert.Contains($"return \"{profile.DisplayName}\"", providerSwift, StringComparison.Ordinal);
        Assert.Contains($"return \"{profile.BaseUrlPlaceholder}\"", providerSwift, StringComparison.Ordinal);
        Assert.Contains($"return \"{profile.ValidationActionTitle}\"", providerSwift, StringComparison.Ordinal);
        Assert.Contains($"return \"{profile.SuccessMessage}\"", providerSwift, StringComparison.Ordinal);
        Assert.Contains(
            $"static let parakeetTranscriptionModel = \"{WindowsAiProviderProfile.ParakeetTranscriptionModel}\"",
            modelsSwift,
            StringComparison.Ordinal);
        Assert.Contains($"\"{WindowsAiProviderProfile.TranscriptionOnlyGuidance}\"", setupSwift, StringComparison.Ordinal);
    }

    [Fact]
    public void ParakeetLocalSettings_TranscribeButRefuseIssueExtraction()
    {
        var settings = WindowsAppSettings.Default with
        {
            AiProvider = "parakeetLocal",
            AiProviderBaseUrl = string.Empty,
            TranscriptionModel = "whisper-1",
        };

        // Transcription is allowed with no key and the pinned Parakeet model/URL.
        Assert.Null(settings.AiProviderCompatibilityIssue);
        Assert.Equal(string.Empty, settings.AiProviderCredentialForWorkflow(null));
        Assert.Equal("parakeet-tdt-0.6b-v3", settings.EffectiveTranscriptionModel);
        Assert.Equal("http://localhost:8422", settings.EffectiveAiProviderBaseUrl);
        // A base URL left over from a previously selected provider never redirects Parakeet.
        Assert.Equal(
            "http://localhost:8422",
            (settings with { AiProviderBaseUrl = "https://gateway.example.com/openai" }).EffectiveAiProviderBaseUrl);

        // Extraction is refused with the macOS guidance, even when a key happens to be saved.
        Assert.False(settings.SupportsIssueExtraction);
        Assert.Equal(WindowsAiProviderProfile.TranscriptionOnlyGuidance, settings.IssueExtractionUnavailableReason);
        Assert.Equal(WindowsAiProviderProfile.TranscriptionOnlyGuidance, settings.IssueExtractionCompatibilityIssue);
        Assert.Null(settings.AiProviderCredentialForIssueExtraction("sk-test"));
    }

    [Theory]
    [InlineData("openAI", "", "whisper-1", "gpt-4.1-mini")]
    [InlineData("openAICompatible", "https://gateway.example.com/openai", "whisper-1", "gpt-4.1-mini")]
    [InlineData("localCompatible", "http://localhost:1234/v1", "whisper-large-v3", "local-qwen")]
    public void ChatCapableProviders_KeepIssueExtractionAvailable(
        string provider, string baseUrl, string transcriptionModel, string issueModel)
    {
        var settings = WindowsAppSettings.Default with
        {
            AiProvider = provider,
            AiProviderBaseUrl = baseUrl,
            TranscriptionModel = transcriptionModel,
            IssueExtractionModel = issueModel,
        };

        Assert.True(settings.SupportsIssueExtraction);
        Assert.Null(settings.IssueExtractionUnavailableReason);
        Assert.Null(settings.IssueExtractionCompatibilityIssue);
        Assert.Equal(
            settings.AiProviderCredentialForWorkflow("sk-test"),
            settings.AiProviderCredentialForIssueExtraction("sk-test"));
    }

    [Fact]
    public void IssueExtractionCompatibilityIssue_FallsBackToTheProviderIssue()
    {
        var settings = WindowsAppSettings.Default with
        {
            AiProvider = "openAICompatible",
            AiProviderBaseUrl = string.Empty,
        };

        Assert.Equal(settings.AiProviderCompatibilityIssue, settings.IssueExtractionCompatibilityIssue);
        Assert.Null(settings.AiProviderCredentialForIssueExtraction("sk-test"));
    }

    private static string SwiftPath(string folder, string file, [CallerFilePath] string sourceFilePath = "")
    {
        // <root>/windows/tests/BugNarrator.Windows.Tests/<this file>
        var root = Path.GetFullPath(Path.Combine(Path.GetDirectoryName(sourceFilePath)!, "..", "..", ".."));
        var path = Path.Combine(root, "Sources", "BugNarrator", folder, file);
        Assert.True(File.Exists(path), $"Missing macOS source at {path}.");
        return path;
    }
}
