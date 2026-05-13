using BugNarrator.Windows.Services.Shell;

namespace BugNarrator.Windows.Shell;

internal sealed class EarlySingleInstanceGuard : IDisposable
{
    private readonly SingleInstanceService singleInstanceService;
    private bool disposed;

    public EarlySingleInstanceGuard(string applicationId)
    {
        singleInstanceService = new SingleInstanceService(applicationId);
    }

    public bool TryAcquire()
    {
        if (singleInstanceService.TryAcquirePrimaryInstance())
        {
            return true;
        }

        singleInstanceService.SignalPrimaryInstance();
        return false;
    }

    public SingleInstanceService TransferOwnership()
    {
        disposed = true;
        return singleInstanceService;
    }

    public void Dispose()
    {
        if (disposed)
        {
            return;
        }

        singleInstanceService.Dispose();
        disposed = true;
    }
}
