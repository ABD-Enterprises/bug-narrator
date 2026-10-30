using BugNarrator.Windows.Services.Settings;
using Xunit;

namespace BugNarrator.Windows.Tests;

/// <summary>
/// The Windows port used to warn about a plaintext AI provider endpoint and
/// send the request anyway, where the macOS app refuses it. The warning was
/// shown next to the base URL field and nothing consumed it as a gate, so a
/// mistyped scheme put the API key and the transcript text on the wire in the
/// clear (#1285).
///
/// These tests pin the refusal, the surfaces that have to honour it, and the
/// wording the user sees.
/// </summary>
public sealed class WindowsAiProviderPlaintextGateTests
{
    private static WindowsAppSettings RemoteProvider(string baseUrl) => WindowsAppSettings.Default with
    {
        AiProvider = "openAICompatible",
        AiProviderBaseUrl = baseUrl,
    };

    [Fact]
    public void APlaintextRemoteBaseUrlIsRefusedRatherThanWarnedAbout()
    {
        var settings = RemoteProvider("http://api.example.com/v1");

        var issue = settings.AiProviderCompatibilityIssue;

        Assert.NotNull(issue);
        Assert.Contains("api.example.com", issue);
        Assert.Contains("API key and transcript text", issue);
    }

    [Fact]
    public void TheCredentialIsNotHandedOverToAPlaintextRemoteEndpoint()
    {
        var settings = RemoteProvider("http://api.example.com/v1");

        Assert.Null(settings.AiProviderCredentialForWorkflow("sk-secret"));
    }

    [Fact]
    public void TheWarningAndTheGateSayTheSameThing()
    {
        // The field the user is looking at and the gate that refuses the
        // request describe the same host, so they cannot drift apart.
        var settings = RemoteProvider("http://api.example.com/v1");

        Assert.Equal(settings.AiProviderCompatibilityIssue, settings.AiProviderBaseUrlSecurityWarning);
    }

    [Fact]
    public void HttpsAndLocalHttpAreNotRefused()
    {
        Assert.Null(RemoteProvider("https://api.example.com/v1").AiProviderCompatibilityIssue);
        Assert.Null(RemoteProvider("http://localhost:1234/v1").AiProviderCompatibilityIssue);
        Assert.Null(RemoteProvider("http://127.0.0.1:1234/v1").AiProviderCompatibilityIssue);
        Assert.Null(RemoteProvider("http://192.168.1.20:1234/v1").AiProviderCompatibilityIssue);
    }

    [Fact]
    public void AMdnsClaimableNameIsRefusedWithTheReason()
    {
        var settings = RemoteProvider("http://lmstudio:1234/v1");

        var issue = settings.AiProviderCompatibilityIssue;

        Assert.NotNull(issue);
        Assert.Contains("lmstudio", issue);
        Assert.Contains("answered by the network rather than by the app", issue);
    }

    [Fact]
    public void ADotLocalNameIsRefusedWithTheReason()
    {
        var settings = RemoteProvider("http://nas.local:1234/v1");

        var issue = settings.AiProviderCompatibilityIssue;

        Assert.NotNull(issue);
        Assert.Contains("nas.local", issue);
        Assert.Contains("answered by the network rather than by the app", issue);
    }

    [Fact]
    public void AHostTheAppCannotCheckIsRefusedAsSuch()
    {
        // A trailing dot takes the host out of the address form, so the app
        // cannot read it as an address — it is neither remote nor checkable,
        // and the refusal says which one it is.
        var settings = RemoteProvider("http://127.0.0.1.:1234/v1");

        var issue = settings.AiProviderCompatibilityIssue;

        Assert.NotNull(issue);
        Assert.Contains("cannot check as a local address", issue);
    }

    [Fact]
    public void TheLocalParakeetProviderIsExempt()
    {
        // Parakeet ignores the typed base URL and always talks to the
        // transcription server on this machine, so there is nothing to check.
        var settings = WindowsAppSettings.Default with
        {
            AiProvider = "parakeetLocal",
            AiProviderBaseUrl = "http://api.example.com/v1",
        };

        Assert.Null(settings.AiProviderPlaintextEndpointIssue);
        Assert.Null(settings.AiProviderCompatibilityIssue);
    }
}
