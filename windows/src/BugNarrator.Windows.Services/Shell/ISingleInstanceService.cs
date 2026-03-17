namespace BugNarrator.Windows.Services.Shell;

public interface ISingleInstanceService : IDisposable
{
    bool TryAcquirePrimaryInstance();
    void SignalPrimaryInstance();
    void StartFocusRequestPump(Action onFocusRequested, CancellationToken cancellationToken = default);
}
