using BugNarrator.Core.Models;
using Xunit;

namespace BugNarrator.Core.Tests;

public sealed class SessionRecordTests
{
    [Fact]
    public void CreatesSessionRecordWithStableFields()
    {
        var createdAt = new DateTimeOffset(2026, 3, 17, 9, 30, 0, TimeSpan.Zero);
        var record = new SessionRecord(
            Guid.Parse("11111111-1111-1111-1111-111111111111"),
            "Windows MVP",
            createdAt,
            @"C:\BugNarrator\Sessions\Windows-MVP");

        Assert.Equal("Windows MVP", record.Title);
        Assert.Equal(createdAt, record.CreatedAt);
        Assert.Equal(@"C:\BugNarrator\Sessions\Windows-MVP", record.SessionDirectory);
    }
}
