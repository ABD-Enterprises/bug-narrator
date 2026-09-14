using BugNarrator.Windows.Services.LocalTranscription;
using Xunit;

namespace BugNarrator.Windows.Tests;

/// <summary>
/// WIN-039 (#1181): the real server process, driven with cmd.exe as a stand-in for the server
/// executable. Windows-only by nature (Job Objects, console control events).
/// </summary>
public sealed class LocalServerProcessTests : IDisposable
{
    private static readonly string Cmd = Path.Combine(Environment.SystemDirectory, "cmd.exe");
    private readonly string root = Path.Combine(Path.GetTempPath(), "BugNarrator.Windows.Tests", Guid.NewGuid().ToString("N"));
    private readonly string models;

    public LocalServerProcessTests()
    {
        models = Path.Combine(root, "Models");
        Directory.CreateDirectory(root);
    }

    public void Dispose()
    {
        if (Directory.Exists(root))
        {
            Directory.Delete(root, recursive: true);
        }
    }

    [Fact]
    public async Task CleanExit_ReportsStatusZeroAndTheStderrTail()
    {
        if (!OperatingSystem.IsWindows()) return;
        var exit = new TaskCompletionSource<(int Status, string Detail)>();

        using var process = LocalServerProcess.Launch(Cmd, "/c \"echo started 1>&2 & exit 0\"", models, (status, detail) => exit.TrySetResult((status, detail)), TimeSpan.FromSeconds(2));

        var (code, tail) = await exit.Task.WaitAsync(TimeSpan.FromSeconds(10));
        Assert.Equal(0, code);
        Assert.Equal("started", tail);
        Assert.True(Directory.Exists(models)); // the model cache directory is created for the server
    }

    [Fact]
    public async Task FailedExit_ReportsTheStatusAndKeepsOnlyTheStderrTail()
    {
        if (!OperatingSystem.IsWindows()) return;
        var exit = new TaskCompletionSource<(int Status, string Detail)>();
        // 300 lines of ~20 bytes: more than the 4 KB tail keeps.
        using var process = LocalServerProcess.Launch(Cmd, "/c \"(for /L %i in (1,1,300) do @echo line-number-%i 1>&2) & exit 7\"", models, (status, detail) => exit.TrySetResult((status, detail)), TimeSpan.FromSeconds(2));

        var (code, tail) = await exit.Task.WaitAsync(TimeSpan.FromSeconds(15));
        Assert.Equal(7, code);
        Assert.EndsWith("line-number-300", tail);
        Assert.DoesNotContain("line-number-1\r", tail);
        Assert.True(tail.Length <= LocalServerProcess.StderrTailBytes);
    }

    [Fact]
    public void LaunchedProcess_IsInsideTheJobObject()
    {
        if (!OperatingSystem.IsWindows()) return;
        using var process = LocalServerProcess.Launch(Cmd, "/c \"ping -n 30 127.0.0.1 > nul\"", models, (_, _) => { }, TimeSpan.FromSeconds(2));

        Assert.True(process.IsInJob);
        process.Terminate();
    }

    [Fact]
    public async Task Terminate_StopsALongRunningProcessWithinTheGracePlusKill()
    {
        if (!OperatingSystem.IsWindows()) return;
        var exit = new TaskCompletionSource<int>();
        using var process = LocalServerProcess.Launch(Cmd, "/c \"ping -n 60 127.0.0.1 > nul\"", models, (status, _) => exit.TrySetResult(status), TimeSpan.FromSeconds(1));
        var started = DateTimeOffset.UtcNow;

        process.Terminate();
        process.Terminate(); // idempotent

        await process.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(10));
        Assert.True(process.HasExited);
        Assert.True(DateTimeOffset.UtcNow - started < TimeSpan.FromSeconds(8));
        await exit.Task.WaitAsync(TimeSpan.FromSeconds(5));
    }

    [Fact]
    public async Task Terminate_KillsTheWholeTree_WhenTheProcessIgnoresTheGracefulSignal()
    {
        if (!OperatingSystem.IsWindows()) return;
        // cmd spawns ping as a child; the kill must take the child too.
        var started = DateTime.Now;
        using var process = LocalServerProcess.Launch(Cmd, "/c \"ping -n 60 127.0.0.1 > nul & ping -n 60 127.0.0.1 > nul\"", models, (_, _) => { }, TimeSpan.FromMilliseconds(500));
        await Task.Delay(500);
        Assert.NotEmpty(PingsStartedAfter(started));

        process.Terminate();
        await process.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(10));
        await Task.Delay(500);

        Assert.Empty(PingsStartedAfter(started));
    }

    /// <summary>Only pings this test started, so parallel tests cannot skew the count.</summary>
    private static List<int> PingsStartedAfter(DateTime started)
    {
        var found = new List<int>();
        foreach (var ping in System.Diagnostics.Process.GetProcessesByName("ping"))
        {
            try
            {
                if (ping.StartTime >= started && !ping.HasExited)
                {
                    found.Add(ping.Id);
                }
            }
            catch (Exception exception) when (exception is InvalidOperationException or System.ComponentModel.Win32Exception)
            {
                // Exited or inaccessible while we looked: not ours to count.
            }
        }

        return found;
    }

    [Fact]
    public void ServerArguments_BindLoopbackOnTheFixedPortWithThePinnedModel()
    {
        Assert.Equal("--host 127.0.0.1 --port 8422 --model parakeet-tdt-0.6b-v3", LocalServerProcess.ServerArguments);
    }

    [Fact]
    public void Launch_WithAMissingExecutable_ThrowsAndLeavesNothingRunning()
    {
        if (!OperatingSystem.IsWindows()) return;
        Assert.ThrowsAny<Exception>(() => LocalServerProcess.Launch(Path.Combine(root, "missing.exe"), "", models, (_, _) => { }, TimeSpan.FromSeconds(1)));
    }
}
