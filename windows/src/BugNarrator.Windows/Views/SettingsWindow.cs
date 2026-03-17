using System.Windows;
using System.Windows.Controls;

namespace BugNarrator.Windows.Views;

public sealed class SettingsWindow : PlaceholderWindowBase
{
    public SettingsWindow()
        : base(
            title: "BugNarrator Settings",
            heading: "Settings",
            description: "Settings are scaffolded as a dedicated window so future Windows work can add API key, export, and optional hotkey configuration without changing the shell structure.",
            content: BuildContent(),
            width: 520,
            height: 360)
    {
    }

    private static UIElement BuildContent()
    {
        return new StackPanel
        {
            Children =
            {
                BuildLabel("OpenAI API Key"),
                BuildPlaceholderBox("Configured later"),
                BuildLabel("Experimental Exports"),
                BuildPlaceholderBox("GitHub and Jira remain experimental"),
                BuildLabel("Optional Hotkeys"),
                BuildPlaceholderBox("Disabled by default until explicitly assigned"),
            },
        };
    }

    private static TextBlock BuildLabel(string text)
    {
        return new TextBlock
        {
            Margin = new Thickness(0, 0, 0, 6),
            FontWeight = FontWeights.SemiBold,
            Text = text,
        };
    }

    private static TextBox BuildPlaceholderBox(string text)
    {
        return new TextBox
        {
            Margin = new Thickness(0, 0, 0, 12),
            IsReadOnly = true,
            Text = text,
        };
    }
}
