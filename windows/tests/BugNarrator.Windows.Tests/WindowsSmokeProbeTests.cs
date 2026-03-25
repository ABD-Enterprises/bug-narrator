using System.Text.Json;
using BugNarrator.Windows.Services.Diagnostics;
using Xunit;

namespace BugNarrator.Windows.Tests;

public sealed class WindowsSmokeProbeTests : IDisposable
{
    private readonly string tempDirectory;

    public WindowsSmokeProbeTests()
    {
        tempDirectory = Path.Combine(
            Path.GetTempPath(),
            "BugNarrator.Windows.Tests",
            Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(tempDirectory);
    }

    [Fact]
    public void TryWriteReport_WithSmokeOutputArgument_WritesStructuredReport()
    {
        var outputPath = Path.Combine(tempDirectory, "smoke.json");

        var handled = WindowsSmokeProbe.TryWriteReport(
            [WindowsSmokeProbe.SmokeOutputArgument, outputPath],
            out var exitCode);

        Assert.True(handled);
        Assert.Equal(0, exitCode);
        Assert.True(File.Exists(outputPath));

        var report = JsonSerializer.Deserialize<WindowsSmokeProbe.WindowsSmokeReport>(
            File.ReadAllText(outputPath));

        Assert.NotNull(report);
        Assert.Equal("BugNarrator.Windows", report!.AppName);
        Assert.Equal("smoke", report.Mode);
        Assert.False(string.IsNullOrWhiteSpace(report.Version));
    }

    [Fact]
    public void TryWriteReport_WithMissingSmokeOutputPath_ReturnsHandledError()
    {
        var handled = WindowsSmokeProbe.TryWriteReport(
            [WindowsSmokeProbe.SmokeOutputArgument],
            out var exitCode);

        Assert.True(handled);
        Assert.Equal(2, exitCode);
    }

    public void Dispose()
    {
        if (Directory.Exists(tempDirectory))
        {
            Directory.Delete(tempDirectory, recursive: true);
        }
    }
}
