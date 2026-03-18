using BugNarrator.Core.Models;
using BugNarrator.Core.Workflow;
using BugNarrator.Windows.Services.Diagnostics;
using BugNarrator.Windows.Services.Review;
using BugNarrator.Windows.Services.Storage;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace BugNarrator.Windows.Views;

public sealed class SessionLibraryWindow : Window
{
    private readonly ICompletedSessionStore completedSessionStore;
    private readonly TextBlock customDateRangeStatusTextBlock;
    private readonly StackPanel customDateRangePanel;
    private readonly DatePicker customEndDatePicker;
    private readonly DatePicker customStartDatePicker;
    private readonly ComboBox dateRangeComboBox;
    private readonly Button deleteSessionButton;
    private readonly WindowsDiagnostics diagnostics;
    private readonly TextBlock emptyStateTextBlock;
    private readonly Button exportBundleButton;
    private readonly Button exportDebugBundleButton;
    private readonly Button exportGitHubButton;
    private readonly Button exportJiraButton;
    private readonly Button extractIssuesButton;
    private readonly StackPanel issueEditorsPanel;
    private readonly TextBlock issuesEmptyStateTextBlock;
    private readonly TextBlock issuesGuidanceTextBlock;
    private readonly TextBlock issuesStatusTextBlock;
    private readonly TextBlock issuesSummaryTextBlock;
    private readonly TextBlock libraryStatusTextBlock;
    private readonly IReviewSessionActionService reviewSessionActionService;
    private readonly Button saveReviewButton;
    private readonly Image screenshotPreviewImage;
    private readonly TextBlock screenshotPreviewTextBlock;
    private readonly ListBox screenshotListBox;
    private readonly TextBox searchTextBox;
    private readonly ListBox sessionListBox;
    private readonly ComboBox sortOrderComboBox;
    private readonly TextBlock summaryHeaderTextBlock;
    private readonly TextBox summaryTextBox;
    private readonly TextBlock transcriptHeaderTextBlock;
    private readonly TextBox transcriptTextBox;

    private IReadOnlyList<CompletedSession> allSessions = Array.Empty<CompletedSession>();
    private bool hasResolvedInitialDateRange;
    private bool isRefreshing;
    private bool isRunningReviewAction;
    private List<IssueEditorRow> issueEditors = [];
    private CompletedSession? selectedSession;

