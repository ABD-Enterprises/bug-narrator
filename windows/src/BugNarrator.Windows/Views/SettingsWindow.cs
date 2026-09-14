using BugNarrator.Windows.Services.Shell;
using BugNarrator.Windows.Accessibility;
using BugNarrator.Windows.Services.Audio;
using BugNarrator.Windows.Services.Diagnostics;
using BugNarrator.Windows.Services.Hotkeys;
using BugNarrator.Windows.Services.LocalTranscription;
using BugNarrator.Windows.Services.Secrets;
using BugNarrator.Windows.Services.Settings;
using BugNarrator.Windows.Services.Transcription;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Threading;

namespace BugNarrator.Windows.Views;

public sealed class SettingsWindow : Window
{
    private readonly PasswordBox apiKeyPasswordBox;
    private readonly TextBox aiProviderBaseUrlTextBox;
    private readonly ComboBox aiProviderComboBox;
    private readonly TextBlock aiProviderCapabilityHintTextBlock;
    private readonly ILocalTranscriptionServerManager localServerManager;
    private readonly ILocalServerHealthProbe localServerHealthProbe;
    private readonly DispatcherTimer localServerPollTimer;
    private readonly StackPanel localServerPanel;
    private readonly TextBlock localServerStatusTextBlock;
    private readonly TextBlock localServerMessageTextBlock;
    private readonly ProgressBar localServerProgressBar;
    private readonly Button localServerDownloadButton;
    private readonly Button localServerCheckDownloadButton;
    private readonly Button localServerStartStopButton;
    private readonly Button localServerRemoveButton;
    private readonly Button localServerCancelButton;
    private bool localServerReachable;
    private bool localServerProbeInFlight;
    private readonly IAudioInputDeviceCatalog audioInputDeviceCatalog;
    private readonly ComboBox audioInputDeviceComboBox;
    private readonly ComboBox audioRecordingSourceComboBox;
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
    private readonly CheckBox systemAudioConsentCheckBox;
    private readonly CheckBox experimentalSystemAudioCheckBox;
    private readonly CheckBox launchAtLoginCheckBox;
    private readonly CheckBox autoExtractIssuesCheckBox;
    private readonly TextBlock launchAtLoginStatusTextBlock;
    private readonly ILaunchAtLoginService launchAtLoginService;
    private bool launchAtLoginAsLoaded;
    private readonly ITranscriptionClient transcriptionClient;

