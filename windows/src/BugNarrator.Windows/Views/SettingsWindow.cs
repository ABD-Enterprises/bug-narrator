using BugNarrator.Windows.Services.Diagnostics;
using BugNarrator.Windows.Services.Hotkeys;
using BugNarrator.Windows.Services.Secrets;
using BugNarrator.Windows.Services.Settings;
using BugNarrator.Windows.Services.Transcription;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace BugNarrator.Windows.Views;

public sealed class SettingsWindow : Window
{
    private readonly PasswordBox apiKeyPasswordBox;
    private readonly WindowsDiagnostics diagnostics;
    private readonly Dictionary<WindowsHotkeyAction, WindowsHotkeyShortcut> draftHotkeys = [];
    private readonly TextBox gitHubDefaultLabelsTextBox;
    private readonly TextBox gitHubOwnerTextBox;
    private readonly TextBox gitHubRepositoryTextBox;
    private readonly PasswordBox gitHubTokenPasswordBox;
    private readonly IWindowsGlobalHotkeyService hotkeyService;
    private readonly Dictionary<WindowsHotkeyAction, TextBlock> hotkeyStatusTextBlocks = [];
    private readonly Dictionary<WindowsHotkeyAction, TextBlock> hotkeyValueTextBlocks = [];
    private readonly TextBox issueExtractionModelTextBox;
    private readonly PasswordBox jiraApiTokenPasswordBox;
    private readonly TextBox jiraBaseUrlTextBox;
    private readonly TextBox jiraEmailTextBox;
    private readonly TextBox jiraIssueTypeTextBox;
    private readonly TextBox jiraProjectKeyTextBox;
    private readonly TextBox languageHintTextBox;
    private readonly TextBox modelTextBox;
    private readonly HashSet<WindowsHotkeyAction> pendingHotkeyChanges = [];
    private readonly TextBox promptTextBox;
    private readonly ISecretStore secretStore;
    private readonly IWindowsAppSettingsStore settingsStore;
    private readonly TextBlock statusTextBlock;
    private readonly ITranscriptionClient transcriptionClient;

    public SettingsWindow(
        IWindowsAppSettingsStore settingsStore,
        ISecretStore secretStore,
        ITranscriptionClient transcriptionClient,
        IWindowsGlobalHotkeyService hotkeyService,
        WindowsDiagnostics diagnostics)
    {
        this.settingsStore = settingsStore;
        this.secretStore = secretStore;
        this.transcriptionClient = transcriptionClient;
        this.hotkeyService = hotkeyService;
        this.diagnostics = diagnostics;

        foreach (var action in WindowsHotkeyActionExtensions.All)
        {
            draftHotkeys[action] = WindowsHotkeyShortcut.NotSet;
        }

        Title = "BugNarrator Settings";
        Width = 780;
        Height = 820;
        MinWidth = 680;
        MinHeight = 620;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Background = Brushes.White;

        apiKeyPasswordBox = new PasswordBox
        {
            Margin = new Thickness(0, 0, 0, 14),
        };

        modelTextBox = new TextBox
        {
            Margin = new Thickness(0, 0, 0, 14),
        };

        languageHintTextBox = new TextBox
        {
            Margin = new Thickness(0, 0, 0, 14),
        };

        promptTextBox = new TextBox
        {
            AcceptsReturn = true,
            Height = 120,
            Margin = new Thickness(0, 0, 0, 14),
            TextWrapping = TextWrapping.Wrap,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
        };

        issueExtractionModelTextBox = new TextBox
        {
            Margin = new Thickness(0, 0, 0, 14),
        };

        gitHubTokenPasswordBox = new PasswordBox
        {
            Margin = new Thickness(0, 0, 0, 14),
        };

        gitHubOwnerTextBox = new TextBox
        {
            Margin = new Thickness(0, 0, 0, 14),
        };

        gitHubRepositoryTextBox = new TextBox
        {
            Margin = new Thickness(0, 0, 0, 14),
        };

        gitHubDefaultLabelsTextBox = new TextBox
        {
            Margin = new Thickness(0, 0, 0, 14),
        };

        jiraBaseUrlTextBox = new TextBox
        {
            Margin = new Thickness(0, 0, 0, 14),
        };

        jiraEmailTextBox = new TextBox
        {
            Margin = new Thickness(0, 0, 0, 14),
        };

        jiraApiTokenPasswordBox = new PasswordBox
        {
            Margin = new Thickness(0, 0, 0, 14),
        };

        jiraProjectKeyTextBox = new TextBox
        {
            Margin = new Thickness(0, 0, 0, 14),
        };

        jiraIssueTypeTextBox = new TextBox
        {
            Margin = new Thickness(0, 0, 0, 14),
        };

        statusTextBlock = new TextBlock
        {
            Margin = new Thickness(0, 12, 0, 0),
            Foreground = Brushes.DimGray,
            TextWrapping = TextWrapping.Wrap,
        };

        Content = BuildWindowContent();
        Loaded += async (_, _) => await LoadSettingsAsync();
        Closed += OnClosed;
        hotkeyService.StateChanged += OnHotkeyStateChanged;
    }

