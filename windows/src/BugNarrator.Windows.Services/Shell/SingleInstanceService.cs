namespace BugNarrator.Windows.Services.Shell;

public sealed class SingleInstanceService : ISingleInstanceService
{
    private readonly EventWaitHandle focusEvent;
    private readonly Mutex primaryInstanceMutex;
    private RegisteredWaitHandle? focusRegistration;
    private bool ownsPrimaryInstance;

    public SingleInstanceService(string applicationId)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(applicationId);

        primaryInstanceMutex = new Mutex(false, $"{applicationId}.PrimaryInstance");
        focusEvent = new EventWaitHandle(false, EventResetMode.AutoReset, $"{applicationId}.FocusRequest");
    }

    public bool TryAcquirePrimaryInstance()
    {
        if (ownsPrimaryInstance)
        {
            return true;
        }

        try
        {
            ownsPrimaryInstance = primaryInstanceMutex.WaitOne(0, false);
        }
        catch (AbandonedMutexException)
        {
            ownsPrimaryInstance = true;
        }

        return ownsPrimaryInstance;
    }

    public void SignalPrimaryInstance()
    {
        focusEvent.Set();
    }

    public void StartFocusRequestPump(Action onFocusRequested, CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(onFocusRequested);

        focusRegistration = ThreadPool.RegisterWaitForSingleObject(
            focusEvent,
            static (state, timedOut) =>
            {
                if (timedOut || state is not Action callback)
                {
                    return;
                }

                callback();
            },
            onFocusRequested,
            Timeout.Infinite,
            executeOnlyOnce: false);

        if (cancellationToken.CanBeCanceled)
        {
            cancellationToken.Register(() => focusRegistration?.Unregister(null));
        }
    }

    public void Dispose()
    {
        focusRegistration?.Unregister(null);
        focusRegistration = null;
        focusEvent.Dispose();

        if (ownsPrimaryInstance)
        {
            primaryInstanceMutex.ReleaseMutex();
            ownsPrimaryInstance = false;
        }

        primaryInstanceMutex.Dispose();
    }
}
