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
    public void SetEnabled_False_LeavesAnotherCopysRegistrationAlone()
    {
        var registry = new FakeRunKey();
        registry.Values[LaunchAtLoginService.ValueName] = "\"D:\\Old\\BugNarrator.Windows.exe\"";
        var service = new LaunchAtLoginService(registry, () => Exe);

        service.SetEnabled(false);

        Assert.Equal("\"D:\\Old\\BugNarrator.Windows.exe\"", registry.Values[LaunchAtLoginService.ValueName]);
    }

    [Fact]
    public void CurrentStatus_IsDisabledWhenWindowsSettingsDisabledTheEntryButLeftTheValue()
    {
        // What the Settings Startup page actually does: the Run value stays, StartupApproved says no.
        var registry = new FakeRunKey();
        registry.Values[LaunchAtLoginService.ValueName] = $"\"{Exe}\"";
        registry.Approved[LaunchAtLoginService.ValueName] = false;
        var service = new LaunchAtLoginService(registry, () => Exe);

        Assert.Equal(LaunchAtLoginStatus.Disabled, service.CurrentStatus());

        // Re-enabling from our Settings must clear that verdict, not just rewrite the value.
        Assert.Equal(LaunchAtLoginStatus.Enabled, service.SetEnabled(true));
        Assert.True(registry.Approved[LaunchAtLoginService.ValueName]);
    }

    [Fact]
    public void SetEnabled_False_AlsoRemovesTheStartupApprovedVerdict()
    {
        var registry = new FakeRunKey();
        registry.Values[LaunchAtLoginService.ValueName] = $"\"{Exe}\"";
        registry.Approved[LaunchAtLoginService.ValueName] = true;
        var service = new LaunchAtLoginService(registry, () => Exe);

        service.SetEnabled(false);

        Assert.Empty(registry.Values);
        Assert.Empty(registry.Approved);
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

        public Dictionary<string, bool> Approved { get; } = new(StringComparer.OrdinalIgnoreCase);
        public bool? GetStartupApproved(string name) => Approved.TryGetValue(name, out var approved) ? approved : null;
        public void SetStartupApproved(string name, bool approved) { if (ThrowOnWrite is not null) throw ThrowOnWrite; Approved[name] = approved; }
        public void DeleteStartupApproved(string name) => Approved.Remove(name);
    }
}
