namespace BugNarrator.Windows.Services.Shell;

public interface IWindowsShellLauncher
{
    void OpenPath(string path, string label);
    void OpenUri(Uri uri, string label);
}
