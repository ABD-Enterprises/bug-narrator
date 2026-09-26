using System.Reflection;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Media;
using BugNarrator.Windows.Services.Diagnostics;
using BugNarrator.Windows.Services.Review;
using BugNarrator.Windows.Services.Shell;

namespace BugNarrator.Windows.Views;

public sealed class AboutWindow : Window
{
    private readonly WindowsDiagnostics diagnostics;
    private readonly IReviewSessionActionService reviewSessionActionService;
    private readonly IWindowsShellLauncher shellLauncher;
    private readonly TextBlock statusTextBlock;

    public AboutWindow(
        IReviewSessionActionService reviewSessionActionService,
        IWindowsShellLauncher shellLauncher,
        WindowsDiagnostics diagnostics)
    {
        this.reviewSessionActionService = reviewSessionActionService;
        this.shellLauncher = shellLauncher;
        this.diagnostics = diagnostics;

        Title = "BugNarrator Help And Support";
        Width = 760;
        Height = 680;
        MinWidth = 640;
        MinHeight = 560;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Background = Brushes.White;

        statusTextBlock = new TextBlock
        {
            Margin = new Thickness(0, 16, 0, 0),
            Foreground = Brushes.DimGray,
            Text = "Open docs, release notes, or support actions from here.",
            TextWrapping = TextWrapping.Wrap,
        };
        AutomationProperties.SetName(statusTextBlock, "Help and support status");
        AutomationProperties.SetLiveSetting(statusTextBlock, AutomationLiveSetting.Polite);

        Content = new ScrollViewer
        {
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            Content = new StackPanel
            {
                Margin = new Thickness(24),
                Children =
                {
                    BuildHeader(),
                    BuildOverviewCard(),
                    BuildProjectLinksCard(),
                    BuildSupportCard(),
                    statusTextBlock,
                },
            },
        };
    }

    private UIElement BuildHeader()
    {
        return new Border
        {
            Padding = new Thickness(20),
            BorderBrush = Brushes.LightGray,
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(16),
            Child = new StackPanel
            {
                Children =
                {
                    new TextBlock
                    {
                        FontSize = 30,
                        FontWeight = FontWeights.Bold,
                        Text = "BugNarrator",
                    },
                    new TextBlock
                    {
                        Margin = new Thickness(0, 10, 0, 0),
                        Foreground = Brushes.DimGray,
                        Text = "Narrated software testing for record -> review -> refine -> export.",
                        TextWrapping = TextWrapping.Wrap,
                    },
                    new TextBlock
                    {
                        Margin = new Thickness(0, 12, 0, 0),
                        Text = $"Windows parity build  |  {GetVersionLabel()}",
                        FontWeight = FontWeights.SemiBold,
                    },
                },
            },
        };
    }

    private UIElement BuildOverviewCard()
    {
        return BuildCard(
            "Product Overview",
            "BugNarrator on Windows now supports the core recording, screenshot, review, hotkey, and export workflow. GitHub and Jira export remain experimental, and public Windows release work is still tracked separately.",
            new StackPanel
            {
                Children =
                {
                    BuildBodyText("Use Recording Controls for live capture. Use Session Library for transcript review, generated summary, extracted issues, bundles, and exports."),
                    BuildBodyText("This support surface gives you the same kind of entry points the macOS app already exposes: docs, issue reporting, release notes, updates, and safe diagnostics export."),
                },
            });
    }

    private UIElement BuildProjectLinksCard()
    {
        return BuildCard(
            "Project Links",
            "Documentation, release notes, reporting, and update paths.",
            new StackPanel
            {
                Children =
                {
                    BuildActionButton(
                        "Documentation",
                        "Open the hosted user guide and troubleshooting notes.",
                        () => OpenUri(BugNarratorWindowsLinks.Documentation, "documentation")),
                    BuildActionButton(
                        "View Changelog",
                        "Open the latest project changelog on GitHub.",
                        () => OpenUri(BugNarratorWindowsLinks.Changelog, "changelog")),
                    BuildActionButton(
                        "Report A Bug Or Feature Request",
                        "Open the GitHub issue form for support and product feedback.",
                        () => OpenUri(BugNarratorWindowsLinks.Issues, "issue tracker")),
                    BuildActionButton(
                        "Check For Updates",
                        "Open the latest BugNarrator release page for Windows and macOS builds.",
                        () => OpenUri(BugNarratorWindowsLinks.Releases, "release page")),
                    BuildActionButton(
                        "GitHub Repository",
                        "Open the main BugNarrator repository, roadmap, and release history.",
                        () => OpenUri(BugNarratorWindowsLinks.Repository, "GitHub repository")),
                },
            });
    }

