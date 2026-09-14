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
    private static readonly string Ping = Path.Combine(Environment.SystemDirectory, "PING.EXE");
    private readonly string root = Path.Combine(Path.GetTempPath(), "BugNarrator.Windows.Tests", Guid.NewGuid().ToString("N"));
    private readonly string models;

    private readonly string cmd = Cmd;

    public LocalServerProcessTests()
    {
        // The install directory is the parent of Models: the stderr log lands in the test root.
        models = Path.Combine(root, "Models");
        Directory.CreateDirectory(root);
    }

    public void Dispose()
    {
        // A just-killed stand-in can hold its executable open for a moment; retry briefly.
        for (var attempt = 0; attempt < 10; attempt++)
        {
            try
            {
                if (Directory.Exists(root))
                {
                    Directory.Delete(root, recursive: true);
                }

                return;
            }
            catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
            {
                Thread.Sleep(200);
            }
        }
    }

    [Fact]
    public async Task CleanExit_ReportsStatusZeroAndTheStderrTail()
    {
        if (!OperatingSystem.IsWindows()) return;
        var exit = new TaskCompletionSource<(int Status, string Detail)>();

        using var process = LocalServerProcess.Launch(cmd, "/c \"echo started 1>&2 & exit 0\"", models, (status, detail) => exit.TrySetResult((status, detail)), TimeSpan.FromSeconds(2));

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
        using var process = LocalServerProcess.Launch(cmd, "/c \"(for /L %i in (1,1,300) do @echo line-number-%i 1>&2) & exit 7\"", models, (status, detail) => exit.TrySetResult((status, detail)), TimeSpan.FromSeconds(2));

        var (code, tail) = await exit.Task.WaitAsync(TimeSpan.FromSeconds(15));
        Assert.Equal(7, code);
        Assert.EndsWith("line-number-300", tail);
        Assert.DoesNotContain("line-number-1\r", tail);
        Assert.True(System.Text.Encoding.UTF8.GetByteCount(tail) <= LocalServerProcess.StderrTailBytes);
        Assert.True(File.Exists(Path.Combine(root, LocalServerProcess.StderrLogName)));
    }

    [Fact]
    public void LaunchedProcess_IsInsideTheJobObject()
    {
        if (!OperatingSystem.IsWindows()) return;
        using var process = LocalServerProcess.Launch(cmd, "/c \"ping -n 30 127.0.0.1 > nul\"", models, (_, _) => { }, TimeSpan.FromSeconds(2));

        Assert.True(process.IsInJob);
        process.Terminate();
        process.WaitForExitAsync().Wait(TimeSpan.FromSeconds(10));
    }

    [Fact]
    public async Task Terminate_StopsACtrlCAwareProcessGracefullyWithinTheGrace()
    {
        if (!OperatingSystem.IsWindows()) return;
        // ping stops on Ctrl+C; with a 10 s grace, exiting well inside it proves the graceful signal
        // reached the process rather than the kill after the grace period.
        var exit = new TaskCompletionSource<int>();
        using var process = LocalServerProcess.Launch(Ping, "-n 60 127.0.0.1", models, (status, _) => exit.TrySetResult(status), TimeSpan.FromSeconds(10));
        await Task.Delay(500);
        var started = DateTimeOffset.UtcNow;

        process.Terminate();
        process.Terminate(); // idempotent

        await process.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(15));
        Assert.True(process.HasExited);
        Assert.True(DateTimeOffset.UtcNow - started < TimeSpan.FromSeconds(5), $"did not exit inside the grace period: {process.LastSignalOutcome}");
        Assert.Equal("Ctrl+C sent", process.LastSignalOutcome);
        await exit.Task.WaitAsync(TimeSpan.FromSeconds(5));
    }

    [Fact]
    public async Task Terminate_KillsTheWholeTree_WhenTheProcessIgnoresTheGracefulSignal()
    {
        if (!OperatingSystem.IsWindows()) return;
        // cmd runs a chain of pings: Ctrl+C ends the current ping and cmd moves on to the next, so
        // the process outlives the grace and the kill must take the whole tree.
        var exit = new TaskCompletionSource<int>();
        using var process = LocalServerProcess.Launch(cmd, "/c \"ping -n 60 127.0.0.1 > nul & ping -n 60 127.0.0.1 > nul & ping -n 60 127.0.0.1 > nul\"", models, (status, _) => exit.TrySetResult(status), TimeSpan.FromMilliseconds(500));
        await Task.Delay(500);
        // Children are identified by job membership, not by name or time, so concurrent tests cannot interfere.
        Assert.NotEmpty(PingsInJob(process));

        process.Terminate();
        await process.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(10));
        await exit.Task.WaitAsync(TimeSpan.FromSeconds(5));
        await Task.Delay(500);

        Assert.Empty(PingsInJob(process));
    }

    /// <summary>Live ping processes inside this server's job — the launched tree and nothing else.</summary>
    private static List<int> PingsInJob(LocalServerProcess process)
    {
        var found = new List<int>();
        foreach (var ping in System.Diagnostics.Process.GetProcessesByName("ping"))
        {
            using (ping)
            {
                if (process.JobContains(ping) && !ping.HasExited)
                {
                    found.Add(ping.Id);
                }
            }
        }

        return found;
    }

    [Fact]
    public void StderrTail_IsCappedInBytesNotCharacters()
    {
        var log = Path.Combine(root, "tail.log");
        // 3-byte UTF-8 characters: 2000 of them is 6000 bytes, well past the 4096-byte cap.
        File.WriteAllText(log, new string('\u20AC', 2000));

        var tail = LocalServerProcess.ReadStderrTail(log);

        Assert.True(System.Text.Encoding.UTF8.GetByteCount(tail) <= LocalServerProcess.StderrTailBytes);
        Assert.DoesNotContain('�', tail);

        // 4095 ASCII bytes then an unfinished 3-byte lead: no replacement character, still within the cap.
        var ragged = Path.Combine(root, "ragged.log");
        File.WriteAllBytes(ragged, [.. Enumerable.Repeat((byte)'a', 4095), 0xE2]);
        var raggedTail = LocalServerProcess.ReadStderrTail(ragged);
        Assert.Equal(4095, raggedTail.Length);
        Assert.DoesNotContain('�', raggedTail);

        Assert.Equal(string.Empty, LocalServerProcess.ReadStderrTail(Path.Combine(root, "absent.log")));
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
        Assert.Throws<LocalServerFailure>(() => LocalServerProcess.Launch(Path.Combine(root, "missing.exe"), "", models, (_, _) => { }, TimeSpan.FromSeconds(1)));
    }
}
