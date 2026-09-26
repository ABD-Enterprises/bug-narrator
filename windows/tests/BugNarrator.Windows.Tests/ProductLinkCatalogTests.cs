using BugNarrator.Windows.Services.Shell;
using Xunit;

namespace BugNarrator.Windows.Tests;

public sealed class ProductLinkCatalogTests
{
    [Fact]
    public void BugNarratorWindowsLinks_UseAbsoluteHttpsUris()
    {
        var links = new[]
        {
            BugNarratorWindowsLinks.Repository,
            BugNarratorWindowsLinks.Documentation,
            BugNarratorWindowsLinks.Changelog,
            BugNarratorWindowsLinks.Issues,
            BugNarratorWindowsLinks.Releases,
            BugNarratorWindowsLinks.SupportDevelopment,
        };

        Assert.All(links, link =>
        {
            Assert.True(link.IsAbsoluteUri);
            Assert.Equal(Uri.UriSchemeHttps, link.Scheme);
        });
    }

    [Fact]
    public void WindowsSettingsLinks_UseAbsoluteMsSettingsUris()
    {
        var links = new[]
        {
            WindowsSettingsLinks.MicrophonePrivacy,
            WindowsSettingsLinks.Sound,
        };

        Assert.All(links, link =>
        {
            Assert.True(link.IsAbsoluteUri);
            Assert.Equal("ms-settings", link.Scheme);
        });
    }
}
