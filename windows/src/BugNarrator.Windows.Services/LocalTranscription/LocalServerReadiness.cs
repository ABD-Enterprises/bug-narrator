using BugNarrator.Windows.Services.Settings;

namespace BugNarrator.Windows.Services.LocalTranscription;

public static class LocalServerReadiness
{
    /// <summary>Require a fresh health and identity proof before using the local Parakeet provider.</summary>
    public static Task<bool> IsReadyAsync(
        WindowsAppSettings settings,
        ILocalServerHealthProbe probe,
        CancellationToken cancellationToken = default)
    {
        return settings.UsesLocalTranscriptionServer
            ? probe.IsReachableAsync(settings.EffectiveAiProviderBaseUrl!, cancellationToken)
            : Task.FromResult(true);
    }
}
