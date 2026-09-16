using BugNarrator.Core.Export;
using Xunit;

namespace BugNarrator.Core.Tests;

/// <summary>Mirrors Tests/BugNarratorTests/TrackerExportPayloadBudgetTests.swift (#1200, macOS #1112).</summary>
public sealed class TrackerExportPayloadBudgetTests
{
    [Fact]
    public void TrackerTitle_PlainShortTitlePassesThroughUnchanged()
    {
        Assert.Equal("Login button stuck disabled", TrackerExportPayloadBudget.TrackerTitle("Login button stuck disabled", 255));
    }

    [Fact]
    public void TrackerTitle_CollapsesWhitespaceRunsAndNewlines()
    {
        Assert.Equal("Crash on launch after update", TrackerExportPayloadBudget.TrackerTitle("  Crash\r\non   launch\t\tafter\nupdate  ", 255));
    }

    [Theory]
    [InlineData(" \n\t ")]
    [InlineData("")]
    [InlineData(null)]
    public void TrackerTitle_WhitespaceOnlyBecomesEmpty(string? value)
    {
        Assert.Equal("", TrackerExportPayloadBudget.TrackerTitle(value, 255));
    }

    [Fact]
    public void TrackerTitle_ExactlyAtTheCapIsKeptWhole()
    {
        var title = new string('a', 255);
        Assert.Equal(title, TrackerExportPayloadBudget.TrackerTitle(title, 255));
    }

    [Fact]
    public void TrackerTitle_OneOverTheCapIsCutToTheCapEndingInAnEllipsis()
    {
        var result = TrackerExportPayloadBudget.TrackerTitle(new string('a', 256), 255);
        Assert.Equal(255, result.Length);
        Assert.Equal(new string('a', 254) + "…", result);
    }

    [Fact]
    public void TrackerTitle_CutDoesNotLeaveATrailingSpaceBeforeTheEllipsis()
    {
        Assert.Equal("a…", TrackerExportPayloadBudget.TrackerTitle("a bcd", 2));
        // "w " has period 2, so the last kept index (253, odd) is a space and must be trimmed.
        var result = TrackerExportPayloadBudget.TrackerTitle(string.Concat(Enumerable.Repeat("w ", 150)), 255);
        Assert.EndsWith("w…", result, System.StringComparison.Ordinal);
        Assert.Equal(254, result.Length);
    }

    [Fact]
    public void TrackerTitle_NeverCutsInsideASurrogatePair()
    {
        var title = "a" + string.Concat(Enumerable.Repeat("😀", 128)); // 257 UTF-16 units; unit 254 is a high surrogate
        var result = TrackerExportPayloadBudget.TrackerTitle(title, 255);

        Assert.False(char.IsHighSurrogate(result[^2]), "the cut must not leave a lone high surrogate before the ellipsis");
        Assert.EndsWith("😀…", result, System.StringComparison.Ordinal);
        Assert.True(result.Length <= 255);
    }

    [Fact]
    public void TrackerTitle_CollapsingHappensBeforeMeasuring()
    {
        Assert.Equal("short title", TrackerExportPayloadBudget.TrackerTitle("short" + new string(' ', 290) + "title", 255));
    }

    [Fact]
    public void TrackerTitle_HardLimitsMatchTheTrackers()
    {
        Assert.Equal(255, TrackerExportPayloadBudget.JiraSummaryLimit);
        Assert.Equal(256, TrackerExportPayloadBudget.GitHubTitleLimit);
    }

    [Fact]
    public void Truncated_OvershootsMaxCharactersBySuffixDesign()
    {
        // Cuts to max - 36 then appends a 47-character marker: pinned as the current contract,
        // shared with macOS, where every caller uses a self-imposed body budget with slack.
        var result = TrackerExportPayloadBudget.Truncated(new string('x', 1_000), 500);
        Assert.Equal(511, result.Length);
        Assert.EndsWith(" …[truncated by BugNarrator for tracker limits]", result, System.StringComparison.Ordinal);
    }
}
