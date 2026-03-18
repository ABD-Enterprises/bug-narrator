using BugNarrator.Core.Diagnostics;
using BugNarrator.Windows.Services.Storage;

namespace BugNarrator.Windows.Services.Diagnostics;

public sealed class WindowsDiagnostics
{
    private readonly object syncRoot = new();
    private readonly string logFilePath;

    public WindowsDiagnostics(AppStoragePaths storagePaths)
    {
        Directory.CreateDirectory(storagePaths.LogsDirectory);
        logFilePath = Path.Combine(storagePaths.LogsDirectory, "windows-shell.log");
    }

    public string LogFilePath => logFilePath;

    public DiagnosticEvent CreateEvent(string category, string message)
    {
        return new DiagnosticEvent(category, message, DateTimeOffset.UtcNow);
    }

    public void Info(string category, string message)
    {
        Write("INFO", category, message);
    }

    public void Warning(string category, string message)
    {
        Write("WARN", category, message);
    }

    public void Error(string category, string message, Exception? exception = null)
    {
        var fullMessage = exception is null
            ? message
            : $"{message}{Environment.NewLine}{exception}";
        Write("ERROR", category, fullMessage);
    }

    private void Write(string level, string category, string message)
    {
        var sanitizedMessage = SensitiveDataRedactor.Redact(message);
        var logLine = $"{DateTimeOffset.UtcNow:O} [{level}] [{category}] {sanitizedMessage}{Environment.NewLine}";
        lock (syncRoot)
        {
            File.AppendAllText(logFilePath, logLine);
        }
    }
}