    private UIElement BuildWindowContent()
    {
        var root = new DockPanel
        {
            Margin = new Thickness(24),
        };

        var validateButton = new Button
        {
            Content = "Validate Key",
            Width = 120,
            Height = 34,
            Margin = new Thickness(0, 0, 10, 0),
        };
        validateButton.Click += async (_, _) => await ValidateApiKeyAsync();

        var saveButton = new Button
        {
            Content = "Save",
            Width = 100,
            Height = 34,
            Margin = new Thickness(0, 0, 10, 0),
        };
        saveButton.Click += async (_, _) => await SaveSettingsAsync();

        var closeButton = new Button
        {
            Content = "Close",
            Width = 100,
            Height = 34,
        };
        closeButton.Click += (_, _) => Close();

        var buttonBar = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            HorizontalAlignment = HorizontalAlignment.Right,
            Margin = new Thickness(0, 18, 0, 0),
            Children =
            {
                validateButton,
                saveButton,
                closeButton,
            },
        };

        DockPanel.SetDock(buttonBar, Dock.Bottom);
        root.Children.Add(buttonBar);

        root.Children.Add(new ScrollViewer
        {
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            Content = new StackPanel
            {
                Children =
                {
                    new TextBlock
                    {
                        FontSize = 28,
                        FontWeight = FontWeights.Bold,
                        Text = "Settings",
                    },
                    new TextBlock
                    {
                        Margin = new Thickness(0, 12, 0, 0),
                        Text = "Configure transcription, optional global hotkeys, and the experimental export integrations for the Windows app.",
                        TextWrapping = TextWrapping.Wrap,
                    },
                    new TextBlock
                    {
                        Margin = new Thickness(0, 16, 0, 0),
                        Foreground = Brushes.DimGray,
                        Text = "Source-of-truth docs: windows/docs/WINDOWS_IMPLEMENTATION_ROADMAP.md and docs/CROSS_PLATFORM_GUIDELINES.md",
                        TextWrapping = TextWrapping.Wrap,
                    },
                    BuildOpenAiSettingsSection(),
                    BuildHotkeySettingsSection(),
                    BuildGitHubSettingsSection(),
                    BuildJiraSettingsSection(),
                },
            },
        });

