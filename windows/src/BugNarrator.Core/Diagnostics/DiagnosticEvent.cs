namespace BugNarrator.Core.Diagnostics;

public sealed record DiagnosticEvent(
    string Category,
    string Message,
    DateTimeOffset Timestamp
);
