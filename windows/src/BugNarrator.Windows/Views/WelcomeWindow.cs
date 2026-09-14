using BugNarrator.Core.Workflow;
using BugNarrator.Windows.Services.Audio;
using BugNarrator.Windows.Services.Diagnostics;
using BugNarrator.Windows.Services.Hotkeys;
using BugNarrator.Windows.Services.Permissions;
using BugNarrator.Windows.Services.Secrets;
using BugNarrator.Windows.Services.Settings;
using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace BugNarrator.Windows.Views;

/// <summary>
/// The one-time first-run tour (macOS Views/WelcomeView.swift): three steps — provider, microphone,
/// hotkeys — each skippable, reopenable from the tray, and honest about what is done. Every gating
/// decision comes from <see cref="FirstRunFunnel"/>; this class only renders and persists.
/// </summary>
public sealed class WelcomeWindow : Window
{
    private const string MicrophonePrivacySettingsUri = "ms-settings:privacy-microphone";

    private readonly IAudioInputDeviceCatalog audioInputDeviceCatalog;
    private readonly WindowsDiagnostics diagnostics;
    private readonly IWindowsGlobalHotkeyService hotkeyService;
    private readonly IMicrophonePreflightService microphonePreflightService;
    private readonly Action openSettings;
    private readonly ISecretStore secretStore;
    private readonly IWindowsAppSettingsStore settingsStore;

    private readonly Button backButton;
    private readonly Button primaryButton;
    private readonly Button skipButton;
    private readonly StackPanel bodyPanel;
    private readonly StackPanel stepListPanel;
    private readonly Dictionary<OnboardingStep, TextBlock> stepMarkers = new();

    private WindowsAppSettings settings = WindowsAppSettings.Default;
    private string? providerCredential;
    private bool microphoneAuthorized;
    private string? microphoneMessage;
    private int stepIndex;
    private bool finished;

