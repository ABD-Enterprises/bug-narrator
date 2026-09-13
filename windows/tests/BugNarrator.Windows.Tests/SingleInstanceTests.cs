using BugNarrator.Windows.Services.Shell;
using Xunit;

namespace BugNarrator.Windows.Tests;

/// <summary>
/// "Single active recording session" is a must-remain-identical parity contract. Until now its only
/// evidence was a one-time packaged probe on #44. These pin the two halves in CI: one process holds
/// the primary-instance mutex and a second launch is told to exit and hands focus to the first; and
/// (in AudioInputDeviceSelectionTests) a second Start while recording is refused.
///
/// A Mutex is re-entrant for the thread that owns it, and a real second launch is another process,
/// so every instance here lives entirely on its own thread — acquire, hold, and dispose (ReleaseMutex
/// must run on the owning thread). Same-thread acquisition would succeed and prove nothing.
///
/// These are Windows-only by construction: named EventWaitHandle and Mutex are Windows primitives,
/// which is why the whole test project targets net8.0-windows and CI runs it on windows-latest.
/// </summary>
public sealed class SingleInstanceTests
{
    [Fact]
    public async Task SecondInstance_IsRefusedAndSignalsTheFirstToFocus()
    {
        // Named OS primitives, so a unique id keeps this test isolated from a real running app.
        var applicationId = $"BugNarrator.Tests.{Guid.NewGuid():N}";
        using var focusRequested = new SemaphoreSlim(0);

        using var first = InstanceOwner.Launch(applicationId, service => service.StartFocusRequestPump(() => focusRequested.Release()));
        Assert.True(first.Acquired, "the first launch must own the primary instance");

        using var second = InstanceOwner.Launch(applicationId);
        Assert.False(second.Acquired, "a second launch must not become primary");

        // What the second process does before exiting: hand focus to the first.
        second.SignalPrimaryInstance();

        Assert.True(await focusRequested.WaitAsync(TimeSpan.FromSeconds(5)), "the first instance never received the focus request");
    }

    [Fact]
    public void PrimaryInstance_IsReleasedOnDispose_SoTheNextLaunchCanOwnIt()
    {
        var applicationId = $"BugNarrator.Tests.{Guid.NewGuid():N}";

        var first = InstanceOwner.Launch(applicationId);
        Assert.True(first.Acquired);
        first.Dispose(); // the primary exits: its thread disposes the service and releases the mutex

        using var next = InstanceOwner.Launch(applicationId);
        Assert.True(next.Acquired, "after the primary exits, the next launch must become primary");
    }

    /// <summary>
    /// One simulated process: constructs, acquires, holds, and disposes a SingleInstanceService on a
    /// dedicated thread, so mutex ownership and release both happen where the OS requires.
    /// </summary>
    private sealed class InstanceOwner : IDisposable
    {
        private readonly ManualResetEventSlim ready = new();
        private readonly ManualResetEventSlim release = new();
        private readonly Thread thread;
        private SingleInstanceService? service;

        private InstanceOwner(string applicationId, Action<SingleInstanceService>? configure)
        {
            thread = new Thread(() =>
            {
                service = new SingleInstanceService(applicationId);
                configure?.Invoke(service);
                Acquired = service.TryAcquirePrimaryInstance();
                ready.Set();
                release.Wait();
                service.Dispose();
            });
            thread.Start();
        }

        public bool Acquired { get; private set; }

        public static InstanceOwner Launch(string applicationId, Action<SingleInstanceService>? configure = null)
        {
            var owner = new InstanceOwner(applicationId, configure);
            Assert.True(owner.ready.Wait(TimeSpan.FromSeconds(5)), "the owner thread never reported");
            return owner;
        }

        public void SignalPrimaryInstance()
        {
            service!.SignalPrimaryInstance();
        }

        public void Dispose()
        {
            release.Set();
            thread.Join();
            release.Dispose();
            ready.Dispose();
        }
    }
}
