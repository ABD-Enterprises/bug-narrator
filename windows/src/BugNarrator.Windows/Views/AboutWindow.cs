using BugNarrator.Windows.Services.Shell;
using System.Windows;
using System.Windows.Controls;

namespace BugNarrator.Windows.Views;

public sealed class AboutWindow : PlaceholderWindowBase
{
    public AboutWindow()
        : base(
            title: "About SureForge Capture",
            heading: "About SureForge Capture",
            description: "Turn narrated testing into clear, actionable findings.",
            content: BuildContent(),
            width: 480,
            height: 340)
    {
    }

    private static UIElement BuildContent()
    {
        return new StackPanel
        {
            Children =
            {
                new TextBlock
                {
                    Text = "Record your narration and capture screenshots. Review the evidence, refine draft issues, and export your findings.",
                    TextWrapping = TextWrapping.Wrap,
                },
                new TextBlock
                {
                    Margin = new Thickness(0, 12, 0, 0),
                    Text = $"Version {ReleaseUpdateChecker.CurrentVersion()} · Windows",
                    TextWrapping = TextWrapping.Wrap,
                },
                new TextBlock
                {
                    Margin = new Thickness(0, 12, 0, 0),
                    Text = "Sessions stay on this PC. Audio and transcripts are sent to your selected AI provider only when you use its features. GitHub and Jira export are experimental.",
                    TextWrapping = TextWrapping.Wrap,
                },
            },
        };
    }
}
