using BugNarrator.Windows.Services.Diagnostics;
using System.Text;
using Xunit;

namespace BugNarrator.Windows.Tests;

/// <summary>
/// The redactor is what a user reads when a debug bundle does not explain
/// what went wrong, so it has to leave ordinary prose alone. A Basic
/// credential is the base64 of "user:secret", so it is the decoded text that
/// tells a credential from a word.
/// </summary>
public sealed class SensitiveDataRedactorTests
{
    private const string RedactionToken = "[REDACTED]";

    private static string Credential(string plaintext) =>
        Convert.ToBase64String(Encoding.UTF8.GetBytes(plaintext));

    [Theory]
    [InlineData("Basic authentication failed")]
    [InlineData("Basic configuration missing")]
    [InlineData("Basic Only mode")]
    [InlineData("Basic troubleshooting notes")]
    public void ProseAfterBasicIsNotRedacted(string message)
    {
        Assert.Equal(message, SensitiveDataRedactor.Redact(message));
    }

    [Fact]
    public void ABasicCredentialIsRedacted()
    {
        var credential = Credential("agent:secret");

        var redacted = SensitiveDataRedactor.Redact($"Basic {credential}");

        Assert.DoesNotContain(credential, redacted, StringComparison.Ordinal);
        Assert.Contains(RedactionToken, redacted, StringComparison.Ordinal);
    }

    [Fact]
    public void ABasicCredentialWithPaddingIsRedacted()
    {
        // "ab:c" is three bytes, so its base64 carries padding.
        var credential = Credential("ab:c");

        var redacted = SensitiveDataRedactor.Redact($"Basic {credential}");

        Assert.DoesNotContain(credential, redacted, StringComparison.Ordinal);
        Assert.Contains(RedactionToken, redacted, StringComparison.Ordinal);
    }

    [Fact]
    public void ABasicCredentialFollowedByMoreBase64CharactersIsRedacted()
    {
        // A credential is often written next to more of the same alphabet. The
        // whole run is captured and the credential is found inside it.
        var credential = Credential("agent:secret");

        var redacted = SensitiveDataRedactor.Redact($"Basic {credential}XYZ");

        Assert.DoesNotContain(credential, redacted, StringComparison.Ordinal);
        Assert.Contains(RedactionToken, redacted, StringComparison.Ordinal);
    }

    [Fact]
    public void ABasicCredentialInAnAuthorizationHeaderIsRedacted()
    {
        var credential = Credential("agent:secret");

        var redacted = SensitiveDataRedactor.Redact($"Authorization: Basic {credential}");

        Assert.DoesNotContain(credential, redacted, StringComparison.Ordinal);
        Assert.Contains(RedactionToken, redacted, StringComparison.Ordinal);
    }

    [Fact]
    public void TheRestOfTheMessageSurvivesTheRedaction()
    {
        var credential = Credential("agent:secret");

        var redacted = SensitiveDataRedactor.Redact($"Basic {credential} could not be verified");

        Assert.StartsWith($"Basic {RedactionToken}", redacted, StringComparison.Ordinal);
        Assert.EndsWith("could not be verified", redacted, StringComparison.Ordinal);
    }

    [Fact]
    public void OtherSecretsAreStillRedacted()
    {
        Assert.Contains(RedactionToken, SensitiveDataRedactor.Redact("Bearer abcdefghijkl"), StringComparison.Ordinal);
        Assert.Contains(RedactionToken, SensitiveDataRedactor.Redact("sk-abcdefgh"), StringComparison.Ordinal);
        Assert.Contains(RedactionToken, SensitiveDataRedactor.Redact("ghp_abcdefghijkl"), StringComparison.Ordinal);
    }
}