        return root;
    }

    private UIElement BuildOpenAiSettingsSection()
    {
        return new Border
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
                    BuildLabel("OpenAI API Key"),
                    apiKeyPasswordBox,
                    BuildHint("Stored locally for the current Windows user with DPAPI. BugNarrator does not ship with a bundled API key."),
                    BuildLabel("Transcription Model"),
                    modelTextBox,
                    BuildHint("Defaults to whisper-1 to match the current BugNarrator product baseline."),
                    BuildLabel("Language Hint"),
                    languageHintTextBox,
                    BuildHint("Optional. Leave blank to let OpenAI auto-detect the spoken language."),
                    BuildLabel("Transcription Prompt"),
                    promptTextBox,
                    BuildHint("Optional context sent with the audio transcription request."),
                    BuildLabel("Issue Extraction Model"),
                    issueExtractionModelTextBox,
                    BuildHint("Defaults to gpt-4.1-mini for structured draft issue extraction after transcription."),
                    statusTextBlock,
                },
            },
        };
    }

    private UIElement BuildHotkeySettingsSection()
    {
        return new Border
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
                    new TextBlock
                    {
                        FontSize = 18,
                        FontWeight = FontWeights.SemiBold,
                        Text = "Global Hotkeys (Optional)",
                    },
                    BuildHint("Hotkeys start as Not Set. Assign them only if you want global shortcuts while BugNarrator stays in the tray."),
                    BuildHint("Shortcut changes apply when you click Save. Duplicate assignments are rejected, and unavailable OS-level shortcuts are saved with a visible warning."),
                    BuildHotkeyRow(WindowsHotkeyAction.StartRecording),
                    BuildHotkeyRow(WindowsHotkeyAction.StopRecording),
                    BuildHotkeyRow(WindowsHotkeyAction.CaptureScreenshot),
                },
            },
        };
    }

    private UIElement BuildGitHubSettingsSection()
    {
        return new Border
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
                    new TextBlock
                    {
                        FontSize = 18,
                        FontWeight = FontWeights.SemiBold,
                        Text = "GitHub Export (Experimental)",
                    },
                    BuildHint("These settings stay local. Export creates GitHub Issues from selected extracted issues."),
                    BuildLabel("GitHub Token"),
                    gitHubTokenPasswordBox,
                    BuildHint("Use a token with permission to create issues in the target repository."),
                    BuildLabel("Repository Owner"),
                    gitHubOwnerTextBox,
                    BuildLabel("Repository Name"),
                    gitHubRepositoryTextBox,
                    BuildLabel("Default Labels"),
                    gitHubDefaultLabelsTextBox,
                    BuildHint("Optional. Separate labels with commas or new lines."),
                },
            },
        };
    }

    private UIElement BuildJiraSettingsSection()
    {
        return new Border
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
                    new TextBlock
                    {
                        FontSize = 18,
                        FontWeight = FontWeights.SemiBold,
                        Text = "Jira Export (Experimental)",
                    },
                    BuildHint("These settings stay local. Export creates Jira issues from selected extracted issues."),
                    BuildLabel("Jira Base URL"),
                    jiraBaseUrlTextBox,
                    BuildHint("Example: https://your-company.atlassian.net"),
                    BuildLabel("Jira Email"),
                    jiraEmailTextBox,
                    BuildLabel("Jira API Token"),
                    jiraApiTokenPasswordBox,
                    BuildHint("Use an Atlassian API token tied to the configured email address."),
                    BuildLabel("Project Key"),
                    jiraProjectKeyTextBox,
                    BuildLabel("Issue Type"),
                    jiraIssueTypeTextBox,
                    BuildHint("Defaults to Task unless your Jira project needs a different issue type."),
                },
            },
        };
    }

    private UIElement BuildHotkeyRow(WindowsHotkeyAction action)
    {
        var valueTextBlock = new TextBlock
        {
            FontWeight = FontWeights.SemiBold,
            Text = "Not Set",
            VerticalAlignment = VerticalAlignment.Center,
        };
        hotkeyValueTextBlocks[action] = valueTextBlock;

        var statusText = new TextBlock
        {
            Margin = new Thickness(0, 6, 0, 0),
            Foreground = Brushes.DimGray,
            TextWrapping = TextWrapping.Wrap,
        };
        hotkeyStatusTextBlocks[action] = statusText;

        var assignButton = new Button
        {
            Content = "Assign",
            Width = 90,
            Height = 30,
            Margin = new Thickness(10, 0, 8, 0),
        };
        assignButton.Click += async (_, _) => await AssignHotkeyAsync(action);

        var clearButton = new Button
        {
            Content = "Clear",
            Width = 80,
            Height = 30,
        };
        clearButton.Click += (_, _) => ClearHotkey(action);

        var valueBorder = new Border
        {
            Padding = new Thickness(10, 8, 10, 8),
            BorderBrush = Brushes.LightGray,
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(6),
            Child = valueTextBlock,
        };

        var buttonRow = new Grid
        {
            Margin = new Thickness(0, 6, 0, 0),
            ColumnDefinitions =
            {
                new ColumnDefinition
                {
                    Width = new GridLength(1, GridUnitType.Star),
                },
                new ColumnDefinition
                {
                    Width = GridLength.Auto,
                },
                new ColumnDefinition
                {
                    Width = GridLength.Auto,
                },
            },
        };
        Grid.SetColumn(valueBorder, 0);
        Grid.SetColumn(assignButton, 1);
        Grid.SetColumn(clearButton, 2);
        buttonRow.Children.Add(valueBorder);
        buttonRow.Children.Add(assignButton);
        buttonRow.Children.Add(clearButton);

        return new StackPanel
        {
            Margin = new Thickness(0, 14, 0, 0),
            Children =
            {
                new TextBlock
                {
                    FontWeight = FontWeights.SemiBold,
                    Text = action.DisplayName(),
                },
                buttonRow,
                statusText,
            },
        };
    }

    private async Task LoadSettingsAsync()
    {
        try
        {
            var settings = await settingsStore.LoadAsync();
            var apiKey = await secretStore.GetAsync(SecretKeys.OpenAiApiKey);
            var gitHubToken = await secretStore.GetAsync(SecretKeys.GitHubToken);
            var jiraEmail = await secretStore.GetAsync(SecretKeys.JiraEmail);
            var jiraApiToken = await secretStore.GetAsync(SecretKeys.JiraApiToken);

            apiKeyPasswordBox.Password = apiKey ?? string.Empty;
            modelTextBox.Text = settings.EffectiveTranscriptionModel;
            languageHintTextBox.Text = settings.EffectiveLanguageHint ?? string.Empty;
            promptTextBox.Text = settings.EffectiveTranscriptionPrompt ?? string.Empty;
            issueExtractionModelTextBox.Text = settings.EffectiveIssueExtractionModel;
            gitHubTokenPasswordBox.Password = gitHubToken ?? string.Empty;
            gitHubOwnerTextBox.Text = settings.NormalizedGitHubRepositoryOwner;
            gitHubRepositoryTextBox.Text = settings.NormalizedGitHubRepositoryName;
            gitHubDefaultLabelsTextBox.Text = string.Join(", ", settings.GitHubDefaultLabelsList);
            jiraBaseUrlTextBox.Text = settings.NormalizedJiraBaseUrl;
            jiraEmailTextBox.Text = jiraEmail ?? string.Empty;
            jiraApiTokenPasswordBox.Password = jiraApiToken ?? string.Empty;
            jiraProjectKeyTextBox.Text = settings.NormalizedJiraProjectKey;
            jiraIssueTypeTextBox.Text = settings.EffectiveJiraIssueType;

            draftHotkeys[WindowsHotkeyAction.StartRecording] = settings.EffectiveStartRecordingHotkey;
            draftHotkeys[WindowsHotkeyAction.StopRecording] = settings.EffectiveStopRecordingHotkey;
            draftHotkeys[WindowsHotkeyAction.CaptureScreenshot] = settings.EffectiveScreenshotHotkey;
            pendingHotkeyChanges.Clear();

            RefreshHotkeyValueText();
            RefreshHotkeyStatusText(hotkeyService.CurrentSnapshot);

            statusTextBlock.Text = string.IsNullOrWhiteSpace(apiKey)
                ? "No OpenAI API key is saved yet. Global hotkeys remain optional and start as Not Set."
                : BuildLoadStatusMessage(hotkeyService.CurrentSnapshot);
        }
        catch (Exception exception)
        {
            diagnostics.Error("settings", "failed to load settings", exception);
            statusTextBlock.Text = $"Unable to load settings: {exception.Message}";
        }
    }

    private async Task SaveSettingsAsync()
    {
        try
        {
            var settings = new WindowsAppSettings(
                TranscriptionModel: modelTextBox.Text,
                LanguageHint: languageHintTextBox.Text,
                TranscriptionPrompt: promptTextBox.Text,
                IssueExtractionModel: issueExtractionModelTextBox.Text,
                GitHubRepositoryOwner: gitHubOwnerTextBox.Text,
                GitHubRepositoryName: gitHubRepositoryTextBox.Text,
                GitHubDefaultLabels: gitHubDefaultLabelsTextBox.Text,
                JiraBaseUrl: jiraBaseUrlTextBox.Text,
                JiraProjectKey: jiraProjectKeyTextBox.Text,
                JiraIssueType: jiraIssueTypeTextBox.Text,
                StartRecordingHotkey: draftHotkeys[WindowsHotkeyAction.StartRecording],
                StopRecordingHotkey: draftHotkeys[WindowsHotkeyAction.StopRecording],
                ScreenshotHotkey: draftHotkeys[WindowsHotkeyAction.CaptureScreenshot]);

            var validationIssues = WindowsHotkeySettingsValidator.Validate(settings);
            if (validationIssues.Count > 0)
            {
                ApplyValidationIssues(validationIssues);
                statusTextBlock.Text = validationIssues[0].Message;
                return;
            }

            await settingsStore.SaveAsync(settings);
            await secretStore.SetAsync(SecretKeys.OpenAiApiKey, apiKeyPasswordBox.Password);
            await secretStore.SetAsync(SecretKeys.GitHubToken, gitHubTokenPasswordBox.Password);
            await secretStore.SetAsync(SecretKeys.JiraEmail, jiraEmailTextBox.Text);
            await secretStore.SetAsync(SecretKeys.JiraApiToken, jiraApiTokenPasswordBox.Password);

            var snapshot = await hotkeyService.ApplySettingsAsync(settings);
            pendingHotkeyChanges.Clear();
            RefreshHotkeyValueText();
            RefreshHotkeyStatusText(snapshot);

            diagnostics.Info("settings", "review, extraction, export, and hotkey settings saved");
            statusTextBlock.Text = BuildSavedStatusMessage(snapshot);
        }
        catch (Exception exception)
        {
            diagnostics.Error("settings", "failed to save settings", exception);
            statusTextBlock.Text = $"Unable to save settings: {exception.Message}";
        }
    }

    private async Task ValidateApiKeyAsync()
    {
        var apiKey = apiKeyPasswordBox.Password.Trim();
        if (apiKey.Length == 0)
        {
            statusTextBlock.Text = "Enter an OpenAI API key before running validation.";
            return;
        }

        statusTextBlock.Text = "Validating the OpenAI API key...";

        try
        {
            await transcriptionClient.ValidateApiKeyAsync(apiKey);
            statusTextBlock.Text = "The OpenAI API key was accepted.";
        }
        catch (Exception exception)
        {
            diagnostics.Error("settings", "api key validation failed", exception);
            statusTextBlock.Text = $"OpenAI key validation failed: {exception.Message}";
        }
    }

    private async Task AssignHotkeyAsync(WindowsHotkeyAction action)
    {
        var captureWindow = new HotkeyCaptureWindow(action)
        {
            Owner = this,
        };

        if (captureWindow.ShowDialog() != true || captureWindow.CapturedShortcut is null)
        {
            return;
        }

        var proposedShortcut = captureWindow.CapturedShortcut.Value.Normalize();
        var previousShortcut = draftHotkeys[action];
        draftHotkeys[action] = proposedShortcut;

        var issues = WindowsHotkeySettingsValidator.Validate(draftHotkeys);
        var issueForAction = issues.FirstOrDefault(issue => issue.Action == action);
        if (issueForAction is not null)
        {
            draftHotkeys[action] = previousShortcut;
            RefreshHotkeyValueText();
            RefreshHotkeyStatusText(hotkeyService.CurrentSnapshot);
            hotkeyStatusTextBlocks[action].Text = issueForAction.Message;
            hotkeyStatusTextBlocks[action].Foreground = Brushes.DarkRed;
            statusTextBlock.Text = issueForAction.Message;
            return;
        }

        pendingHotkeyChanges.Add(action);
        RefreshHotkeyValueText();
        RefreshHotkeyStatusText(hotkeyService.CurrentSnapshot);
        statusTextBlock.Text = $"{action.DisplayName()} will use {proposedShortcut.DisplayString} after you click Save.";
    }

    private void ClearHotkey(WindowsHotkeyAction action)
    {
        draftHotkeys[action] = WindowsHotkeyShortcut.NotSet;
        pendingHotkeyChanges.Add(action);
        RefreshHotkeyValueText();
        RefreshHotkeyStatusText(hotkeyService.CurrentSnapshot);
        statusTextBlock.Text = $"{action.DisplayName()} will return to Not Set after you click Save.";
    }

    private void ApplyValidationIssues(IReadOnlyList<WindowsHotkeyValidationIssue> issues)
    {
        RefreshHotkeyStatusText(hotkeyService.CurrentSnapshot);

        foreach (var issue in issues)
        {
            if (!hotkeyStatusTextBlocks.TryGetValue(issue.Action, out var statusText))
            {
                continue;
            }

            statusText.Text = issue.Message;
            statusText.Foreground = Brushes.DarkRed;
        }
    }

    private void RefreshHotkeyValueText()
    {
        foreach (var action in WindowsHotkeyActionExtensions.All)
        {
            hotkeyValueTextBlocks[action].Text = draftHotkeys[action].DisplayString;
        }
    }

    private void RefreshHotkeyStatusText(WindowsHotkeyRuntimeSnapshot snapshot)
    {
        foreach (var action in WindowsHotkeyActionExtensions.All)
        {
            var statusText = hotkeyStatusTextBlocks[action];

            if (pendingHotkeyChanges.Contains(action))
            {
                statusText.Text = "Pending save. Click Save to apply this change.";
                statusText.Foreground = Brushes.DimGray;
                continue;
            }

            var registrationStatus = snapshot.GetStatus(action);
            statusText.Text = registrationStatus.Message;
            statusText.Foreground = registrationStatus.State is WindowsHotkeyRegistrationState.Invalid
                or WindowsHotkeyRegistrationState.Conflict
                or WindowsHotkeyRegistrationState.Unavailable
                ? Brushes.DarkRed
                : Brushes.DimGray;
        }
    }

    private void OnHotkeyStateChanged(object? sender, WindowsHotkeyRuntimeSnapshot snapshot)
    {
        Dispatcher.Invoke(() => RefreshHotkeyStatusText(snapshot));
    }

    private void OnClosed(object? sender, EventArgs e)
    {
        hotkeyService.StateChanged -= OnHotkeyStateChanged;
    }

    private static string BuildLoadStatusMessage(WindowsHotkeyRuntimeSnapshot snapshot)
    {
        return snapshot.HasProblems
            ? "Settings loaded. Some saved global hotkeys need attention in the optional hotkey section."
            : "OpenAI, issue extraction, experimental export settings, and optional global hotkeys are loaded for this Windows user.";
    }

    private static string BuildSavedStatusMessage(WindowsHotkeyRuntimeSnapshot snapshot)
    {
        var problemStatuses = snapshot.Statuses
            .Where(status => status.State is WindowsHotkeyRegistrationState.Invalid
                or WindowsHotkeyRegistrationState.Conflict
                or WindowsHotkeyRegistrationState.Unavailable)
            .ToArray();

        if (problemStatuses.Length == 0)
        {
            return "Settings saved. Transcription, export, and optional hotkeys are updated.";
        }

        if (problemStatuses.Length == 1)
        {
            return $"Settings saved. {problemStatuses[0].Message}";
        }

        return "Settings saved. Some global hotkeys are not active yet. Review the hotkey section for details.";
    }

    private static TextBlock BuildHint(string text)
    {
        return new TextBlock
        {
            Margin = new Thickness(0, -6, 0, 14),
            Foreground = Brushes.DimGray,
            Text = text,
            TextWrapping = TextWrapping.Wrap,
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
}
