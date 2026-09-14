using BugNarrator.Windows.Services.Shell;
using Xunit;

namespace BugNarrator.Windows.Tests;

public sealed class LaunchAtLoginServiceTests
{
    private const string Exe = @"C:\Program Files\BugNarrator\BugNarrator.Windows.exe";

    [Fact]
    public void CurrentStatus_IsDisabledWhenNoRunValueExists()
    {
        var service = new LaunchAtLoginService(new FakeRunKey(), () => Exe);

        Assert.Equal(LaunchAtLoginStatus.Disabled, service.CurrentStatus());
    }

    [Fact]
    public void SetEnabled_WritesAQuotedCommandForThisExecutableAndReportsEnabled()
    {
        var registry = new FakeRunKey();
        var service = new LaunchAtLoginService(registry, () => Exe);

        var status = service.SetEnabled(true);

        Assert.Equal(LaunchAtLoginStatus.Enabled, status);
        // Quoted, because the path has spaces and the shell that runs Run entries splits on them.
        Assert.Equal($"\"{Exe}\"", registry.Values[LaunchAtLoginService.ValueName]);
        Assert.Equal(LaunchAtLoginStatus.Enabled, service.CurrentStatus());
    }

    [Fact]
    public void SetEnabled_False_RemovesTheValueAndReportsDisabled()
    {
        var registry = new FakeRunKey();
        registry.Values[LaunchAtLoginService.ValueName] = $"\"{Exe}\"";
        var service = new LaunchAtLoginService(registry, () => Exe);

        Assert.Equal(LaunchAtLoginStatus.Disabled, service.SetEnabled(false));
        Assert.DoesNotContain(LaunchAtLoginService.ValueName, registry.Values.Keys);
    }

    [Fact]
    public void CurrentStatus_IsDisabledWhenTheValuePointsAtADifferentCopy()
    {
        // The Windows Settings Startup page or an older install may have registered another path;
        // that copy launching is not this copy launching, so it reads as disabled here.
        var registry = new FakeRunKey();
        registry.Values[LaunchAtLoginService.ValueName] = "\"D:\\Old\\BugNarrator.Windows.exe\"";
        var service = new LaunchAtLoginService(registry, () => Exe);

        Assert.Equal(LaunchAtLoginStatus.Disabled, service.CurrentStatus());
    }

    [Fact]
    public void CurrentStatus_IsUnavailableWithAMessageWhenTheExecutablePathIsUnknown()
    {
        var registry = new FakeRunKey();
        var service = new LaunchAtLoginService(registry, () => null);

        var status = service.CurrentStatus();

        Assert.False(status.IsAvailable);
        Assert.False(status.IsEnabled);
        Assert.Contains("executable path", status.Message);
        // And enabling does nothing rather than writing a bad command.
        Assert.False(service.SetEnabled(true).IsAvailable);
        Assert.Empty(registry.Values);
    }

    [Fact]
    public void SetEnabled_IsUnavailableWithAMessageWhenTheKeyIsNotWritable()
    {
        var registry = new FakeRunKey { ThrowOnWrite = new UnauthorizedAccessException("denied") };
        var service = new LaunchAtLoginService(registry, () => Exe);

        var status = service.SetEnabled(true);

        Assert.False(status.IsAvailable);
        Assert.Contains("not writable", status.Message);
    }

    private sealed class FakeRunKey : IRunKeyRegistry
    {
        public Dictionary<string, string> Values { get; } = new(StringComparer.OrdinalIgnoreCase);
        public Exception? ThrowOnWrite { get; init; }

        public string? GetValue(string name) => Values.TryGetValue(name, out var value) ? value : null;

        public void SetValue(string name, string command)
        {
            if (ThrowOnWrite is not null) throw ThrowOnWrite;
            Values[name] = command;
        }

        public void DeleteValue(string name)
        {
            if (ThrowOnWrite is not null) throw ThrowOnWrite;
            Values.Remove(name);
        }
    }
}