    private UIElement BuildSupportCard()
    {
        return BuildCard(
            "Help And Support",
            "Support-development and diagnostics actions live here instead of staying hidden in the session library.",
            new StackPanel
            {
                Children =
                {
                    BuildActionButton(
                        "Export Debug Bundle",
                        "Create a local diagnostics bundle without exposing API keys or tokens.",
                        ExportDebugBundleAsync,
                        isPrimary: true),
                    BuildActionButton(
                        "Support Development",
                        "Open the PayPal support page if BugNarrator is useful in your workflow.",
                        () => OpenUri(BugNarratorWindowsLinks.SupportDevelopment, "support development page")),
                    BuildBodyText("Experimental integrations: GitHub and Jira export are available, but they should still be treated as experimental on Windows."),
                },
            });
    }

    private Border BuildCard(string title, string description, UIElement content)
    {
        return new Border
        {
            Margin = new Thickness(0, 18, 0, 0),
            Padding = new Thickness(18),
            BorderBrush = Brushes.LightGray,
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(14),
            Child = new StackPanel
            {
                Children =
                {
                    new TextBlock
                    {
                        FontSize = 22,
                        FontWeight = FontWeights.SemiBold,
                        Text = title,
                    },
                    new TextBlock
                    {
                        Margin = new Thickness(0, 8, 0, 0),
                        Foreground = Brushes.DimGray,
                        Text = description,
                        TextWrapping = TextWrapping.Wrap,
                    },
                    new Border
                    {
                        Margin = new Thickness(0, 16, 0, 0),
                        Child = content,
                    },
                },
            },
        };
    }

    private Button BuildActionButton(
        string title,
        string description,
        Action action,
        bool isPrimary = false)
    {
        var button = new Button
        {
            Margin = new Thickness(0, 0, 0, 12),
            Padding = new Thickness(14, 12, 14, 12),
            HorizontalContentAlignment = HorizontalAlignment.Left,
            Background = isPrimary ? Brushes.Black : Brushes.WhiteSmoke,
            Foreground = isPrimary ? Brushes.White : Brushes.Black,
            BorderBrush = Brushes.LightGray,
            BorderThickness = new Thickness(1),
            Content = new StackPanel
            {
                Children =
                {
                    new TextBlock
                    {
                        FontWeight = FontWeights.SemiBold,
                        Text = title,
                    },
                    new TextBlock
                    {
                        Margin = new Thickness(0, 4, 0, 0),
                        Foreground = isPrimary ? Brushes.WhiteSmoke : Brushes.DimGray,
                        Text = description,
                        TextWrapping = TextWrapping.Wrap,
                    },
                },
            },
        };

        button.Click += (_, _) => action();
        return button;
    }

    private TextBlock BuildBodyText(string text)
    {
        return new TextBlock
        {
            Margin = new Thickness(0, 0, 0, 12),
            Foreground = Brushes.DimGray,
            Text = text,
            TextWrapping = TextWrapping.Wrap,
        };
    }

    private async void ExportDebugBundleAsync()
    {
        try
        {
            statusTextBlock.Text = "Exporting debug bundle...";
            var bundlePath = await reviewSessionActionService.ExportDebugBundleAsync(session: null);
            diagnostics.Info("support", $"debug bundle exported from Help And Support: {bundlePath}");
            statusTextBlock.Text = $"Debug bundle exported to {bundlePath}";
        }
        catch (Exception exception)
        {
            diagnostics.Error("support", "debug bundle export from Help And Support failed", exception);
            statusTextBlock.Text = exception.Message;
        }
    }

    private void OpenUri(Uri uri, string label)
    {
        try
        {
            shellLauncher.OpenUri(uri, label);
            statusTextBlock.Text = $"Opened {label}.";
        }
        catch (Exception exception)
        {
            statusTextBlock.Text = exception.Message;
        }
    }

    private static string GetVersionLabel()
    {
        var assembly = typeof(AboutWindow).Assembly;
        var informationalVersion = assembly
            .GetCustomAttribute<AssemblyInformationalVersionAttribute>()
            ?.InformationalVersion;
        if (!string.IsNullOrWhiteSpace(informationalVersion))
        {
            return informationalVersion.Trim();
        }

        return assembly.GetName().Version?.ToString() ?? "development";
    }
}
