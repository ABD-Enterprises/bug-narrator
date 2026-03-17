namespace BugNarrator.Core.Models;

public sealed record SessionRecord(
    Guid Id,
    string Title,
    DateTimeOffset CreatedAt,
    string SessionDirectory
);
