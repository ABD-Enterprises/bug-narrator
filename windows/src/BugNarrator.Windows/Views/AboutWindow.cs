using System.Windows;
using System.Windows.Controls;

namespace BugNarrator.Windows.Views;

public sealed class AboutWindow : PlaceholderWindowBase
{
    public AboutWindow()
        : base(
            title: "About BugNarrator",
            heading: "About BugNarrator",
            description: "This Windows shell keeps the same product direction as the native macOS app while accepting phased parity between platforms.",
            content: BuildContent(),
            width: 480,
            height: 300)
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
                    Text = "Workflow target: record -> review -> refine -> export",
                    TextWrapping = TextWrapping.Wrap,
                },
                new TextBlock
                {
                    Margin = new Thickness(0, 12, 0, 0),
                    Text = "Platform: Windows WPF shell placeholder",
                    TextWrapping = TextWrapping.Wrap,
                },
                new TextBlock
                {
                    Margin = new Thickness(0, 12, 0, 0),
                    Text = "GitHub and Jira export remain experimental.",
                    TextWrapping = TextWrapping.Wrap,
                },
            },
        };
    }
}
