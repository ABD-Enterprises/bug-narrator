using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace BugNarrator.Windows.Views;

public sealed class SessionLibraryWindow : PlaceholderWindowBase
{
    public SessionLibraryWindow()
        : base(
            title: "BugNarrator Session Library",
            heading: "Session Library",
            description: "This placeholder window reserves the main review surface for transcript, screenshots, issues, and summary work in later milestones.",
            content: BuildContent(),
            width: 860,
            height: 520)
    {
    }

    private static UIElement BuildContent()
    {
        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(220) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(16) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

        var sidebar = BuildPanel("Filters", "Today\nYesterday\nLast 7 Days\nAll Sessions");
        var detail = BuildPanel("Review Workspace", "Transcript\nScreenshots\nExtracted Issues\nSummary");

        Grid.SetColumn(sidebar, 0);
        Grid.SetColumn(detail, 2);

        grid.Children.Add(sidebar);
        grid.Children.Add(detail);
        return grid;
    }

    private static Border BuildPanel(string heading, string body)
    {
        return new Border
        {
            BorderBrush = Brushes.LightGray,
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(8),
            Padding = new Thickness(16),
            Child = new StackPanel
            {
                Children =
                {
                    new TextBlock
                    {
                        FontSize = 18,
                        FontWeight = FontWeights.SemiBold,
                        Text = heading,
                    },
                    new TextBlock
                    {
                        Margin = new Thickness(0, 12, 0, 0),
                        Text = body,
                        TextWrapping = TextWrapping.Wrap,
                    },
                },
            },
        };
    }
}
