using BugNarrator.Core.Models;

namespace BugNarrator.Core.Workflow;

public static class SessionLibraryQueryEvaluator
{
    public static IReadOnlyList<CompletedSession> Apply(
        IEnumerable<CompletedSession> sessions,
        SessionLibraryQuery query,
        DateTimeOffset now)
    {
        var filtered = sessions
            .Where(session => MatchesDateRange(session, query, now))
            .Where(session => MatchesSearch(session, query.SearchText));

        filtered = query.SortOrder == SessionLibrarySortOrder.OldestFirst
            ? filtered.OrderBy(session => session.CreatedAt).ThenBy(session => session.SessionId)
            : filtered.OrderByDescending(session => session.CreatedAt).ThenByDescending(session => session.SessionId);

        return filtered.ToArray();
    }

    private static bool MatchesDateRange(
        CompletedSession session,
        SessionLibraryQuery query,
        DateTimeOffset now)
    {
        var localNow = now.ToLocalTime();
        var sessionLocalDate = session.CreatedAt.ToLocalTime().Date;

        return query.DateRange switch
        {
            SessionLibraryDateRange.All => true,
            SessionLibraryDateRange.Today => sessionLocalDate == localNow.Date,
            SessionLibraryDateRange.Yesterday => sessionLocalDate == localNow.Date.AddDays(-1),
            SessionLibraryDateRange.Last7Days => sessionLocalDate >= localNow.Date.AddDays(-6),
            SessionLibraryDateRange.Last30Days => sessionLocalDate >= localNow.Date.AddDays(-29),
            SessionLibraryDateRange.CustomRange => IsWithinCustomRange(
                sessionLocalDate,
                query.CustomRangeStart,
                query.CustomRangeEnd),
            _ => true,
        };
    }

    private static bool IsWithinCustomRange(
        DateTime sessionLocalDate,
        DateTime? start,
        DateTime? end)
    {
        if (start is null && end is null)
        {
            return true;
        }

        var lowerBound = (start ?? end ?? sessionLocalDate).Date;
        var upperBound = (end ?? start ?? sessionLocalDate).Date;

        if (lowerBound > upperBound)
        {
            (lowerBound, upperBound) = (upperBound, lowerBound);
        }

        return sessionLocalDate >= lowerBound && sessionLocalDate <= upperBound;
    }

    private static bool MatchesSearch(CompletedSession session, string searchText)
    {
        if (string.IsNullOrWhiteSpace(searchText))
        {
            return true;
        }

        var needle = searchText.Trim();

        return Contains(session.Title, needle)
               || Contains(session.TranscriptText, needle)
               || Contains(session.ReviewSummary, needle)
               || (session.IssueExtraction is not null
                   && (Contains(session.IssueExtraction.Summary, needle)
                       || session.IssueExtraction.Issues.Any(issue =>
                           Contains(issue.Title, needle)
                           || Contains(issue.Summary, needle)
                           || Contains(issue.EvidenceExcerpt, needle))))
               || session.Screenshots.Any(screenshot => Contains(screenshot.TimelineLabel, needle))
               || session.TimelineMoments.Any(moment => Contains(moment.Label, needle));
    }

    private static bool Contains(string? haystack, string needle)
    {
        return !string.IsNullOrWhiteSpace(haystack)
               && haystack.Contains(needle, StringComparison.OrdinalIgnoreCase);
    }
}
