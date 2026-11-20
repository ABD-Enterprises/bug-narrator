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
        // A credential is often written next to more of the same alphabet.
        var credential = Credential("agent:secret");

        var redacted = SensitiveDataRedactor.Redact($"Basic {credential}XYZ");

        Assert.DoesNotContain(credential, redacted, StringComparison.Ordinal);
        Assert.Contains(RedactionToken, redacted, StringComparison.Ordinal);
    }

    [Fact]
    public void ABasicCredentialPrecededByOtherBase64CharactersIsRedacted()
    {
        // The same, with the extra characters in front of the credential.
        var credential = Credential("agent:secret");

        var redacted = SensitiveDataRedactor.Redact($"Basic XYZ{credential}");

        Assert.DoesNotContain(credential, redacted, StringComparison.Ordinal);
        Assert.Contains(RedactionToken, redacted, StringComparison.Ordinal);
    }

    [Fact]
    public void ABasicCredentialThatIsNotAsciiIsRedacted()
    {
        // A user name is not always written in ASCII, and the credential is
        // still a credential.
        var credential = Credential("usér:pass");

        var redacted = SensitiveDataRedactor.Redact($"Basic {credential}");

        Assert.DoesNotContain(credential, redacted, StringComparison.Ordinal);
        Assert.Contains(RedactionToken, redacted, StringComparison.Ordinal);
    }

    [Fact]
    public void ALongRunAfterBasicIsRedacted()
    {
        // A run this long is not a word, so it is data and is redacted whole.
        var run = new string('A', 600);

        var redacted = SensitiveDataRedactor.Redact($"Basic {run}");

        Assert.DoesNotContain(run, redacted, StringComparison.Ordinal);
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
    public void AnAuthorizationHeaderIsRedacted()
    {
        // The header is redacted as a whole, by the header rule and not by the
        // Basic rule: everything after the colon goes.
        var credential = Credential("agent:secret");

        var redacted = SensitiveDataRedactor.Redact($"Authorization: Basic {credential}");

        Assert.DoesNotContain(credential, redacted, StringComparison.Ordinal);
        Assert.Equal($"Authorization: {RedactionToken}", redacted);
    }

    [Fact]
    public void OtherSecretsAreStillRedacted()
    {
        Assert.Contains(RedactionToken, SensitiveDataRedactor.Redact("Bearer abcdefghijkl"), StringComparison.Ordinal);
        Assert.Contains(RedactionToken, SensitiveDataRedactor.Redact("sk-abcdefgh"), StringComparison.Ordinal);
        Assert.Contains(RedactionToken, SensitiveDataRedactor.Redact("ghp_abcdefghijkl"), StringComparison.Ordinal);
    }
}
