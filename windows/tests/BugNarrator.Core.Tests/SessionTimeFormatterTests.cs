using BugNarrator.Core.Workflow;
using Xunit;

namespace BugNarrator.Core.Tests;

public sealed class SessionTimeFormatterTests
{
    [Theory]
    [InlineData(double.NaN)]
    [InlineData(double.PositiveInfinity)]
    [InlineData(double.NegativeInfinity)]
    [InlineData(-5)]
    public void FormatElapsedSeconds_IsTotalForNonFiniteAndNegativeInput(double seconds)
    {
        // A session persisted before #1196 can carry a non-finite timestamp; rendering must not throw.
        Assert.Equal(SessionTimeFormatter.FormatDuration(TimeSpan.Zero), SessionTimeFormatter.FormatElapsedSeconds(seconds));
    }

    [Fact]
    public void FormatElapsedSeconds_FormatsFiniteInput()
    {
        Assert.Equal(SessionTimeFormatter.FormatDuration(TimeSpan.FromSeconds(65)), SessionTimeFormatter.FormatElapsedSeconds(65));
    }
}
