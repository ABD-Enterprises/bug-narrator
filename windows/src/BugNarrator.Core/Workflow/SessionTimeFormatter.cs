using System.Globalization;

namespace BugNarrator.Core.Workflow;

/// <summary>
/// Culture and time zone used to render session timestamps. Production uses the current user's
/// settings so the output matches what macOS shows its users; tests pass invariant culture plus UTC
/// so golden assertions do not depend on the host.
/// </summary>
public sealed record SessionTimestampOptions(CultureInfo Culture, TimeZoneInfo TimeZone);

public static class SessionTimeFormatter
{
    /// <summary>
    /// Invariant analogue of the macOS <c>.abbreviated</c> date + <c>.standard</c> time style,
    /// e.g. <c>Mar 17, 2026 at 3:00:00 PM</c>.
    /// </summary>
    private const string TimestampFormat = "MMM d, yyyy 'at' h:mm:ss tt";

    public static SessionTimestampOptions DefaultTimestampOptions =>
        new(CultureInfo.CurrentCulture, TimeZoneInfo.Local);

    public static SessionTimestampOptions InvariantTimestampOptions =>
        new(CultureInfo.InvariantCulture, TimeZoneInfo.Utc);

    public static string FormatTimestamp(DateTimeOffset timestamp, SessionTimestampOptions options)
    {
        var localized = TimeZoneInfo.ConvertTime(timestamp, options.TimeZone);
        return localized.ToString(TimestampFormat, options.Culture);
    }

    public static string FormatDuration(TimeSpan duration)
    {
        var safeDuration = duration < TimeSpan.Zero ? TimeSpan.Zero : duration;

        // macOS ElapsedTimeFormatter renders hours without a leading zero ("1:05:00").
        return safeDuration.TotalHours >= 1
            ? $"{(int)safeDuration.TotalHours}:{safeDuration.Minutes:D2}:{safeDuration.Seconds:D2}"
            : $"{safeDuration.Minutes:D2}:{safeDuration.Seconds:D2}";
    }

    public static string FormatElapsedSeconds(double seconds)
    {
        return FormatDuration(TimeSpan.FromSeconds(Math.Max(0, seconds)));
    }
}