    public SettingsWindow(
        IWindowsAppSettingsStore settingsStore,
        ISecretStore secretStore,
        ITranscriptionClient transcriptionClient,
        IWindowsGlobalHotkeyService hotkeyService,
        WindowsDiagnostics diagnostics,
        IAudioInputDeviceCatalog audioInputDeviceCatalog,
        ILaunchAtLoginService launchAtLoginService,
        ILocalTranscriptionServerManager localServerManager,
        ILocalServerHealthProbe localServerHealthProbe)
    {
        this.localServerManager = localServerManager;
        this.localServerHealthProbe = localServerHealthProbe;
        this.settingsStore = settingsStore;
        this.secretStore = secretStore;
        this.transcriptionClient = transcriptionClient;
        this.hotkeyService = hotkeyService;
        this.diagnostics = diagnostics;
        this.audioInputDeviceCatalog = audioInputDeviceCatalog;

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

        aiProviderBaseUrlTextBox = new TextBox
        {
            Margin = new Thickness(0, 0, 0, 14),
        };

        aiProviderComboBox = new ComboBox
        {
            Margin = new Thickness(0, 0, 0, 14),
            DisplayMemberPath = nameof(WindowsAiProviderProfile.DisplayName),
            ItemsSource = WindowsAiProviderProfile.All,
        };
        aiProviderCapabilityHintTextBlock = BuildHint(WindowsAiProviderProfile.TranscriptionOnlyGuidance);
        aiProviderCapabilityHintTextBlock.Visibility = Visibility.Collapsed;
        System.Windows.Automation.AutomationProperties.SetName(
            aiProviderCapabilityHintTextBlock, "AI provider capability note");
        aiProviderComboBox.SelectionChanged += (_, _) => ApplyAiProviderCapabilityHint();

        // Local (Parakeet) server section: the macOS localServerControls block, with the health
        // probe as the status line (#1180). Visible only while that provider is selected.
        localServerStatusTextBlock = BuildHint("Local server: not checked yet.");
        localServerMessageTextBlock = BuildHint(string.Empty);
        localServerProgressBar = new ProgressBar { Minimum = 0, Maximum = 1, Height = 8, Margin = new Thickness(0, 0, 0, 8), Visibility = Visibility.Collapsed };
        System.Windows.Automation.AutomationProperties.SetName(localServerProgressBar, "Local server download progress");
        localServerDownloadButton = BuildLocalServerButton("Download the local transcription server", async () => await localServerManager.InstallAndStartAsync());
        localServerCheckDownloadButton = BuildLocalServerButton("Check server download", async () => await localServerManager.DiscoverAsync());
        localServerStartStopButton = BuildLocalServerButton("Start local server", async () =>
        {
            if (localServerManager.State.Running)
            {
                localServerManager.Stop();
            }
            else
            {
                await localServerManager.StartAsync();
            }
        });
        localServerRemoveButton = BuildLocalServerButton("Remove local server and models", () => { localServerManager.Remove(); return Task.CompletedTask; });
        localServerCancelButton = BuildLocalServerButton("Cancel installation", () => { localServerManager.Stop(); return Task.CompletedTask; });
        localServerPanel = new StackPanel
        {
            Visibility = Visibility.Collapsed,
            Children =
            {
                BuildLabel("Local (Parakeet) Server"),
                BuildHint("Local server download: about 136 MB. Model weights download on first start and require additional disk space."),
                localServerStatusTextBlock,
                new WrapPanel
                {
                    Children = { localServerDownloadButton, localServerCheckDownloadButton, localServerStartStopButton, localServerRemoveButton, localServerCancelButton },
                },
                localServerProgressBar,
                BuildHint($"Install location: {localServerManager.InstallDirectory}"),
                localServerMessageTextBlock,
            },
        };
        System.Windows.Automation.AutomationProperties.SetName(localServerPanel, "Local Parakeet server");
        localServerManager.StateChanged += OnLocalServerStateChanged;
        localServerPollTimer = new DispatcherTimer { Interval = LocalServerHealthProbe.PollInterval };
        localServerPollTimer.Tick += async (_, _) => await RefreshLocalServerReachabilityAsync();
        aiProviderComboBox.SelectionChanged += (_, _) => ApplyLocalServerSectionVisibility();

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

        audioInputDeviceComboBox = new ComboBox
        {
            Margin = new Thickness(0, 0, 0, 14),
            DisplayMemberPath = nameof(AudioInputDeviceOption.DisplayName),
        };

        audioRecordingSourceComboBox = new ComboBox
        {
            Margin = new Thickness(0, 0, 0, 14),
            DisplayMemberPath = nameof(AudioRecordingSourceProfile.DisplayName),
            ItemsSource = AudioRecordingSourceProfile.All,
        };

        this.launchAtLoginService = launchAtLoginService;
        autoExtractIssuesCheckBox = new CheckBox
        {
            Margin = new Thickness(0, -4, 0, 14),
            Content = "Automatically extract issues after transcription",
        };

        launchAtLoginCheckBox = new CheckBox
        {
            Margin = new Thickness(0, 0, 0, 4),
            // The macOS label (SettingsGeneralPanes.swift).
            Content = "Open BugNarrator at startup",
        };
        launchAtLoginStatusTextBlock = new TextBlock
        {
            Margin = new Thickness(0, 0, 0, 14),
            TextWrapping = TextWrapping.Wrap,
            Visibility = Visibility.Collapsed,
        };

        experimentalSystemAudioCheckBox = new CheckBox
        {
            Margin = new Thickness(0, -4, 0, 8),
            Content = "System audio capture modes (experimental)",
        };

        systemAudioConsentCheckBox = new CheckBox
        {
            Margin = new Thickness(0, -4, 0, 14),
            Content = "I understand system audio recording captures audio playing from other apps on this PC.",
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
        // Visible labels double as accessible names (product-spec Accessibility Contract);
        // AccessibleNameAuditTests fails on any input this leaves unlabeled.
        AccessibleLabels.LabelInputsFromPrecedingText(this);
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
                        Text = "Configure AI provider settings, optional global hotkeys, and the experimental export integrations for the Windows app.",
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
                    BuildLabel("AI Provider"),
                    aiProviderComboBox,
                    BuildHint("Choose OpenAI, an OpenAI-compatible hosted endpoint, a local-compatible endpoint, or Local (Parakeet) for transcription-only offline use."),
                    aiProviderCapabilityHintTextBlock,
                    localServerPanel,
                    BuildLabel("AI Provider Credential"),
                    apiKeyPasswordBox,
                    BuildHint("Stored locally for the current Windows user with DPAPI. Required for OpenAI and OpenAI-compatible providers; optional for local-compatible providers."),
                    BuildLabel("AI Provider Base URL"),
                    aiProviderBaseUrlTextBox,
                    BuildHint("Optional. Leave blank for OpenAI. Use an OpenAI-compatible base URL such as https://api.openai.com/v1 or a trusted enterprise/local endpoint."),
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
                    autoExtractIssuesCheckBox,
                    launchAtLoginCheckBox,
                    launchAtLoginStatusTextBlock,
                    BuildLabel("Recording Audio Source"),
                    audioRecordingSourceComboBox,
                    BuildHint("Choose Microphone for normal narration, System Audio for app/computer playback, or Microphone + System Audio to see the currently tracked mixed-capture limitation."),
                    experimentalSystemAudioCheckBox,
                    systemAudioConsentCheckBox,
                    BuildLabel("Microphone Input Device"),
                    audioInputDeviceComboBox,
                    BuildHint("Choose a specific Windows microphone when recording from the microphone. If the saved device disappears, BugNarrator will ask you to choose another instead of silently using the wrong microphone."),
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
            aiProviderComboBox.SelectedItem = settings.EffectiveAiProviderProfile;
            ApplyLocalServerSectionVisibility();
            aiProviderBaseUrlTextBox.Text = settings.EffectiveAiProviderBaseUrl ?? string.Empty;
            modelTextBox.Text = settings.EffectiveTranscriptionModel;
            languageHintTextBox.Text = settings.EffectiveLanguageHint ?? string.Empty;
            promptTextBox.Text = settings.EffectiveTranscriptionPrompt ?? string.Empty;
            issueExtractionModelTextBox.Text = settings.EffectiveIssueExtractionModel;
            audioRecordingSourceComboBox.SelectedItem = settings.EffectiveRecordingAudioSourceProfile;
            systemAudioConsentCheckBox.IsChecked = settings.HasAcceptedSystemAudioRecordingConsent;
            experimentalSystemAudioCheckBox.IsChecked = settings.IsExperimentalSystemAudioEnabled;
            autoExtractIssuesCheckBox.IsChecked = settings.AutoExtractIssues;
            ApplyLaunchAtLoginStatus(launchAtLoginService.CurrentStatus());
            PopulateAudioInputDevices(settings.EffectiveAudioInputDeviceName);
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
                ? "No AI provider credential is saved yet. Global hotkeys remain optional and start as Not Set."
                : BuildLoadStatusMessage(hotkeyService.CurrentSnapshot);
        }
        catch (Exception exception)
        {
            diagnostics.Error("settings", "failed to load settings", exception);
            statusTextBlock.Text = $"Unable to load settings: {exception.Message}";
        }
    }

