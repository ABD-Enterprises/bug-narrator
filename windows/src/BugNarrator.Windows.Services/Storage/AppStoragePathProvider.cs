namespace BugNarrator.Windows.Services.Storage;

public static class AppStoragePathProvider
{
    public static AppStoragePaths CreateDefault()
    {
        var rootDirectory = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "BugNarrator");
        var sessionsDirectory = Path.Combine(rootDirectory, "Sessions");
        var logsDirectory = Path.Combine(rootDirectory, "Logs");
        var exportsDirectory = Path.Combine(rootDirectory, "Exports");
        var sessionBundlesDirectory = Path.Combine(exportsDirectory, "SessionBundles");
        var debugBundlesDirectory = Path.Combine(exportsDirectory, "DebugBundles");

        Directory.CreateDirectory(rootDirectory);
        Directory.CreateDirectory(sessionsDirectory);
        Directory.CreateDirectory(logsDirectory);
        Directory.CreateDirectory(exportsDirectory);
        Directory.CreateDirectory(sessionBundlesDirectory);
        Directory.CreateDirectory(debugBundlesDirectory);

        return new AppStoragePaths(rootDirectory, sessionsDirectory, logsDirectory);
    }
}
