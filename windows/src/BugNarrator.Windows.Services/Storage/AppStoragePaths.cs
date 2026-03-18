namespace BugNarrator.Windows.Services.Storage;

public sealed record AppStoragePaths(
    string RootDirectory,
    string SessionsDirectory,
    string LogsDirectory
)
{
    public string SecretsDirectory => Path.Combine(RootDirectory, "Secrets");
    public string SettingsFilePath => Path.Combine(RootDirectory, "settings.json");
    public string ExportsDirectory => Path.Combine(RootDirectory, "Exports");
    public string SessionBundlesDirectory => Path.Combine(ExportsDirectory, "SessionBundles");
    public string DebugBundlesDirectory => Path.Combine(ExportsDirectory, "DebugBundles");
}