    public SessionLibraryWindow(
        ICompletedSessionStore completedSessionStore,
        IReviewSessionActionService reviewSessionActionService,
        WindowsDiagnostics diagnostics)
    {
        this.completedSessionStore = completedSessionStore;
        this.reviewSessionActionService = reviewSessionActionService;
        this.diagnostics = diagnostics;

        Title = "BugNarrator Session Library";
        Width = 1180;
        Height = 760;
        MinWidth = 980;
        MinHeight = 640;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Background = Brushes.White;

        dateRangeComboBox = new ComboBox
        {
            Margin = new Thickness(0, 0, 0, 10),
        };
        AddComboBoxOption(dateRangeComboBox, SessionLibraryDateRange.Today, "Today");
        AddComboBoxOption(dateRangeComboBox, SessionLibraryDateRange.Yesterday, "Yesterday");
        AddComboBoxOption(dateRangeComboBox, SessionLibraryDateRange.Last7Days, "Last 7 Days");
        AddComboBoxOption(dateRangeComboBox, SessionLibraryDateRange.Last30Days, "Last 30 Days");
        AddComboBoxOption(dateRangeComboBox, SessionLibraryDateRange.All, "All Sessions");
        AddComboBoxOption(dateRangeComboBox, SessionLibraryDateRange.CustomRange, "Custom Date Range");
        SetSelectedComboBoxValue(dateRangeComboBox, SessionLibraryDateRange.Today);
        dateRangeComboBox.SelectionChanged += (_, _) =>
        {
            UpdateCustomDateRangeVisibility();
            ApplyCurrentQuery();
        };

        customStartDatePicker = new DatePicker
        {
            Margin = new Thickness(0, 0, 0, 8),
            SelectedDate = DateTime.Today.AddDays(-6),
        };
        customStartDatePicker.SelectedDateChanged += OnCustomDateRangeChanged;

        customEndDatePicker = new DatePicker
        {
            Margin = new Thickness(0, 0, 0, 8),
            SelectedDate = DateTime.Today,
        };
        customEndDatePicker.SelectedDateChanged += OnCustomDateRangeChanged;

        customDateRangeStatusTextBlock = new TextBlock
        {
            Foreground = Brushes.DimGray,
            TextWrapping = TextWrapping.Wrap,
        };

        customDateRangePanel = new StackPanel
        {
            Margin = new Thickness(0, 0, 0, 10),
            Visibility = Visibility.Collapsed,
            Children =
            {
                BuildLabel("Custom Range"),
                customStartDatePicker,
                customEndDatePicker,
                customDateRangeStatusTextBlock,
            },
        };

        sortOrderComboBox = new ComboBox
        {
            Margin = new Thickness(0, 0, 0, 10),
        };
        AddComboBoxOption(sortOrderComboBox, SessionLibrarySortOrder.NewestFirst, "Newest First");
        AddComboBoxOption(sortOrderComboBox, SessionLibrarySortOrder.OldestFirst, "Oldest First");
        SetSelectedComboBoxValue(sortOrderComboBox, SessionLibrarySortOrder.NewestFirst);
        sortOrderComboBox.SelectionChanged += (_, _) => ApplyCurrentQuery();

        searchTextBox = new TextBox
        {
            Margin = new Thickness(0, 0, 0, 10),
        };
        searchTextBox.TextChanged += (_, _) => ApplyCurrentQuery();

        libraryStatusTextBlock = new TextBlock
        {
            Margin = new Thickness(0, 0, 0, 10),
            Foreground = Brushes.DimGray,
            TextWrapping = TextWrapping.Wrap,
        };

        sessionListBox = new ListBox
        {
            MinHeight = 320,
        };
        sessionListBox.SelectionChanged += OnSessionSelectionChanged;

        deleteSessionButton = new Button
        {
            Content = "Delete Session",
            Height = 34,
            Margin = new Thickness(0, 14, 0, 0),
        };
        deleteSessionButton.Click += async (_, _) => await DeleteSelectedSessionAsync();

        emptyStateTextBlock = new TextBlock
        {
            Margin = new Thickness(0, 12, 0, 0),
            Foreground = Brushes.DimGray,
            Text = "No completed review sessions yet. Stop a recording to create one.",
            TextWrapping = TextWrapping.Wrap,
        };

        transcriptHeaderTextBlock = new TextBlock
        {
            Margin = new Thickness(0, 0, 0, 8),
            FontWeight = FontWeights.SemiBold,
            Text = "Transcript unavailable until you select a session.",
            TextWrapping = TextWrapping.Wrap,
        };

        transcriptTextBox = new TextBox
        {
            AcceptsReturn = true,
            IsReadOnly = true,
            TextWrapping = TextWrapping.Wrap,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
        };

        screenshotListBox = new ListBox
        {
            MinWidth = 260,
        };
        screenshotListBox.SelectionChanged += OnScreenshotSelectionChanged;

        screenshotPreviewTextBlock = new TextBlock
        {
            Foreground = Brushes.DimGray,
            Text = "Select a screenshot to preview it here.",
            TextWrapping = TextWrapping.Wrap,
        };

        screenshotPreviewImage = new Image
        {
            Margin = new Thickness(0, 12, 0, 0),
            Stretch = Stretch.Uniform,
            MaxHeight = 380,
        };

        extractIssuesButton = BuildActionButton("Extract Issues");
        extractIssuesButton.Click += async (_, _) => await RunReviewActionAsync(
            "Extracting draft issues with OpenAI...",
            ExtractIssuesAsync);

        saveReviewButton = BuildActionButton("Save Review");
        saveReviewButton.Click += async (_, _) => await RunReviewActionAsync(
            "Saving review edits...",
            SaveReviewAsync);

        exportBundleButton = BuildActionButton("Export Session Bundle");
        exportBundleButton.Click += async (_, _) => await RunReviewActionAsync(
            "Exporting the local session bundle...",
            ExportSessionBundleAsync);

        exportDebugBundleButton = BuildActionButton("Export Debug Bundle");
        exportDebugBundleButton.Click += async (_, _) => await RunReviewActionAsync(
            "Exporting the local debug bundle...",
            ExportDebugBundleAsync);

        exportGitHubButton = BuildActionButton("Export To GitHub (Experimental)");
        exportGitHubButton.Click += async (_, _) => await RunReviewActionAsync(
            "Exporting selected issues to GitHub...",
            ExportSelectedIssuesToGitHubAsync);

        exportJiraButton = BuildActionButton("Export To Jira (Experimental)");
        exportJiraButton.Click += async (_, _) => await RunReviewActionAsync(
            "Exporting selected issues to Jira...",
            ExportSelectedIssuesToJiraAsync);

        issuesSummaryTextBlock = new TextBlock
        {
            FontWeight = FontWeights.SemiBold,
            TextWrapping = TextWrapping.Wrap,
        };

        issuesGuidanceTextBlock = new TextBlock
        {
            Margin = new Thickness(0, 8, 0, 12),
            Foreground = Brushes.DimGray,
            TextWrapping = TextWrapping.Wrap,
        };

        issuesStatusTextBlock = new TextBlock
        {
            Margin = new Thickness(0, 12, 0, 12),
            Foreground = Brushes.DimGray,
            TextWrapping = TextWrapping.Wrap,
            Text = "Select a saved session to extract issues, export bundles, or export selected issues.",
        };

        issuesEmptyStateTextBlock = new TextBlock
        {
            Foreground = Brushes.DimGray,
            TextWrapping = TextWrapping.Wrap,
        };

        issueEditorsPanel = new StackPanel();

        summaryHeaderTextBlock = new TextBlock
        {
            Margin = new Thickness(0, 0, 0, 8),
            FontWeight = FontWeights.SemiBold,
            Text = "Select a session to inspect its review summary.",
            TextWrapping = TextWrapping.Wrap,
        };

        summaryTextBox = new TextBox
        {
            AcceptsReturn = true,
            IsReadOnly = true,
            TextWrapping = TextWrapping.Wrap,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
        };

        Content = BuildWindowContent();
        UpdateCustomDateRangeVisibility();

        Loaded += async (_, _) => await RefreshSessionsAsync();
        Activated += async (_, _) => await RefreshSessionsAsync();
    }

