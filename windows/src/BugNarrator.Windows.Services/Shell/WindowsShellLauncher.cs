using System.Diagnostics;
using BugNarrator.Windows.Services.Diagnostics;

namespace BugNarrator.Windows.Services.Shell;

public sealed class WindowsShellLauncher : IWindowsShellLauncher
{
    private readonly WindowsDiagnostics diagnostics;

    public WindowsShellLauncher(WindowsDiagnostics diagnostics)
    {
        this.diagnostics = diagnostics;
    }

    public void OpenPath(string path, string label)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            throw new InvalidOperationException($"BugNarrator could not open {label} because no path was provided.");
        }

        var fullPath = Path.GetFullPath(path);
        if (!File.Exists(fullPath) && !Directory.Exists(fullPath))
        {
            throw new InvalidOperationException($"BugNarrator could not find {label} at {fullPath}.");
        }

        OpenTarget(fullPath, label);
    }

    public void OpenUri(Uri uri, string label)
    {
        if (!uri.IsAbsoluteUri)
        {
            throw new InvalidOperationException($"BugNarrator could not open {label} because the destination was invalid.");
        }

        OpenTarget(uri.AbsoluteUri, label);
    }

    private void OpenTarget(string target, string label)
    {
        try
        {
            Process.Start(new ProcessStartInfo(target)
            {
                UseShellExecute = true,
            });
            diagnostics.Info("shell", $"opened {label}: {target}");
        }
        catch (Exception exception)
        {
            diagnostics.Error("shell", $"failed to open {label}", exception);
            throw new InvalidOperationException($"BugNarrator could not open {label}.", exception);
        }
    }
}
