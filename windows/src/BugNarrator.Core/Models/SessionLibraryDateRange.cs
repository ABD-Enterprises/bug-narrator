namespace BugNarrator.Core.Models;

public enum SessionLibraryDateRange
{
    All,
    Today,
    Yesterday,
    Last7Days,
    Last30Days,
    // Sessions whose transcription did not complete and can be retried — the macOS
    // "Retry Needed" filter. Sits between Last 30 Days and All Sessions as it does there.
    RetryNeeded,
    CustomRange,
}
