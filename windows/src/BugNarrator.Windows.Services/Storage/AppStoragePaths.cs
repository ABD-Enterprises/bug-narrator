namespace BugNarrator.Windows.Services.Storage;

public sealed record AppStoragePaths(
    string RootDirectory,
    string SessionsDirectory,
    string LogsDirectory
);