    private void ApplyLaunchAtLoginStatus(LaunchAtLoginStatus status)
    {
        launchAtLoginCheckBox.IsChecked = status.IsEnabled;
        launchAtLoginAsLoaded = status.IsEnabled;
        launchAtLoginCheckBox.IsEnabled = status.IsAvailable;
        launchAtLoginStatusTextBlock.Text = status.Message ?? string.Empty;
        launchAtLoginStatusTextBlock.Visibility = status.Message is null ? Visibility.Collapsed : Visibility.Visible;
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
                AiProviderBaseUrl: aiProviderBaseUrlTextBox.Text,
                AudioInputDeviceName: (audioInputDeviceComboBox.SelectedItem as AudioInputDeviceOption)?.DisplayName ?? string.Empty,
                GitHubRepositoryOwner: gitHubOwnerTextBox.Text,
                GitHubRepositoryName: gitHubRepositoryTextBox.Text,
                GitHubDefaultLabels: gitHubDefaultLabelsTextBox.Text,
                JiraBaseUrl: jiraBaseUrlTextBox.Text,
                JiraProjectKey: jiraProjectKeyTextBox.Text,
                JiraIssueType: jiraIssueTypeTextBox.Text,
                StartRecordingHotkey: draftHotkeys[WindowsHotkeyAction.StartRecording],
                StopRecordingHotkey: draftHotkeys[WindowsHotkeyAction.StopRecording],
                ScreenshotHotkey: draftHotkeys[WindowsHotkeyAction.CaptureScreenshot],
                AiProvider: GetSelectedAiProviderProfile().StorageValue,
                RecordingAudioSource: GetSelectedRecordingAudioSourceProfile().StorageValue,
                HasAcceptedSystemAudioRecordingConsent: systemAudioConsentCheckBox.IsChecked == true,
                IsExperimentalSystemAudioEnabled: experimentalSystemAudioCheckBox.IsChecked == true,
                AutoExtractIssues: autoExtractIssuesCheckBox.IsChecked == true);

