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
    [Theory]
    [InlineData(1e308)]
    [InlineData(-1e308)]
    [InlineData(9223372036854775808d)]
    public void FormatElapsedSeconds_RejectsNumbersOutsideTheIntegerRange(double seconds)
    {
        Assert.Equal("00:00", SessionTimeFormatter.FormatElapsedSeconds(seconds));
    }

    [Fact]
    public void FormatElapsedSeconds_HandlesFiniteValuesLargerThanTimeSpan()
    {
        Assert.Equal("277777777777:46:40", SessionTimeFormatter.FormatElapsedSeconds(1e15));
        Assert.NotEmpty(SessionTimeFormatter.FormatElapsedSeconds(Math.BitDecrement((double)long.MaxValue)));
    }
}
