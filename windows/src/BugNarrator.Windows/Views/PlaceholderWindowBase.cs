using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace BugNarrator.Windows.Views;

public abstract class PlaceholderWindowBase : Window
{
    protected PlaceholderWindowBase(
        string title,
        string heading,
        string description,
        UIElement content,
        double width,
        double height)
    {
        Title = title;
        Width = width;
        Height = height;
        MinWidth = Math.Min(width, 360);
        MinHeight = Math.Min(height, 220);
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Background = Brushes.White;

        Content = new Border
        {
            Padding = new Thickness(24),
            Child = new StackPanel
            {
                Children =
                {
                    new TextBlock
                    {
                        FontSize = 28,
                        FontWeight = FontWeights.Bold,
                        Text = heading,
                    },
                    new TextBlock
                    {
                        Margin = new Thickness(0, 12, 0, 0),
                        Text = description,
                        TextWrapping = TextWrapping.Wrap,
                    },
                    new TextBlock
                    {
                        Margin = new Thickness(0, 16, 0, 0),
                        Foreground = Brushes.DimGray,
                        Text = "Source-of-truth docs: windows/docs/WINDOWS_IMPLEMENTATION_ROADMAP.md and docs/CROSS_PLATFORM_GUIDELINES.md",
                        TextWrapping = TextWrapping.Wrap,
                    },
                    new Border
                    {
                        Margin = new Thickness(0, 24, 0, 0),
                        Padding = new Thickness(0),
                        Child = content,
                    },
                },
            },
        };
    }
}
