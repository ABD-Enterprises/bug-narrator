using System.Runtime.CompilerServices;
using System.Text.RegularExpressions;
using BugNarrator.Core.Models;
using BugNarrator.Core.Workflow;
using Xunit;

namespace BugNarrator.Core.Tests;

public sealed class SampleSessionTests
{
    /// <summary>
    /// The constants are read from Sources/BugNarrator/Utilities/SampleSession.swift rather than
    /// restated, so the two fixtures cannot drift apart silently.
    /// </summary>
    [Fact]
    public void Constants_EqualTheMacSampleSession()
    {
        var swift = File.ReadAllText(Path.Combine(RepositoryRoot(), "Sources", "BugNarrator", "Utilities", "SampleSession.swift"));

        Assert.Equal(Regex.Match(swift, @"UUID\(uuidString: ""([0-9A-F-]+)""\)").Groups[1].Value, SampleSession.Id.ToString().ToUpperInvariant());
        Assert.Equal(Regex.Match(swift, @"static let title = ""([^""]+)""").Groups[1].Value, SampleSession.Title);
        Assert.Equal(long.Parse(Regex.Match(swift, @"timeIntervalSince1970: ([\d_]+)").Groups[1].Value.Replace("_", "")), SampleSession.CreatedAt.ToUnixTimeSeconds());
        Assert.Equal(int.Parse(Regex.Match(swift, @"duration: (\d+)").Groups[1].Value), SampleSession.DurationSeconds);

        // The transcript: Swift's multi-line literal with `\` line continuations, joined the way Swift
        // joins it, must equal the Windows text word for word.
        var literal = Regex.Match(swift, @"private static let transcript = """"""\r?\n(.*?)\r?\n    """"""", RegexOptions.Singleline).Groups[1].Value;
        var macTranscript = Regex.Replace(literal, @"\\\r?\n\s*", string.Empty);
        macTranscript = string.Join("\n", macTranscript.Split('\n').Select(line => line.StartsWith("    ") ? line[4..] : line)).Replace("\r", string.Empty);
        Assert.Equal(macTranscript, SampleSession.Transcript);
    }

    [Fact]
    public void Make_IsTextOnlyCompletedAndFlaggedAsTheSample()
    {
        var session = SampleSession.Make(@"C:\sessions");

        Assert.True(session.IsSampleSession);
        Assert.Equal(SessionTranscriptionStatus.Completed, session.TranscriptionStatus);
        Assert.Empty(session.Screenshots);
        Assert.Equal(4, session.TimelineMoments.Count);
        Assert.Equal(3, session.IssueExtraction!.Issues.Count);
        Assert.Equal(96, (int)session.Duration.TotalSeconds);
        Assert.StartsWith(@"C:\sessions\sample-", session.SessionDirectory);
        // Deterministic, so a second Make is the same session (macOS: stable id, fixed createdAt).
        var again = SampleSession.Make(@"C:\sessions");
        Assert.Equal(session.SessionId, again.SessionId);
        Assert.Equal(session.CreatedAt, again.CreatedAt);
        Assert.Equal(session.TranscriptText, again.TranscriptText);
        Assert.Equal(session.IssueExtraction!.Issues.Select(issue => issue.IssueId), again.IssueExtraction!.Issues.Select(issue => issue.IssueId));
    }

    [Fact]
    public void IsSampleSession_DefaultsFalseForSessionsSavedBeforeTheFieldExisted()
    {
        var json = """{"SessionId":"00000000-0000-4000-8000-000000000001","Title":"Real","CreatedAt":"2026-09-01T12:00:00+00:00","RecordingStartedAt":"2026-09-01T12:00:00+00:00","RecordingStoppedAt":"2026-09-01T12:01:00+00:00","SessionDirectory":"","AudioFilePath":"","MetadataFilePath":"","TranscriptMarkdownFilePath":"","TranscriptText":"","ReviewSummary":"","TranscriptionStatus":0,"TranscriptionModel":"whisper-1","LanguageHint":null,"Prompt":null,"TranscriptionFailureMessage":null,"IssueExtraction":null,"Screenshots":[],"TimelineMoments":[]}""";

        var session = System.Text.Json.JsonSerializer.Deserialize<CompletedSession>(json)!;

        Assert.False(session.IsSampleSession);
    }

    private static string RepositoryRoot([CallerFilePath] string sourceFilePath = "")
    {
        var directory = Path.GetDirectoryName(sourceFilePath)!;
        return Path.GetFullPath(Path.Combine(directory, "..", "..", ".."));
    }
}
