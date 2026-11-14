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

    [Fact]
    public void Neutralize_EscapesInsideACharacterCluster()
    {
        // A "[" that is part of a larger cluster - a combining mark or a
        // variation selector - opens a link label just as a bare one does, so
        // it has to be escaped inside the cluster as well. The macOS port
        // missed this until it worked on code units too; both ports have to
        // send the same body.
        Assert.Equal("\\[\u0301click](https://evil.example)", UntrustedMarkdown.Neutralize("[\u0301click](https://evil.example)"));
        Assert.Equal("\\[\uFE0Fclick](https://evil.example)", UntrustedMarkdown.Neutralize("[\uFE0Fclick](https://evil.example)"));
        Assert.Equal("!\\[\u0301alt](https://evil.example/x)", UntrustedMarkdown.Neutralize("![\u0301alt](https://evil.example/x)"));
        // A block marker that is part of a larger cluster is the marker as far
        // as a code unit is concerned.
        Assert.Equal("\\*\u0301 item", UntrustedMarkdown.Neutralize("*\u0301 item"));
        // A CR followed by LF and then a combining mark is one character
        // cluster, so a literal search for the line break missed it and the CR
        // survived into the body.
        Assert.Equal("a\n\u0301b", UntrustedMarkdown.Neutralize("a\r\n\u0301b"));
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
    [InlineData("+ plus list", "\\+ plus list")]
    [InlineData("1234567890. too long to be a list marker", "1234567890. too long to be a list marker")]
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

    [Fact]
    public void NeutralizeMentions_DefangsTheLiveTriggersOnly()
    {
        var output = UntrustedMarkdown.NeutralizeMentions("@channel ping #123 and GH-42");

        // Plain string operations, so the assertion does not depend on the assertion
        // library's comparison semantics.
        Assert.True(output.Contains("@\u200B", StringComparison.Ordinal));
        Assert.True(output.Contains("#\u200B", StringComparison.Ordinal));
        Assert.True(output.Contains("GH-\u200B", StringComparison.Ordinal));
        // The text stays visually identical: only zero-width spaces are added.
        Assert.Equal(
            "@channel ping #123 and GH-42",
            output.Replace("\u200B", string.Empty, StringComparison.Ordinal));
    }

    [Fact]
    public void NeutralizeMentions_LeavesMarkdownSyntaxAlone()
    {
        // The fields this is used for are plain text, not markdown, so the block-structure and
        // link escapes the GitHub body needs would only mangle them.
        Assert.Equal("see [docs]", UntrustedMarkdown.NeutralizeMentions("see [docs]"));
        Assert.Equal("- list item", UntrustedMarkdown.NeutralizeMentions("- list item"));
    }
}
