using BugNarrator.Core.Export;
using Xunit;

namespace BugNarrator.Core.Tests;

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

    // MARK: #1200 — the bypasses #1118 closed on macOS, ported

    [Fact]
    public void Neutralize_DefangsLinkMasksImagesAndReferenceDefinitions()
    {
        Assert.Equal("click \\[here](https://evil.example) now", UntrustedMarkdown.Neutralize("click [here](https://evil.example) now"));
        Assert.Equal("!\\[pixel](https://tracker.example/p.png)", UntrustedMarkdown.Neutralize("![pixel](https://tracker.example/p.png)"));
        Assert.StartsWith("\\[docs]:", UntrustedMarkdown.Neutralize("[docs]: https://evil.example"), System.StringComparison.Ordinal);
        Assert.Equal("&lt;https://evil.example&gt;", UntrustedMarkdown.Neutralize("<https://evil.example>"));
        // A bare URL is the one link form that stays live: its target is visible.
        Assert.Equal("see https://github.com/acme/widgets", UntrustedMarkdown.Neutralize("see https://github.com/acme/widgets"));
    }

    [Fact]
    public void Neutralize_SurvivesAttackerBackslashesAndEscapesEveryBracket()
    {
        // An attacker's own backslash must not pair with ours and free the "[".
        Assert.Equal("\\\\\\[Pay](https://evil.example)", UntrustedMarkdown.Neutralize("\\[Pay](https://evil.example)"));
        Assert.Equal("\\[a](x) \\[b](y)", UntrustedMarkdown.Neutralize("[a](x) [b](y)"));
    }

    [Theory]
    [InlineData("  ===", "  \\===")]
    [InlineData(" - [ ] task", " \\- \\[ ] task")]
    [InlineData("___", "\\___")]
    [InlineData(":--|:--", "\\:--|:--")]
    [InlineData("1. forged step", "1\\. forged step")]
    [InlineData("  2) forged", "  2\\) forged")]
    [InlineData("3.5 seconds", "3.5 seconds")]
    [InlineData("v1.2", "v1.2")]
    public void Neutralize_HandlesIndentedBlockSyntaxAndOrderedLists(string input, string expected)
    {
        Assert.Equal(expected, UntrustedMarkdown.Neutralize(input));
    }

    [Theory]
    [InlineData("see GH-42", "see GH-\u200B42")]
    [InlineData("see gh-42", "see gh-\u200B42")]
    public void Neutralize_BreaksIssueReferencesInAnyCase(string input, string expected)
    {
        Assert.Equal(expected, UntrustedMarkdown.Neutralize(input));
    }

    [Theory]
    [InlineData("Title\r===\r```", "Title\n\\===\n\\```")]
    [InlineData("a\r\n- b", "a\n\\- b")]
    public void Neutralize_TreatsALoneCarriageReturnAsALineBreak(string input, string expected)
    {
        Assert.Equal(expected, UntrustedMarkdown.Neutralize(input));
    }
}