    private UIElement BuildWindowContent()
    {
        var layoutGrid = new Grid
        {
            Margin = new Thickness(24),
        };
        layoutGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(320) });
        layoutGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(24) });
        layoutGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

        var refreshButton = new Button
        {
            Content = "Refresh",
            Margin = new Thickness(0, 14, 0, 0),
            Height = 34,
        };
        refreshButton.Click += async (_, _) => await RefreshSessionsAsync();

        var sidebar = new StackPanel
        {
            Children =
            {
                new TextBlock
                {
                    FontSize = 28,
                    FontWeight = FontWeights.Bold,
                    Text = "Session Library",
                },
                new TextBlock
                {
                    Margin = new Thickness(0, 12, 0, 0),
                    Text = "Windows now includes the Milestone 6 review loop plus a parity pass on the session library with richer date filters and permanent local session deletion.",
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
                    Margin = new Thickness(0, 20, 0, 0),
                    Padding = new Thickness(16),
                    BorderBrush = Brushes.LightGray,
                    BorderThickness = new Thickness(1),
                    CornerRadius = new CornerRadius(8),
                    Child = new StackPanel
                    {
                        Children =
                        {
                            BuildLabel("Filter"),
                            dateRangeComboBox,
                            customDateRangePanel,
                            BuildLabel("Sort"),
                            sortOrderComboBox,
                            BuildLabel("Search"),
                            searchTextBox,
                            libraryStatusTextBlock,
                            sessionListBox,
                            emptyStateTextBlock,
                            new WrapPanel
                            {
                                Children =
                                {
                                    refreshButton,
                                    deleteSessionButton,
                                },
                            },
                        },
                    },
                },
            },
        };

        var reviewTabs = new TabControl
        {
            Items =
            {
                new TabItem
                {
                    Header = "Transcript",
                    Content = new Border
                    {
                        Padding = new Thickness(16),
                        Child = new Grid
                        {
                            RowDefinitions =
                            {
                                new RowDefinition { Height = GridLength.Auto },
                                new RowDefinition { Height = new GridLength(1, GridUnitType.Star) },
                            },
                            Children =
                            {
                                transcriptHeaderTextBlock,
                                CreateRowChild(transcriptTextBox, 1),
                            },
                        },
                    },
                },
                new TabItem
                {
                    Header = "Screenshots",
                    Content = new Border
                    {
                        Padding = new Thickness(16),
                        Child = BuildScreenshotsTab(),
                    },
                },
                new TabItem
                {
                    Header = "Extracted Issues",
                    Content = new Border
                    {
                        Padding = new Thickness(16),
                        Child = BuildIssuesTab(),
                    },
                },
                new TabItem
                {
                    Header = "Summary",
                    Content = new Border
                    {
                        Padding = new Thickness(16),
                        Child = new Grid
                        {
                            RowDefinitions =
                            {
                                new RowDefinition { Height = GridLength.Auto },
                                new RowDefinition { Height = new GridLength(1, GridUnitType.Star) },
                            },
                            Children =
                            {
                                summaryHeaderTextBlock,
                                CreateRowChild(summaryTextBox, 1),
                            },
                        },
                    },
                },
            },
        };

        Grid.SetColumn(sidebar, 0);
        Grid.SetColumn(reviewTabs, 2);

        layoutGrid.Children.Add(sidebar);
        layoutGrid.Children.Add(reviewTabs);
        return layoutGrid;
    }

    private UIElement BuildScreenshotsTab()
    {
        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(280) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(20) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

        var previewPanel = new StackPanel
        {
            Children =
            {
                screenshotPreviewTextBlock,
                screenshotPreviewImage,
            },
        };

        Grid.SetColumn(screenshotListBox, 0);
        Grid.SetColumn(previewPanel, 2);

        grid.Children.Add(screenshotListBox);
        grid.Children.Add(previewPanel);
        return grid;
    }

    private UIElement BuildIssuesTab()
    {
        return new ScrollViewer
        {
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            Content = new StackPanel
            {
                Children =
                {
                    issuesSummaryTextBlock,
                    issuesGuidanceTextBlock,
                    new WrapPanel
                    {
                        Margin = new Thickness(0, 0, 0, 4),
                        Children =
                        {
                            extractIssuesButton,
                            saveReviewButton,
                            exportBundleButton,
                            exportDebugBundleButton,
                            exportGitHubButton,
                            exportJiraButton,
                        },
                    },
                    issuesStatusTextBlock,
                    issuesEmptyStateTextBlock,
                    issueEditorsPanel,
                },
            },
        };
    }

    private async Task RunReviewActionAsync(string workingMessage, Func<Task> action)
    {
        if (isRunningReviewAction)
        {
            return;
        }

        isRunningReviewAction = true;
        issuesStatusTextBlock.Text = workingMessage;
        ApplyActionButtonState();

        try
        {
            await action();
        }
        catch (Exception exception)
        {
            diagnostics.Error("session-library", "review action failed", exception);
            issuesStatusTextBlock.Text = exception.Message;
        }
        finally
        {
            isRunningReviewAction = false;
            ApplyActionButtonState();
        }
    }

    private async Task ExtractIssuesAsync()
    {
        var session = RequireSelectedSession();
        var editableSession = await PersistCurrentEditsAsync(session);
        var updatedSession = await reviewSessionActionService.ExtractIssuesAsync(editableSession);
        ReplaceSession(updatedSession);

        var issueCount = updatedSession.IssueExtraction?.Issues.Count ?? 0;
        issuesStatusTextBlock.Text =
            issueCount == 0
                ? "Issue extraction finished without any draft issues."
                : $"Issue extraction created {issueCount} draft issue(s). Review and adjust them before export.";
    }

    private async Task SaveReviewAsync()
    {
        var session = RequireSelectedSession();
        var updatedSession = await PersistCurrentEditsAsync(session);
        ReplaceSession(updatedSession);
        issuesStatusTextBlock.Text = "Review edits saved to the local session metadata.";
    }

    private async Task ExportSessionBundleAsync()
    {
        var session = RequireSelectedSession();
        var updatedSession = await PersistCurrentEditsAsync(session);
        var bundlePath = await reviewSessionActionService.ExportSessionBundleAsync(updatedSession);
        issuesStatusTextBlock.Text = $"Session bundle exported to {bundlePath}";
    }

    private async Task ExportDebugBundleAsync()
    {
        var session = RequireSelectedSession();
        var updatedSession = await PersistCurrentEditsAsync(session);
        var bundlePath = await reviewSessionActionService.ExportDebugBundleAsync(updatedSession);
        issuesStatusTextBlock.Text = $"Debug bundle exported to {bundlePath}";
    }

    private async Task ExportSelectedIssuesToGitHubAsync()
    {
        var session = RequireSelectedSession();
        var updatedSession = await PersistCurrentEditsAsync(session);
        var results = await reviewSessionActionService.ExportSelectedIssuesToGitHubAsync(updatedSession);
        issuesStatusTextBlock.Text = BuildExportStatusMessage("GitHub", results);
    }

    private async Task ExportSelectedIssuesToJiraAsync()
    {
        var session = RequireSelectedSession();
        var updatedSession = await PersistCurrentEditsAsync(session);
        var results = await reviewSessionActionService.ExportSelectedIssuesToJiraAsync(updatedSession);
        issuesStatusTextBlock.Text = BuildExportStatusMessage("Jira", results);
    }

    private async Task<CompletedSession> PersistCurrentEditsAsync(CompletedSession session)
    {
        var editedSession = BuildEditedSessionSnapshot(session);
        var savedSession = await reviewSessionActionService.SaveSessionAsync(editedSession);
        ReplaceSession(savedSession);
        return savedSession;
    }

    private CompletedSession BuildEditedSessionSnapshot(CompletedSession session)
    {
        if (session.IssueExtraction is null)
        {
            return session;
        }

        var updatedIssues = issueEditors.Select(editor => editor.BuildIssue()).ToArray();
        return session with
        {
            IssueExtraction = session.IssueExtraction with
            {
                Issues = updatedIssues,
            },
        };
    }

    private CompletedSession RequireSelectedSession()
    {
        return selectedSession
               ?? throw new InvalidOperationException("Select a saved session before running this action.");
    }

    private void ReplaceSession(CompletedSession updatedSession)
    {
        allSessions = allSessions
            .Select(session => session.SessionId == updatedSession.SessionId ? updatedSession : session)
            .ToArray();
        selectedSession = updatedSession;
        ApplyCurrentQuery();
    }

    private void ApplyActionButtonState()
    {
        var hasSession = selectedSession is not null;
        var hasTranscript = hasSession && !string.IsNullOrWhiteSpace(selectedSession!.TranscriptText);
        var hasExtraction = selectedSession?.IssueExtraction is not null;
        var selectedIssueCount = issueEditors.Count > 0
            ? issueEditors.Count(editor => editor.IsSelectedForExport)
            : selectedSession?.IssueExtraction?.SelectedIssues.Count ?? 0;

        extractIssuesButton.IsEnabled = hasSession && hasTranscript && !isRunningReviewAction;
        saveReviewButton.IsEnabled = hasExtraction && !isRunningReviewAction;
        exportBundleButton.IsEnabled = hasSession && !isRunningReviewAction;
        exportDebugBundleButton.IsEnabled = hasSession && !isRunningReviewAction;
        exportGitHubButton.IsEnabled = hasExtraction && selectedIssueCount > 0 && !isRunningReviewAction;
        exportJiraButton.IsEnabled = hasExtraction && selectedIssueCount > 0 && !isRunningReviewAction;
        deleteSessionButton.IsEnabled = hasSession && !isRunningReviewAction && !isRefreshing;
    }

    private async Task RefreshSessionsAsync()
    {
        if (isRefreshing || isRunningReviewAction)
        {
            return;
        }

        isRefreshing = true;
        libraryStatusTextBlock.Text = "Loading saved review sessions...";

        try
        {
            allSessions = await completedSessionStore.GetAllAsync();
            ResolveInitialDateRangeIfNeeded();
            ApplyCurrentQuery();
        }
        catch (Exception exception)
        {
            diagnostics.Error("session-library", "failed to load completed sessions", exception);
            libraryStatusTextBlock.Text = $"Unable to load sessions: {exception.Message}";
        }
        finally
        {
            isRefreshing = false;
            ApplyActionButtonState();
        }
    }

    private void ApplyCurrentQuery()
    {
        var previousSelectionId = selectedSession?.SessionId;
        var query = new SessionLibraryQuery(
            SearchText: searchTextBox.Text,
            DateRange: GetSelectedComboBoxValue(dateRangeComboBox, SessionLibraryDateRange.All),
            SortOrder: GetSelectedComboBoxValue(sortOrderComboBox, SessionLibrarySortOrder.NewestFirst),
            CustomRangeStart: customStartDatePicker.SelectedDate,
            CustomRangeEnd: customEndDatePicker.SelectedDate);

        var now = DateTimeOffset.Now;
        var filteredSessions = SessionLibraryQueryEvaluator.Apply(allSessions, query, now);
        var customRangeSessionCount = SessionLibraryQueryEvaluator.Apply(
            allSessions,
            query with
            {
                SearchText = string.Empty,
                DateRange = SessionLibraryDateRange.CustomRange,
            },
            now).Count;

        sessionListBox.Items.Clear();
        foreach (var session in filteredSessions)
        {
            sessionListBox.Items.Add(new SessionListItem(session));
        }

        customDateRangeStatusTextBlock.Text =
            customRangeSessionCount == 1
                ? "1 session in the selected date range."
                : $"{customRangeSessionCount} sessions in the selected date range.";
        emptyStateTextBlock.Visibility = filteredSessions.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        emptyStateTextBlock.Text = BuildEmptyStateText(query);
        libraryStatusTextBlock.Text = BuildLibraryStatusText(filteredSessions.Count, query);

        var itemToSelect = sessionListBox.Items
            .OfType<SessionListItem>()
            .FirstOrDefault(item => item.Session.SessionId == previousSelectionId)
            ?? sessionListBox.Items.OfType<SessionListItem>().FirstOrDefault();

        sessionListBox.SelectedItem = itemToSelect;
        if (itemToSelect is null)
        {
            selectedSession = null;
            UpdateReviewWorkspace(null);
        }
    }

    private void OnCustomDateRangeChanged(object? sender, SelectionChangedEventArgs e)
    {
        if (GetSelectedComboBoxValue(dateRangeComboBox, SessionLibraryDateRange.All) != SessionLibraryDateRange.CustomRange)
        {
            SetSelectedComboBoxValue(dateRangeComboBox, SessionLibraryDateRange.CustomRange);
            return;
        }

        ApplyCurrentQuery();
    }

    private async Task DeleteSelectedSessionAsync()
    {
        if (isRefreshing || isRunningReviewAction)
        {
            return;
        }

        var session = RequireSelectedSession();
        var deleteConfirmed = MessageBox.Show(
            this,
            BuildDeleteConfirmationMessage(session),
            "Delete Session?",
            MessageBoxButton.YesNo,
            MessageBoxImage.Warning,
            MessageBoxResult.No);

        if (deleteConfirmed != MessageBoxResult.Yes)
        {
            return;
        }

        isRunningReviewAction = true;
        libraryStatusTextBlock.Text = $"Deleting \"{session.Title}\"...";
        ApplyActionButtonState();

        try
        {
            await reviewSessionActionService.DeleteSessionAsync(session);

            allSessions = allSessions
                .Where(candidate => candidate.SessionId != session.SessionId)
                .ToArray();
            selectedSession = null;

            ApplyCurrentQuery();
            libraryStatusTextBlock.Text = $"Deleted \"{session.Title}\" from the local session library.";
            issuesStatusTextBlock.Text = "The selected session and its local artifacts were deleted.";
        }
        catch (Exception exception)
        {
            diagnostics.Error("session-library", $"failed to delete completed session {session.SessionId}", exception);
            libraryStatusTextBlock.Text = $"Unable to delete the session: {exception.Message}";
        }
        finally
        {
            isRunningReviewAction = false;
            ApplyActionButtonState();
        }
    }

    private void OnSessionSelectionChanged(object? sender, SelectionChangedEventArgs e)
    {
        selectedSession = (sessionListBox.SelectedItem as SessionListItem)?.Session;
        UpdateReviewWorkspace(selectedSession);
    }

    private void UpdateReviewWorkspace(CompletedSession? session)
    {
        if (session is null)
        {
            transcriptHeaderTextBlock.Text = "Transcript unavailable until you select a session.";
            transcriptTextBox.Text = string.Empty;
            summaryHeaderTextBlock.Text = "Select a session to inspect its review summary.";
            summaryTextBox.Text = string.Empty;
            screenshotListBox.Items.Clear();
            UpdateScreenshotPreview(null);
            issuesSummaryTextBlock.Text = "No extracted issues are loaded.";
            issuesGuidanceTextBlock.Text = "Select a saved session to run issue extraction or export review artifacts.";
            issuesStatusTextBlock.Text = "Select a saved session to extract issues, export bundles, or export selected issues.";
            issuesEmptyStateTextBlock.Text = string.Empty;
            issueEditorsPanel.Children.Clear();
            issueEditors = [];
            ApplyActionButtonState();
            return;
        }

        transcriptHeaderTextBlock.Text = BuildTranscriptHeader(session);
        transcriptTextBox.Text = string.IsNullOrWhiteSpace(session.TranscriptText)
            ? BuildTranscriptFallback(session)
            : session.TranscriptText;

        summaryHeaderTextBlock.Text = BuildSummaryHeader(session);
        summaryTextBox.Text = session.ReviewSummary;

        screenshotListBox.Items.Clear();
        foreach (var screenshot in session.Screenshots.OrderBy(screenshot => screenshot.ElapsedSeconds))
        {
            screenshotListBox.Items.Add(new ScreenshotListItem(screenshot));
        }

        screenshotListBox.SelectedItem = screenshotListBox.Items.OfType<ScreenshotListItem>().FirstOrDefault();
        if (screenshotListBox.SelectedItem is null)
        {
            UpdateScreenshotPreview(null);
        }

        RenderIssues(session);
        issuesStatusTextBlock.Text = BuildIssuesStatusMessage(session);
        ApplyActionButtonState();
    }

    private void RenderIssues(CompletedSession session)
    {
        issueEditorsPanel.Children.Clear();
        issueEditors = [];

        if (session.IssueExtraction is null)
        {
            issuesSummaryTextBlock.Text = "No extracted issues yet.";
            issuesGuidanceTextBlock.Text = "Click Extract Issues to turn the saved transcript into editable draft issues before export.";
            issuesEmptyStateTextBlock.Text =
                "Draft issues, export selection, and experimental GitHub/Jira export all live here once issue extraction completes.";
            return;
        }

        issuesSummaryTextBlock.Text = string.IsNullOrWhiteSpace(session.IssueExtraction.Summary)
            ? "Issue extraction completed."
            : session.IssueExtraction.Summary;
        issuesGuidanceTextBlock.Text = session.IssueExtraction.GuidanceNote;

        if (session.IssueExtraction.Issues.Count == 0)
        {
            issuesEmptyStateTextBlock.Text =
                "OpenAI returned no draft issues for this session. You can still export the session bundle or debug bundle.";
            return;
        }

        issuesEmptyStateTextBlock.Text = string.Empty;
        foreach (var issue in session.IssueExtraction.Issues)
        {
            var editor = CreateIssueEditor(issue);
            issueEditors.Add(editor);
            issueEditorsPanel.Children.Add(editor.Container);
        }
    }

    private IssueEditorRow CreateIssueEditor(ExtractedIssue issue)
    {
        var exportCheckBox = new CheckBox
        {
            Content = "Selected for export",
            IsChecked = issue.IsSelectedForExport,
            Margin = new Thickness(0, 0, 18, 10),
        };
        exportCheckBox.Checked += (_, _) => ApplyActionButtonState();
        exportCheckBox.Unchecked += (_, _) => ApplyActionButtonState();

        var requiresReviewCheckBox = new CheckBox
        {
            Content = "Needs review",
            IsChecked = issue.RequiresReview,
            Margin = new Thickness(0, 0, 0, 10),
        };

        var titleTextBox = BuildIssueTextBox(issue.Title);
        var categoryComboBox = new ComboBox
        {
            Margin = new Thickness(0, 0, 0, 12),
            ItemsSource = new[]
            {
                ExtractedIssueCategory.Bug,
                ExtractedIssueCategory.UxIssue,
                ExtractedIssueCategory.Enhancement,
                ExtractedIssueCategory.FollowUp,
            },
            SelectedItem = issue.Category,
        };
        var sectionTitleTextBox = BuildIssueTextBox(issue.SectionTitle ?? string.Empty);
        var summaryTextBox = BuildIssueTextBox(issue.Summary, acceptsReturn: true, height: 84);
        var evidenceTextBox = BuildIssueTextBox(issue.EvidenceExcerpt, acceptsReturn: true, height: 84);
        var noteTextBox = BuildIssueTextBox(issue.Note ?? string.Empty, acceptsReturn: true, height: 70);

        var metadataTextBlock = new TextBlock
        {
            Margin = new Thickness(0, 0, 0, 10),
            Foreground = Brushes.DimGray,
            Text = BuildIssueMetadata(issue),
            TextWrapping = TextWrapping.Wrap,
        };

        var editorContainer = new Border
        {
            Margin = new Thickness(0, 0, 0, 16),
            Padding = new Thickness(14),
            BorderBrush = Brushes.LightGray,
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(8),
            Child = new StackPanel
            {
                Children =
                {
                    metadataTextBlock,
                    new WrapPanel
                    {
                        Children =
                        {
                            exportCheckBox,
                            requiresReviewCheckBox,
                        },
                    },
                    BuildLabel("Title"),
                    titleTextBox,
                    BuildLabel("Category"),
                    categoryComboBox,
                    BuildLabel("Section"),
                    sectionTitleTextBox,
                    BuildLabel("Summary"),
                    summaryTextBox,
                    BuildLabel("Evidence"),
                    evidenceTextBox,
                    BuildLabel("Note"),
                    noteTextBox,
                },
            },
        };

        return new IssueEditorRow(
            issue,
            editorContainer,
            exportCheckBox,
            requiresReviewCheckBox,
            categoryComboBox,
            titleTextBox,
            sectionTitleTextBox,
            summaryTextBox,
            evidenceTextBox,
            noteTextBox);
    }

    private void OnScreenshotSelectionChanged(object? sender, SelectionChangedEventArgs e)
    {
        UpdateScreenshotPreview((screenshotListBox.SelectedItem as ScreenshotListItem)?.Screenshot);
    }

    private void UpdateScreenshotPreview(ScreenshotArtifact? screenshot)
    {
        if (screenshot is null)
        {
            screenshotPreviewTextBlock.Text = "No screenshots are attached to the selected session.";
            screenshotPreviewImage.Source = null;
            return;
        }

        screenshotPreviewTextBlock.Text =
            $"{Path.GetFileName(screenshot.RelativePath)} at {SessionTimeFormatter.FormatElapsedSeconds(screenshot.ElapsedSeconds)} ({screenshot.Width}x{screenshot.Height})";

        if (!File.Exists(screenshot.AbsolutePath))
        {
            screenshotPreviewImage.Source = null;
            screenshotPreviewTextBlock.Text += $"{Environment.NewLine}The image file was not found at {screenshot.AbsolutePath}.";
            return;
        }

        var bitmap = new BitmapImage();
        try
        {
            bitmap.BeginInit();
            bitmap.CacheOption = BitmapCacheOption.OnLoad;
            bitmap.UriSource = new Uri(screenshot.AbsolutePath);
            bitmap.EndInit();
            bitmap.Freeze();

            screenshotPreviewImage.Source = bitmap;
        }
        catch (Exception exception)
        {
            screenshotPreviewImage.Source = null;
            screenshotPreviewTextBlock.Text += $"{Environment.NewLine}The image preview could not be loaded.";
            diagnostics.Warning("session-library", $"failed to preview screenshot {screenshot.AbsolutePath}: {exception.Message}");
        }
    }

    private void ResolveInitialDateRangeIfNeeded()
    {
        if (hasResolvedInitialDateRange)
        {
            return;
        }

        hasResolvedInitialDateRange = true;
        var hasTodaySessions = allSessions.Any(session => session.CreatedAt.ToLocalTime().Date == DateTime.Today);
        if (!hasTodaySessions && allSessions.Count > 0)
        {
            SetSelectedComboBoxValue(dateRangeComboBox, SessionLibraryDateRange.All);
        }
    }

    private void UpdateCustomDateRangeVisibility()
    {
        var isCustomRange = GetSelectedComboBoxValue(dateRangeComboBox, SessionLibraryDateRange.All)
                            == SessionLibraryDateRange.CustomRange;
        customDateRangePanel.Visibility = isCustomRange ? Visibility.Visible : Visibility.Collapsed;
    }

    private static void AddComboBoxOption<T>(ComboBox comboBox, T value, string label)
    {
        comboBox.Items.Add(new ComboBoxItem
        {
            Content = label,
            Tag = value,
        });
    }

    private static T GetSelectedComboBoxValue<T>(ComboBox comboBox, T fallback)
    {
        return comboBox.SelectedItem is ComboBoxItem comboBoxItem && comboBoxItem.Tag is T value
            ? value
            : fallback;
    }

    private static void SetSelectedComboBoxValue<T>(ComboBox comboBox, T value)
    {
        var selectedItem = comboBox.Items
            .OfType<ComboBoxItem>()
            .FirstOrDefault(item => item.Tag is T itemValue && EqualityComparer<T>.Default.Equals(itemValue, value));

        if (selectedItem is not null)
        {
            comboBox.SelectedItem = selectedItem;
        }
    }

    private string BuildLibraryStatusText(int filteredCount, SessionLibraryQuery query)
    {
        if (filteredCount == 0)
        {
            return allSessions.Count == 0
                ? "No completed review sessions have been saved yet."
                : "No sessions matched the current library view.";
        }

        var resultLabel = filteredCount == 1 ? "1 session" : $"{filteredCount} sessions";
        return string.IsNullOrWhiteSpace(query.SearchText)
            ? resultLabel
            : $"{resultLabel} matched \"{query.SearchText.Trim()}\"";
    }

    private string BuildEmptyStateText(SessionLibraryQuery query)
    {
        if (allSessions.Count == 0)
        {
            return "No completed review sessions yet. Stop a recording to create one.";
        }

        if (!string.IsNullOrWhiteSpace(query.SearchText))
        {
            return $"No sessions matched \"{query.SearchText.Trim()}\". Try a different search term or clear search.";
        }

        return query.DateRange switch
        {
            SessionLibraryDateRange.Today => "No sessions were saved today. Switch to a broader filter to keep reviewing older work.",
            SessionLibraryDateRange.Yesterday => "No sessions were saved yesterday.",
            SessionLibraryDateRange.Last7Days => "No sessions were saved in the last 7 days.",
            SessionLibraryDateRange.Last30Days => "No sessions were saved in the last 30 days.",
            SessionLibraryDateRange.CustomRange => "No sessions fall inside the selected custom date range.",
            _ => "No completed review sessions are available in the local session library.",
        };
    }

    private static string BuildDeleteConfirmationMessage(CompletedSession session)
    {
        return session.Screenshots.Count switch
        {
            0 => $"Delete \"{session.Title}\" permanently from the local BugNarrator session library?",
            1 => $"Delete \"{session.Title}\" permanently? This also removes 1 locally stored screenshot and the rest of the session artifacts.",
            _ => $"Delete \"{session.Title}\" permanently? This also removes {session.Screenshots.Count} locally stored screenshots and the rest of the session artifacts.",
        };
    }

    private static FrameworkElement CreateRowChild(FrameworkElement element, int row)
    {
        Grid.SetRow(element, row);
        return element;
    }

    private static Button BuildActionButton(string title)
    {
        return new Button
        {
            Content = title,
            Height = 34,
            Margin = new Thickness(0, 0, 12, 12),
            MinWidth = 208,
        };
    }

    private static TextBox BuildIssueTextBox(
        string text,
        bool acceptsReturn = false,
        double? height = null)
    {
        return new TextBox
        {
            Text = text,
            Margin = new Thickness(0, 0, 0, 12),
            AcceptsReturn = acceptsReturn,
            Height = height ?? double.NaN,
            TextWrapping = acceptsReturn ? TextWrapping.Wrap : TextWrapping.NoWrap,
            VerticalScrollBarVisibility = acceptsReturn ? ScrollBarVisibility.Auto : ScrollBarVisibility.Hidden,
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

    private static string BuildTranscriptHeader(CompletedSession session)
    {
        return
            $"{session.Title}{Environment.NewLine}" +
            $"{session.CreatedAt:yyyy-MM-dd HH:mm:ss}  |  {SessionTimeFormatter.FormatDuration(session.Duration)}  |  {ToDisplayText(session.TranscriptionStatus)}";
    }

    private static string BuildSummaryHeader(CompletedSession session)
    {
        var extractedIssueCount = session.IssueExtraction?.Issues.Count ?? 0;
        return
            $"{session.Title}{Environment.NewLine}" +
            $"Model: {session.TranscriptionModel}  |  Screenshots: {session.Screenshots.Count}  |  Draft issues: {extractedIssueCount}";
    }

    private static string BuildTranscriptFallback(CompletedSession session)
    {
        return session.TranscriptionStatus switch
        {
            SessionTranscriptionStatus.NotConfigured =>
                "This recording was saved without a transcript because an OpenAI API key was not configured in Settings.",
            SessionTranscriptionStatus.Failed =>
                $"Transcription failed for this session. {session.TranscriptionFailureMessage ?? "Check the Windows log for more detail."}",
            _ => "No transcript text was saved for this session.",
        };
    }

    private static string ToDisplayText(SessionTranscriptionStatus status)
    {
        return status switch
        {
            SessionTranscriptionStatus.Completed => "Completed",
            SessionTranscriptionStatus.NotConfigured => "Not Configured",
            SessionTranscriptionStatus.Failed => "Failed",
            _ => status.ToString(),
        };
    }

    private static string ToDisplayText(ExtractedIssueCategory category)
    {
        return category switch
        {
            ExtractedIssueCategory.Bug => "Bug",
            ExtractedIssueCategory.UxIssue => "UX Issue",
            ExtractedIssueCategory.Enhancement => "Enhancement",
            ExtractedIssueCategory.FollowUp => "Question / Follow-up",
            _ => category.ToString(),
        };
    }

    private static string BuildIssuesStatusMessage(CompletedSession session)
    {
        if (session.IssueExtraction is null)
        {
            return "Extract draft issues from this transcript, or export the local session bundle and debug bundle.";
        }

        var selectedCount = session.IssueExtraction.SelectedIssues.Count;
        return
            $"{session.IssueExtraction.Issues.Count} draft issue(s) loaded. " +
            $"{selectedCount} currently selected for export. Save any title, note, or category edits before exporting.";
    }

    private static string BuildIssueMetadata(ExtractedIssue issue)
    {
        var parts = new List<string>
        {
            ToDisplayText(issue.Category),
        };

        if (issue.TimestampLabel is not null)
        {
            parts.Add($"Transcript time: {issue.TimestampLabel}");
        }

        if (issue.ConfidenceLabel is not null)
        {
            parts.Add($"Confidence: {issue.ConfidenceLabel}");
        }

        if (issue.RelatedScreenshotIds.Count > 0)
        {
            parts.Add($"{issue.RelatedScreenshotIds.Count} linked screenshot(s)");
        }

        return string.Join("  |  ", parts);
    }

    private static string BuildExportStatusMessage(
        string destinationName,
        IReadOnlyList<IssueExportResult> results)
    {
        var firstUrl = results
            .Select(result => result.RemoteUrl?.ToString())
            .FirstOrDefault(url => !string.IsNullOrWhiteSpace(url));

        return firstUrl is null
            ? $"{destinationName} export completed for {results.Count} issue(s)."
            : $"{destinationName} export completed for {results.Count} issue(s). First item: {firstUrl}";
    }

    private sealed class IssueEditorRow
    {
        private readonly ComboBox categoryComboBox;
        private readonly TextBox evidenceTextBox;
        private readonly CheckBox exportCheckBox;
        private readonly TextBox noteTextBox;
        private readonly CheckBox requiresReviewCheckBox;
        private readonly TextBox sectionTitleTextBox;
        private readonly ExtractedIssue sourceIssue;
        private readonly TextBox summaryTextBox;
        private readonly TextBox titleTextBox;

        public IssueEditorRow(
            ExtractedIssue sourceIssue,
            Border container,
            CheckBox exportCheckBox,
            CheckBox requiresReviewCheckBox,
            ComboBox categoryComboBox,
            TextBox titleTextBox,
            TextBox sectionTitleTextBox,
            TextBox summaryTextBox,
            TextBox evidenceTextBox,
            TextBox noteTextBox)
        {
            this.sourceIssue = sourceIssue;
            Container = container;
            this.exportCheckBox = exportCheckBox;
            this.requiresReviewCheckBox = requiresReviewCheckBox;
            this.categoryComboBox = categoryComboBox;
            this.titleTextBox = titleTextBox;
            this.sectionTitleTextBox = sectionTitleTextBox;
            this.summaryTextBox = summaryTextBox;
            this.evidenceTextBox = evidenceTextBox;
            this.noteTextBox = noteTextBox;
        }

        public Border Container { get; }

        public bool IsSelectedForExport => exportCheckBox.IsChecked == true;

        public ExtractedIssue BuildIssue()
        {
            return sourceIssue with
            {
                Title = NormalizeText(titleTextBox.Text, sourceIssue.Title),
                Category = categoryComboBox.SelectedItem is ExtractedIssueCategory category
                    ? category
                    : sourceIssue.Category,
                Summary = NormalizeText(summaryTextBox.Text, sourceIssue.Summary),
                EvidenceExcerpt = NormalizeText(evidenceTextBox.Text, sourceIssue.EvidenceExcerpt),
                RequiresReview = requiresReviewCheckBox.IsChecked != false,
                IsSelectedForExport = exportCheckBox.IsChecked == true,
                SectionTitle = NullIfWhiteSpace(sectionTitleTextBox.Text),
                Note = NullIfWhiteSpace(noteTextBox.Text),
            };
        }

        private static string NormalizeText(string value, string fallback)
        {
            return string.IsNullOrWhiteSpace(value)
                ? fallback
                : value.Trim();
        }

        private static string? NullIfWhiteSpace(string? value)
        {
            return string.IsNullOrWhiteSpace(value) ? null : value.Trim();
        }
    }

    private sealed class SessionListItem
    {
        public SessionListItem(CompletedSession session)
        {
            Session = session;
        }

        public CompletedSession Session { get; }

        public override string ToString()
        {
            var issueCount = Session.IssueExtraction?.Issues.Count ?? 0;
            return
                $"{Session.Title}{Environment.NewLine}" +
                $"{Session.CreatedAt:yyyy-MM-dd HH:mm}  |  {ToDisplayText(Session.TranscriptionStatus)}  |  {Session.Screenshots.Count} screenshots  |  {issueCount} draft issues";
        }
    }

    private sealed class ScreenshotListItem
    {
        public ScreenshotListItem(ScreenshotArtifact screenshot)
        {
            Screenshot = screenshot;
        }

        public ScreenshotArtifact Screenshot { get; }

        public override string ToString()
        {
            return $"{Path.GetFileName(Screenshot.RelativePath)}  |  {SessionTimeFormatter.FormatElapsedSeconds(Screenshot.ElapsedSeconds)}";
        }
    }
}
