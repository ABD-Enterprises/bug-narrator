using BugNarrator.Windows.Services.Export;
using Xunit;

namespace BugNarrator.Windows.Tests;

public sealed class UntrustedMarkdownTests
{
    [Fact]
    public void Neutralize_DefangsMentionsAndIssueReferences()
    {
        var output = UntrustedMarkdown.Neutralize("@channel ping #123 done");

        // Ordinal comparison: a zero-width space is inserted after @/# (which
        // breaks GitHub's byte/regex-based autolink parser). A culture-aware
        // comparison would ignore the ZWSP, so assert ordinally.
        Assert.DoesNotContain("@channel", output, System.StringComparison.Ordinal);
        Assert.DoesNotContain("#123", output, System.StringComparison.Ordinal);
    }

    [Fact]
    public void Neutralize_EscapesRawHtml()
    {
        var output = UntrustedMarkdown.Neutralize("<script>alert(1)</script>");

        Assert.DoesNotContain("<script>", output, System.StringComparison.Ordinal);
        Assert.Contains("&lt;script&gt;", output, System.StringComparison.Ordinal);
    }

    [Fact]
    public void Neutralize_DefeatsInjectedHeading()
    {
        var output = UntrustedMarkdown.Neutralize("## Injected heading");

        Assert.False(output.StartsWith("## ", System.StringComparison.Ordinal));
    }

    [Theory]
    [InlineData("```malicious fence")]
    [InlineData("- injected list item")]
    [InlineData("| injected | table |")]
    public void Neutralize_EscapesLeadingBlockMarkers(string input)
    {
        var output = UntrustedMarkdown.Neutralize(input);

        Assert.StartsWith("\\", output, System.StringComparison.Ordinal);
    }

    [Fact]
    public void Neutralize_PreservesPlainText()
    {
        var output = UntrustedMarkdown.Neutralize("The login button stays disabled after valid input.");

        Assert.Equal("The login button stays disabled after valid input.", output);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    public void Neutralize_HandlesNullAndEmpty(string? input)
    {
        Assert.Equal(string.Empty, UntrustedMarkdown.Neutralize(input));
    }
}