            if (settings.AiProviderCompatibilityIssue is { } aiProviderIssue)
            {
                statusTextBlock.Text = aiProviderIssue;
                return;
            }

            var validationIssues = WindowsHotkeySettingsValidator.Validate(settings);
            if (validationIssues.Count > 0)
            {
                ApplyValidationIssues(validationIssues);
                statusTextBlock.Text = validationIssues[0].Message;
                return;
            }

            await settingsStore.SaveAsync(settings);
            // Registry-backed, not a settings field: the Run key is the single source of truth, and the
            // Windows Settings Startup page can change it behind our back.
            // Only on an explicit toggle: saving an unrelated setting must not touch the Run key,
            // and a change made in Windows Settings while this dialog was open must not be undone.
            var launchAtLoginWanted = launchAtLoginCheckBox.IsChecked == true;
            if (launchAtLoginCheckBox.IsEnabled && launchAtLoginWanted != launchAtLoginAsLoaded)
            {
                ApplyLaunchAtLoginStatus(launchAtLoginService.SetEnabled(launchAtLoginWanted));
            }
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
        var providerProfile = GetSelectedAiProviderProfile();
        var validationSettings = WindowsAppSettings.Default with
        {
            AiProvider = providerProfile.StorageValue,
            AiProviderBaseUrl = aiProviderBaseUrlTextBox.Text,
            TranscriptionModel = modelTextBox.Text,
            IssueExtractionModel = issueExtractionModelTextBox.Text,
        };

        if (validationSettings.AiProviderCompatibilityIssue is { } aiProviderIssue)
        {
            statusTextBlock.Text = aiProviderIssue;
            return;
        }

        if (providerProfile.RequiresCredential && apiKey.Length == 0)
        {
            statusTextBlock.Text = $"Enter a {providerProfile.DisplayName} credential before running validation.";
            return;
        }

        statusTextBlock.Text = $"Validating the {providerProfile.DisplayName} connection...";

        // Check Server: the health probe, not the OpenAI validate call (macOS uses the same probe).
        if (validationSettings.UsesLocalTranscriptionServer)
        {
            await RefreshLocalServerReachabilityAsync();
            statusTextBlock.Text = localServerReachable
                ? providerProfile.SuccessMessage
                : LocalServerHealthProbe.UnreachableMessage;
            return;
        }