    public WelcomeWindow(
        IWindowsAppSettingsStore settingsStore,
        ISecretStore secretStore,
        IWindowsGlobalHotkeyService hotkeyService,
        IMicrophonePreflightService microphonePreflightService,
        IAudioInputDeviceCatalog audioInputDeviceCatalog,
        WindowsDiagnostics diagnostics,
        Action openSettings)
    {
        this.settingsStore = settingsStore;
        this.secretStore = secretStore;
        this.hotkeyService = hotkeyService;
        this.microphonePreflightService = microphonePreflightService;
        this.audioInputDeviceCatalog = audioInputDeviceCatalog;
        this.diagnostics = diagnostics;
        this.openSettings = openSettings;

        Title = "Welcome to BugNarrator";
        Width = 560;
        Height = 520;
        MinWidth = 520;
        MinHeight = 460;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Background = Brushes.White;

        stepListPanel = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 12, 0, 0) };
        foreach (var step in FirstRunFunnel.Steps)
        {
            var marker = new TextBlock
            {
                Margin = new Thickness(0, 0, 18, 0),
                Foreground = Brushes.DimGray,
            };
            stepMarkers[step] = marker;
            stepListPanel.Children.Add(marker);
        }

        bodyPanel = new StackPanel();

        skipButton = BuildButton("Skip Setup");
        skipButton.ToolTip = "Closes the tour. Anything left unconfigured stays unconfigured.";
        skipButton.Click += async (_, _) => await SkipAsync();

        backButton = BuildButton("Back");
        backButton.Click += (_, _) => { stepIndex = Math.Max(stepIndex - 1, 0); Render(); };

        primaryButton = BuildButton("Next");
        primaryButton.IsDefault = true;
        primaryButton.Click += async (_, _) => await AdvanceAsync();

        var footer = new DockPanel { Margin = new Thickness(24, 16, 24, 16) };
        DockPanel.SetDock(skipButton, Dock.Left);
        footer.Children.Add(skipButton);
        var right = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
        right.Children.Add(backButton);
        right.Children.Add(primaryButton);
        footer.Children.Add(right);

        var header = new StackPanel
        {
            Margin = new Thickness(24, 24, 24, 16),
            Children =
            {
                new TextBlock { FontSize = 24, FontWeight = FontWeights.Bold, Text = "Welcome to BugNarrator" },
                new TextBlock
                {
                    Margin = new Thickness(0, 8, 0, 0),
                    TextWrapping = TextWrapping.Wrap,
                    Text = "Record what you are testing, narrate the problem out loud, and get a written transcript with the issues already pulled out. Three quick things and you are recording.",
                },
                stepListPanel,
            },
        };

        var root = new DockPanel();
        DockPanel.SetDock(header, Dock.Top);
        DockPanel.SetDock(footer, Dock.Bottom);
        root.Children.Add(header);
        root.Children.Add(footer);
        root.Children.Add(new ScrollViewer
        {
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            Content = new Border { Padding = new Thickness(24, 0, 24, 0), Child = bodyPanel },
        });
        Content = root;

        Loaded += async (_, _) => await RefreshAsync(advanceToFirstIncomplete: true);
        Activated += async (_, _) =>
        {
            // The user leaves to Settings or the system privacy page and comes back; re-read state
            // so a step completed elsewhere shows as done without restarting the tour.
            if (IsLoaded)
            {
                await RefreshAsync(advanceToFirstIncomplete: false);
            }
        };
        Closed += async (_, _) =>
        {
            // The close box is a skip, as on macOS: dismissal must be durable or an unconfigured
            // user is re-prompted on every launch. Readiness itself is never fabricated.
            if (!finished)
            {
                await MarkCompletedAsync();
            }
        };
    }

    /// <summary>The plain-value view of readiness every decision reads from.</summary>
    internal OnboardingSnapshot Snapshot => new(
        HasUsableAiProviderCredential: settings.HasUsableAiProviderCredential(providerCredential),
        ProviderConfigurationIsCompatible: settings.AiProviderCompatibilityIssue is null,
        MicrophoneAuthorized: microphoneAuthorized,
        HasAnyCaptureHotkeyAssigned: settings.HasAnyCaptureHotkeyAssigned);

    internal OnboardingStep CurrentStep => FirstRunFunnel.Steps[Math.Clamp(stepIndex, 0, FirstRunFunnel.Steps.Count - 1)];

    private bool IsOnLastStep => stepIndex >= FirstRunFunnel.Steps.Count - 1;

    /// <summary>Renders the given step with the current (unloaded) snapshot; for the accessibility audit only.</summary>
    internal void RenderStepForAudit(int index)
    {
        stepIndex = Math.Clamp(index, 0, FirstRunFunnel.Steps.Count - 1);
        Render();
    }

    private async Task RefreshAsync(bool advanceToFirstIncomplete)
    {
        try
        {
            settings = await settingsStore.LoadAsync();
            providerCredential = await secretStore.GetAsync(SecretKeys.OpenAiApiKey);
        }
        catch (Exception exception)
        {
            diagnostics.Error("welcome", "failed to load settings for the welcome tour", exception);
        }

        if (advanceToFirstIncomplete && FirstRunFunnel.FirstIncompleteStep(Snapshot) is { } first)
        {
            stepIndex = FirstRunFunnel.Steps.ToList().IndexOf(first);
        }

        Render();
    }

    private void Render()
    {
        var snapshot = Snapshot;
        foreach (var (step, marker) in stepMarkers)
        {
            var complete = FirstRunFunnel.IsComplete(step, snapshot);
            marker.Text = (complete ? "✓ " : "○ ") + FirstRunFunnel.Title(step);
            marker.FontWeight = step == CurrentStep ? FontWeights.SemiBold : FontWeights.Normal;
            System.Windows.Automation.AutomationProperties.SetName(
                marker, $"{FirstRunFunnel.Title(step)}: {(complete ? "done" : "not done yet")}");
        }

        bodyPanel.Children.Clear();
        var fullyConfigured = FirstRunFunnel.IsFullyConfigured(snapshot);
        if (fullyConfigured)
        {
            bodyPanel.Children.Add(BuildHeading("You are all set"));
            bodyPanel.Children.Add(BuildBody("Your AI provider, microphone access, and capture hotkeys are all configured. Start a session from the tray whenever you are ready."));
        }
        else
        {
            switch (CurrentStep)
            {
                case OnboardingStep.Provider:
                    RenderProviderStep(snapshot);
                    break;
                case OnboardingStep.Microphone:
                    RenderMicrophoneStep(snapshot);
                    break;
                case OnboardingStep.Hotkeys:
                    RenderHotkeysStep(snapshot);
                    break;
            }
        }

        backButton.Visibility = fullyConfigured ? Visibility.Collapsed : Visibility.Visible;
        backButton.IsEnabled = stepIndex > 0;
        primaryButton.Content = IsOnLastStep || fullyConfigured ? "Done" : "Next";
    }

    private void RenderProviderStep(OnboardingSnapshot snapshot)
    {
        bodyPanel.Children.Add(BuildHeading(FirstRunFunnel.Title(OnboardingStep.Provider)));
        bodyPanel.Children.Add(BuildBody("BugNarrator sends your recording to an AI provider to transcribe it and pull out the issues. Pick a provider and paste a key — or choose a local engine that needs no key at all."));
        if (FirstRunFunnel.IsComplete(OnboardingStep.Provider, snapshot))
        {
            bodyPanel.Children.Add(BuildDone("Provider ready."));
            return;
        }

        if (settings.AiProviderCompatibilityIssue is { } issue)
        {
            bodyPanel.Children.Add(BuildWarning(issue));
        }

        var open = BuildButton("Open AI Provider Settings");
        open.ToolTip = "Settings opens on the AI provider section while a provider still needs configuring.";
        open.Click += (_, _) => openSettings();
        bodyPanel.Children.Add(open);
        bodyPanel.Children.Add(BuildBody("This is the only step that gates recording. The other two make BugNarrator nicer to use, and you can skip them."));
    }

    private void RenderMicrophoneStep(OnboardingSnapshot snapshot)
    {
        bodyPanel.Children.Add(BuildHeading(FirstRunFunnel.Title(OnboardingStep.Microphone)));
        bodyPanel.Children.Add(BuildBody("BugNarrator records your narration, so Windows needs to allow it to use the microphone."));
        if (FirstRunFunnel.IsComplete(OnboardingStep.Microphone, snapshot))
        {
            bodyPanel.Children.Add(BuildDone("Microphone access granted."));
            return;
        }

        if (microphoneMessage is { } message)
        {
            bodyPanel.Children.Add(BuildWarning(message));
        }

        var check = BuildButton("Check Microphone Access");
        check.ToolTip = "Opens the microphone briefly to confirm Windows allows it. You can also do this later, the first time you record.";
        check.Click += (_, _) => CheckMicrophone();
        bodyPanel.Children.Add(check);

        var openPrivacy = BuildButton("Open Microphone Settings");
        openPrivacy.ToolTip = "Opens Windows Settings > Privacy & security > Microphone.";
        openPrivacy.Click += (_, _) => OpenMicrophonePrivacySettings();
        bodyPanel.Children.Add(openPrivacy);
        bodyPanel.Children.Add(BuildBody("If Windows is blocking microphone access for desktop apps, turn it back on in Settings, then return here."));
    }

    private void RenderHotkeysStep(OnboardingSnapshot snapshot)
    {
        bodyPanel.Children.Add(BuildHeading(FirstRunFunnel.Title(OnboardingStep.Hotkeys)));
        bodyPanel.Children.Add(BuildBody("Global shortcuts let you start, stop, and grab a screenshot without leaving the app you are testing. BugNarrator ships with none bound, so nothing of yours is overwritten."));

        foreach (var (action, shortcut) in settings.GetHotkeyAssignments())
        {
            var row = new TextBlock
            {
                Margin = new Thickness(0, 0, 0, 4),
                Text = $"{action.DisplayName()}: {(shortcut.IsConfigured ? shortcut.DisplayString : "Not assigned")}",
            };
            bodyPanel.Children.Add(row);
        }

        if (FirstRunFunnel.IsComplete(OnboardingStep.Hotkeys, snapshot))
        {
            bodyPanel.Children.Add(BuildDone("At least one capture hotkey is assigned."));
            return;
        }

        var suggest = BuildButton("Use Suggested Shortcuts");
        suggest.ToolTip = "Applies the recommended shortcut to every capture action that is still unassigned.";
        suggest.Click += async (_, _) => await ApplySuggestedShortcutsAsync();
        bodyPanel.Children.Add(suggest);
        bodyPanel.Children.Add(BuildBody("Nothing is bound until you press the button, and you can change any of these later in Settings."));
    }

    private void CheckMicrophone()
    {
        var selection = AudioInputDeviceSelection.Resolve(
            settings.EffectiveAudioInputDeviceName,
            audioInputDeviceCatalog.GetAvailableInputDevices());
        if (!selection.IsResolved)
        {
            microphoneAuthorized = false;
            microphoneMessage = selection.ErrorMessage ?? "No microphone device is available.";
            Render();
            return;
        }

        var result = microphonePreflightService.CheckReadyToRecord(isAlreadyRecording: false, selection.DeviceNumber);
        diagnostics.Info("welcome", $"microphone check: {result.Status}");
        microphoneAuthorized = result.CanStart;
        microphoneMessage = result.CanStart ? null : result.Message;
        Render();
    }

    private void OpenMicrophonePrivacySettings()
    {
        try
        {
            // A fixed ms-settings: URI, not user input; ShellExecute is what opens the Settings app.
            Process.Start(new ProcessStartInfo(MicrophonePrivacySettingsUri) { UseShellExecute = true });
        }
        catch (Exception exception)
        {
            diagnostics.Error("welcome", "failed to open microphone privacy settings", exception);
            microphoneMessage = "Could not open Windows Settings. Open Settings > Privacy & security > Microphone by hand.";
            Render();
        }
    }

    /// <summary>
    /// Only fills empty slots, as macOS applySuggestedShortcuts does: a shortcut the user already
    /// chose is never replaced, and a suggestion already assigned elsewhere is not duplicated.
    /// </summary>
    internal static WindowsAppSettings WithSuggestedShortcuts(WindowsAppSettings current)
    {
        var assignments = new Dictionary<WindowsHotkeyAction, WindowsHotkeyShortcut>(current.GetHotkeyAssignments());
        foreach (var action in WindowsHotkeyActionExtensions.All)
        {
            if (assignments[action].IsConfigured)
            {
                continue;
            }

            var suggestion = action.SuggestedShortcut();
            if (assignments.Any(pair => pair.Key != action && pair.Value == suggestion))
            {
                continue;
            }

            assignments[action] = suggestion;
        }

        return current with
        {
            StartRecordingHotkey = assignments[WindowsHotkeyAction.StartRecording],
            StopRecordingHotkey = assignments[WindowsHotkeyAction.StopRecording],
            ScreenshotHotkey = assignments[WindowsHotkeyAction.CaptureScreenshot],
        };
    }

    private async Task ApplySuggestedShortcutsAsync()
    {
        try
        {
            var updated = WithSuggestedShortcuts(await settingsStore.LoadAsync());
            var issues = WindowsHotkeySettingsValidator.Validate(updated);
            if (issues.Count > 0)
            {
                bodyPanel.Children.Add(BuildWarning(issues[0].Message));
                return;
            }

            await settingsStore.SaveAsync(updated);
            await hotkeyService.ApplySettingsAsync(updated);
            diagnostics.Info("welcome", "suggested capture hotkeys applied");
        }
        catch (Exception exception)
        {
            diagnostics.Error("welcome", "failed to apply suggested hotkeys", exception);
            bodyPanel.Children.Add(BuildWarning($"Could not apply the suggested shortcuts: {exception.Message}"));
            return;
        }

        await RefreshAsync(advanceToFirstIncomplete: false);
    }

    private async Task AdvanceAsync()
    {
        if (IsOnLastStep || FirstRunFunnel.IsFullyConfigured(Snapshot))
        {
            await FinishAsync();
            return;
        }

        stepIndex = Math.Min(stepIndex + 1, FirstRunFunnel.Steps.Count - 1);
        Render();
    }

    private async Task SkipAsync()
    {
        var blocking = FirstRunFunnel.BlockingIncompleteSteps(Snapshot);
        if (blocking.Count == 0)
        {
            await FinishAsync();
            return;
        }

        // Names only the steps that actually block recording — skipping the hotkey step costs nothing.
        var names = string.Join(", ", blocking.Select(FirstRunFunnel.Title));
        var message = $"BugNarrator cannot transcribe a recording until this is done: {names}. "
            + "You can finish it later in Settings, or reopen this tour from the tray menu's Show Welcome Tour.";
        var answer = MessageBox.Show(this, message, "Skip setup?", MessageBoxButton.OKCancel, MessageBoxImage.Warning, MessageBoxResult.Cancel);
        if (answer == MessageBoxResult.OK)
        {
            await FinishAsync();
        }
    }

    /// <summary>Skipping and completing are the same on purpose: both make dismissal durable.</summary>
    private async Task FinishAsync()
    {
        await MarkCompletedAsync();
        Close();
    }

    private async Task MarkCompletedAsync()
    {
        if (finished)
        {
            return;
        }

        finished = true;
        try
        {
            var current = await settingsStore.LoadAsync();
            if (!current.HasCompletedWelcome)
            {
                await settingsStore.SaveAsync(current with { HasCompletedWelcome = true });
            }

            diagnostics.Info("welcome", "welcome tour completed or skipped");
        }
        catch (Exception exception)
        {
            diagnostics.Error("welcome", "failed to record welcome completion", exception);
        }
    }

    private static Button BuildButton(string title)
    {
        return new Button
        {
            Content = title,
            Margin = new Thickness(0, 0, 8, 8),
            Padding = new Thickness(12, 6, 12, 6),
            HorizontalAlignment = HorizontalAlignment.Left,
        };
    }

    private static TextBlock BuildHeading(string text) => new()
    {
        FontSize = 18,
        FontWeight = FontWeights.SemiBold,
        Margin = new Thickness(0, 0, 0, 8),
        Text = text,
    };

    private static TextBlock BuildBody(string text) => new()
    {
        Margin = new Thickness(0, 0, 0, 12),
        TextWrapping = TextWrapping.Wrap,
        Text = text,
    };

    private static TextBlock BuildDone(string text) => new()
    {
        Margin = new Thickness(0, 0, 0, 12),
        Foreground = Brushes.DarkGreen,
        FontWeight = FontWeights.SemiBold,
        Text = "✓ " + text,
    };

    private static TextBlock BuildWarning(string text) => new()
    {
        Margin = new Thickness(0, 0, 0, 12),
        Foreground = Brushes.DarkRed,
        TextWrapping = TextWrapping.Wrap,
        Text = text,
    };
}
