using System.Diagnostics;

namespace BugNarrator.Windows.Services.Shell;

public interface IExternalLinkLauncher
{
    /// <summary>Opens <paramref name="url"/> in the user's default browser; throws if the shell refuses.</summary>
    void Open(string url);
}

/// <summary>The real launcher: hands the URL to the shell, which picks the default browser.</summary>
public sealed class ShellExternalLinkLauncher : IExternalLinkLauncher
{
    public void Open(string url)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(url);
        if (!Uri.TryCreate(url, UriKind.Absolute, out var uri) || (uri.Scheme != Uri.UriSchemeHttps && uri.Scheme != Uri.UriSchemeHttp))
        {
            throw new InvalidOperationException($"Refusing to open a non-web link: {url}");
        }

        Process.Start(new ProcessStartInfo(uri.AbsoluteUri) { UseShellExecute = true });
    }
}