        try
        {
            // Effective URL so a blank Parakeet base URL checks localhost:8422 rather than api.openai.com.
            await transcriptionClient.ValidateApiKeyAsync(
                apiKey,
                validationSettings.EffectiveAiProviderBaseUrl ?? aiProviderBaseUrlTextBox.Text);
            statusTextBlock.Text = providerProfile.SuccessMessage;
        }
        catch (Exception exception)
        {
            diagnostics.Error("settings", "api key validation failed", exception);
            statusTextBlock.Text = $"AI provider validation failed: {exception.Message}";
        }
    }

    private Task AssignHotkeyAsync(WindowsHotkeyAction action)
    {
        var captureWindow = new HotkeyCaptureWindow(action)
        {
            Owner = this,
        };

        if (captureWindow.ShowDialog() != true || captureWindow.CapturedShortcut is null)
        {
            return Task.CompletedTask;
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
            return Task.CompletedTask;
        }

        pendingHotkeyChanges.Add(action);
        RefreshHotkeyValueText();
        RefreshHotkeyStatusText(hotkeyService.CurrentSnapshot);
        statusTextBlock.Text = $"{action.DisplayName()} will use {proposedShortcut.DisplayString} after you click Save.";
        return Task.CompletedTask;
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
        localServerManager.StateChanged -= OnLocalServerStateChanged;
        localServerPollTimer.Stop();
    }

    private static Button BuildLocalServerButton(string title, Func<Task> action)
    {
        var button = new Button
        {
            Content = title,
            Margin = new Thickness(0, 0, 8, 8),
            Padding = new Thickness(12, 6, 12, 6),
        };
        button.Click += async (_, _) => await action();
        return button;
    }

    /// <summary>Polls only while Parakeet is selected, as macOS refreshLocalProviderReachabilityIfNeeded.</summary>
    private void ApplyLocalServerSectionVisibility()
    {
        var uses = GetSelectedAiProviderProfile().Provider == WindowsAiProvider.ParakeetLocal;
        localServerPanel.Visibility = uses ? Visibility.Visible : Visibility.Collapsed;
        if (uses)
        {
            if (!localServerPollTimer.IsEnabled)
            {
                localServerPollTimer.Start();
                _ = RefreshLocalServerReachabilityAsync();
            }
        }
        else
        {
            localServerPollTimer.Stop();
        }

        ApplyLocalServerState(localServerManager.State);
    }

    private async Task RefreshLocalServerReachabilityAsync()
    {
        if (localServerProbeInFlight)
        {
            return;
        }

        localServerProbeInFlight = true;
        try
        {
            localServerReachable = await localServerHealthProbe.IsReachableAsync(WindowsAiProviderProfile.ParakeetLocalBaseUrl);
        }
        finally
        {
            localServerProbeInFlight = false;
        }

        ApplyLocalServerState(localServerManager.State);
    }

    private void OnLocalServerStateChanged(object? sender, LocalTranscriptionServerState state)
    {
        Dispatcher.BeginInvoke(() => ApplyLocalServerState(state));
    }

    /// <summary>
    /// The macOS localServerControls rules: download while not installed (needs a package), Start /
    /// Stop while installed, Remove only when idle, Cancel only during a download. A server that
    /// answers on 8422 but was not started by this app disables Start and is never stopped.
    /// </summary>
    internal void ApplyLocalServerState(LocalTranscriptionServerState state)
    {
        var foreignServer = localServerReachable && !state.Running;
        localServerStatusTextBlock.Text = state.Running
            ? (localServerReachable ? "Local server: running and responding on port 8422." : "Local server: starting, not responding yet.")
            : foreignServer
                ? "A local transcription server is already responding on port 8422."
                : "Local server: not responding on port 8422.";

        localServerDownloadButton.Visibility = state.Installed ? Visibility.Collapsed : Visibility.Visible;
        localServerDownloadButton.IsEnabled = !state.Busy && state.Package is not null;
        localServerCheckDownloadButton.Visibility = state.Installed || state.Package is not null ? Visibility.Collapsed : Visibility.Visible;
        localServerCheckDownloadButton.IsEnabled = !state.Busy;
        localServerStartStopButton.Visibility = state.Installed ? Visibility.Visible : Visibility.Collapsed;
        localServerStartStopButton.Content = state.Running ? "Stop local server" : "Start local server";
        localServerStartStopButton.IsEnabled = !state.Busy && (state.Running || !foreignServer);
        localServerRemoveButton.Visibility = state.Installed ? Visibility.Visible : Visibility.Collapsed;
        localServerRemoveButton.IsEnabled = !state.Busy && !state.Running;
        localServerProgressBar.Visibility = state.Progress is null ? Visibility.Collapsed : Visibility.Visible;
        localServerProgressBar.Value = state.Progress ?? 0;
        localServerCancelButton.Visibility = state.Progress is null ? Visibility.Collapsed : Visibility.Visible;
        localServerMessageTextBlock.Text = state.Message;
        localServerMessageTextBlock.Visibility = string.IsNullOrEmpty(state.Message) ? Visibility.Collapsed : Visibility.Visible;
    }

    internal void SetLocalServerReachableForTests(bool reachable) => localServerReachable = reachable;

    internal IReadOnlyList<Button> LocalServerButtonsForTests =>
        [localServerDownloadButton, localServerCheckDownloadButton, localServerStartStopButton, localServerRemoveButton, localServerCancelButton];

    private void PopulateAudioInputDevices(string? selectedDeviceName)
    {
        var availableDevices = audioInputDeviceCatalog.GetAvailableInputDevices();
        audioInputDeviceComboBox.ItemsSource = availableDevices;

        if (availableDevices.Count == 0)
        {
            audioInputDeviceComboBox.SelectedItem = null;
            statusTextBlock.Text = "No Windows microphone device is currently available.";
            return;
        }

        if (string.IsNullOrWhiteSpace(selectedDeviceName))
        {
            audioInputDeviceComboBox.SelectedItem = availableDevices[0];
            return;
        }

        audioInputDeviceComboBox.SelectedItem = availableDevices.FirstOrDefault(device =>
            string.Equals(device.DisplayName, selectedDeviceName.Trim(), StringComparison.OrdinalIgnoreCase));

        if (audioInputDeviceComboBox.SelectedItem is null)
        {
            audioInputDeviceComboBox.SelectedItem = availableDevices[0];
            statusTextBlock.Text = $"Saved microphone \"{selectedDeviceName.Trim()}\" is unavailable. Choose another input device and click Save.";
        }
    }

    private static string BuildLoadStatusMessage(WindowsHotkeyRuntimeSnapshot snapshot)
    {
        return snapshot.HasProblems
            ? "Settings loaded. Some saved global hotkeys need attention in the optional hotkey section."
            : "AI provider, issue extraction, experimental export settings, and optional global hotkeys are loaded for this Windows user.";
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

    /// <summary>
    /// Shows the macOS transcription-only note beside the provider choice for providers that
    /// cannot extract issues (#1168); hidden otherwise.
    /// </summary>
    private void ApplyAiProviderCapabilityHint()
    {
        aiProviderCapabilityHintTextBlock.Visibility = GetSelectedAiProviderProfile().SupportsIssueExtraction
            ? Visibility.Collapsed
            : Visibility.Visible;
    }

    private WindowsAiProviderProfile GetSelectedAiProviderProfile()
    {
        return aiProviderComboBox.SelectedItem as WindowsAiProviderProfile
            ?? WindowsAiProviderProfile.Default;
    }

    private AudioRecordingSourceProfile GetSelectedRecordingAudioSourceProfile()
    {
        return audioRecordingSourceComboBox.SelectedItem as AudioRecordingSourceProfile
            ?? AudioRecordingSourceProfile.Default;
    }
}
