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
/// so every acquisition here happens on its own thread — otherwise a second acquire on the test
/// thread would succeed and the tests would pass without proving anything.
/// </summary>
public sealed class SingleInstanceTests
{
    [Fact]
    public async Task SecondInstance_IsRefusedAndSignalsTheFirstToFocus()
    {
        // Named OS primitives, so a unique id keeps this test isolated from a real running app.
        var applicationId = $"BugNarrator.Tests.{Guid.NewGuid():N}";
        using var first = new SingleInstanceService(applicationId);
        using var second = new SingleInstanceService(applicationId);
        using var focusRequested = new SemaphoreSlim(0);
        first.StartFocusRequestPump(() => focusRequested.Release());

        using var firstOwner = new InstanceOwner(first);
        Assert.True(firstOwner.Acquired, "the first launch must own the primary instance");

        using var secondOwner = new InstanceOwner(second);
        Assert.False(secondOwner.Acquired, "a second launch must not become primary");

        // What the second process does before exiting: hand focus to the first.
        second.SignalPrimaryInstance();

        Assert.True(await focusRequested.WaitAsync(TimeSpan.FromSeconds(5)), "the first instance never received the focus request");
    }

    [Fact]
    public void PrimaryInstance_IsReleasedOnDispose_SoTheNextLaunchCanOwnIt()
    {
        var applicationId = $"BugNarrator.Tests.{Guid.NewGuid():N}";
        var first = new SingleInstanceService(applicationId);
        using (var firstOwner = new InstanceOwner(first))
        {
            Assert.True(firstOwner.Acquired);
            firstOwner.DisposeServiceOnOwningThread();
        }

        using var next = new SingleInstanceService(applicationId);
        using var nextOwner = new InstanceOwner(next);
        Assert.True(nextOwner.Acquired, "after the primary exits, the next launch must become primary");
    }

    /// <summary>Acquires on a dedicated thread and holds the ownership there until disposed.</summary>
    private sealed class InstanceOwner : IDisposable
    {
        private readonly ManualResetEventSlim release = new();
        private readonly ManualResetEventSlim disposeRequested = new();
        private readonly Thread thread;

        public InstanceOwner(SingleInstanceService service)
        {
            thread = new Thread(() =>
            {
                Acquired = service.TryAcquirePrimaryInstance();
                Ready.Set();
                release.Wait();
                if (disposeRequested.IsSet)
                {
                    // ReleaseMutex must run on the owning thread, so Dispose happens here.
                    service.Dispose();
                }
            });
            thread.Start();
            Assert.True(Ready.Wait(TimeSpan.FromSeconds(5)), "the owner thread never reported");
        }

        public bool Acquired { get; private set; }

        private ManualResetEventSlim Ready { get; } = new();

        public void DisposeServiceOnOwningThread()
        {
            disposeRequested.Set();
            release.Set();
            thread.Join();
        }

        public void Dispose()
        {
            release.Set();
            thread.Join();
            release.Dispose();
            disposeRequested.Dispose();
            Ready.Dispose();
        }
    }
}
