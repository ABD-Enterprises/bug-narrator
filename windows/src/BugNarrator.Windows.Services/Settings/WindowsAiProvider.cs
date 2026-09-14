namespace BugNarrator.Windows.Services.Settings;

public enum WindowsAiProvider
{
    OpenAI,
    OpenAICompatible,
    LocalCompatible,
    ParakeetLocal,
}

public sealed record WindowsAiProviderProfile(
    WindowsAiProvider Provider,
    string StorageValue,
    string DisplayName,
    string SetupDescription,
    string BaseUrlPlaceholder,
    string BaseUrlHint,
    string CredentialFieldTitle,
    string ValidationActionTitle,
    string SuccessMessage,
    bool RequiresCredential,
    bool SupportsIssueExtraction = true)
{
    /// <summary>
    /// Default base URL of the local Parakeet transcription server; mirrors
    /// AIProvider.baseURLPlaceholder for .parakeetLocal in the macOS app.
    /// </summary>
    public const string ParakeetLocalBaseUrl = "http://localhost:8422";

    /// <summary>
    /// Mirrors SettingsStore.parakeetTranscriptionModel in the macOS app.
    /// </summary>
    public const string ParakeetTranscriptionModel = "parakeet-tdt-0.6b-v3";

    /// <summary>
    /// Shown wherever issue extraction is refused for a transcription-only provider.
    /// Copy verbatim from AISetupSectionsView.swift in the macOS app.
    /// </summary>
    public const string TranscriptionOnlyGuidance =
        "Local Parakeet handles transcription only. Choose OpenAI or a compatible provider when you want automatic issue extraction.";

    public static IReadOnlyList<WindowsAiProviderProfile> All { get; } =
    [
        new(
            WindowsAiProvider.OpenAI,
            "openAI",
            "OpenAI",
            "Use OpenAI-hosted transcription and issue extraction with your own API key.",
            "https://api.openai.com/v1",
            "Leave blank to use the default OpenAI API endpoint.",
            "OpenAI API Key",
            "Validate Key",
            "OpenAI accepted this key.",
            RequiresCredential: true),
        new(
            WindowsAiProvider.OpenAICompatible,
            "openAICompatible",
            "OpenAI-Compatible",
            "Use an enterprise proxy or hosted provider that exposes OpenAI-compatible endpoints.",
            "https://gateway.example.com/openai",
            "Enter the enterprise or hosted OpenAI-compatible base URL.",
            "Provider API Key",
            "Validate Connection",
            "The OpenAI-compatible provider accepted this configuration.",
            RequiresCredential: true),
        new(
            WindowsAiProvider.LocalCompatible,
            "localCompatible",
            "Local-Compatible",
            "Use a local or self-hosted endpoint such as LM Studio or Ollama when it exposes OpenAI-compatible APIs.",
            "http://localhost:1234/v1",
            "Enter the local-compatible base URL. BugNarrator will not assume api.openai.com for this provider.",
            "Provider API Key (Optional)",
            "Validate Connection",
            "The local-compatible provider accepted this configuration.",
            RequiresCredential: false),
        new(
            WindowsAiProvider.ParakeetLocal,
            "parakeetLocal",
            "Local (Parakeet)",
            "Transcribe locally on this PC using Parakeet. No API key, no upload, fully offline after setup.",
            ParakeetLocalBaseUrl,
            "BugNarrator connects to the local Parakeet transcription server on this port.",
            string.Empty,
            "Check Server",
            "The local Parakeet transcription server is running.",
            RequiresCredential: false,
            SupportsIssueExtraction: false),
    ];

    public static WindowsAiProviderProfile Default => All[0];

    public static WindowsAiProviderProfile FromStorageValue(string? value)
    {
        return All.FirstOrDefault(profile =>
            string.Equals(profile.StorageValue, value, StringComparison.OrdinalIgnoreCase))
            ?? Default;
    }

    public static WindowsAiProviderProfile FromProvider(WindowsAiProvider provider)
    {
        return All.FirstOrDefault(profile => profile.Provider == provider) ?? Default;
    }

    public override string ToString()
    {
        return DisplayName;
    }
}
