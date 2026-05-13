using BugNarrator.Windows.Services.Settings;
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
}
