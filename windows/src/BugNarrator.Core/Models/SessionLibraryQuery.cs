namespace BugNarrator.Core.Models;

public sealed record SessionLibraryQuery(
    string SearchText,
    SessionLibraryDateRange DateRange,
    SessionLibrarySortOrder SortOrder,
    DateTime? CustomRangeStart = null,
    DateTime? CustomRangeEnd = null)
{
    public static SessionLibraryQuery Default { get; } = new(
        SearchText: string.Empty,
        DateRange: SessionLibraryDateRange.All,
        SortOrder: SessionLibrarySortOrder.NewestFirst);
}
