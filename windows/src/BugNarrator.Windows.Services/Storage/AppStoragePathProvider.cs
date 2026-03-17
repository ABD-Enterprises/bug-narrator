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

        Directory.CreateDirectory(rootDirectory);
        Directory.CreateDirectory(sessionsDirectory);
        Directory.CreateDirectory(logsDirectory);

        return new AppStoragePaths(rootDirectory, sessionsDirectory, logsDirectory);
    }
}
