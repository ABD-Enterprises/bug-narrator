namespace BugNarrator.Core.Workflow;

public static class SessionTimeFormatter
{
    public static string FormatDuration(TimeSpan duration)
    {
        var safeDuration = duration < TimeSpan.Zero ? TimeSpan.Zero : duration;

        return safeDuration.TotalHours >= 1
            ? $"{(int)safeDuration.TotalHours:D2}:{safeDuration.Minutes:D2}:{safeDuration.Seconds:D2}"
            : $"{safeDuration.Minutes:D2}:{safeDuration.Seconds:D2}";
    }

    public static string FormatElapsedSeconds(double seconds)
    {
        return FormatDuration(TimeSpan.FromSeconds(Math.Max(0, seconds)));
    }
}
