using System.Windows;
using System.Windows.Controls;
using System.Windows.Threading;
using BugNarrator.Core.Models;
using BugNarrator.Core.Workflow;
using BugNarrator.Windows.Accessibility;
using BugNarrator.Windows.Services.Audio;
using BugNarrator.Windows.Services.Diagnostics;
using BugNarrator.Windows.Services.Hotkeys;
using BugNarrator.Windows.Services.Review;
using BugNarrator.Windows.Services.Secrets;
using BugNarrator.Windows.Services.Settings;
using BugNarrator.Windows.Services.Storage;
using BugNarrator.Windows.Services.Transcription;
using BugNarrator.Windows.Views;
using Xunit;

namespace BugNarrator.Windows.Tests;

/// <summary>
/// The product spec's Accessibility Contract requires explicit labels for controls that are not
/// self-describing from visible text. The views are built in C#, so the check constructs each real
/// window on an STA thread — never shown — and walks it with AccessibleNameAudit.
/// </summary>
public sealed class AccessibleNameAuditTests
{
    public static IEnumerable<object[]> Windows()
    {
        yield return ["SettingsWindow"];
        yield return ["RecordingControlsWindow"];
        yield return ["SessionLibraryWindow"];
        yield return ["AboutWindow"];
        yield return ["HotkeyCaptureWindow"];
    }

    [Theory]
    [MemberData(nameof(Windows))]
    public void EveryInteractiveControlHasAnAccessibleName(string windowName)
    {
        var violations = OnStaThread(() =>
        {
            using var harness = new WindowHarness();
            var window = harness.Build(windowName);
            try
            {
                return AccessibleNameAudit.Run(window);
            }
            finally
            {
                window.Close();
            }
        });

        Assert.True(
            violations.Count == 0,
            $"{violations.Count} control(s) without an accessible name:\n  " + string.Join("\n  ", violations));
    }

    /// <summary>
    /// The issue editors are built when a session with extracted issues is presented, after the
    /// constructor's labeling pass — so an empty-store audit alone would miss them. This presents a
    /// session with an extracted issue and audits the rendered editor.
    /// </summary>
    [Fact]
    public void SessionLibrary_IssueEditorsRenderedForASessionAreLabeled()
    {
        var violations = OnStaThread(() =>
        {
            using var harness = new WindowHarness();
            var window = (SessionLibraryWindow)harness.Build("SessionLibraryWindow");
            try
            {
                window.PresentSessionForReview(ReviewSessionTestData.CreateCompletedSession(
                    harness.RootDirectory,
                    issueExtraction: ReviewSessionTestData.CreateIssueExtractionResult()));
                return AccessibleNameAudit.Run(window);
            }
            finally
            {
                window.Close();
            }
        });

        Assert.True(
            violations.Count == 0,
            $"{violations.Count} rendered editor control(s) without an accessible name:\n  " + string.Join("\n  ", violations));
    }

    /// <summary>
    /// The tray is WinForms, not WPF: a ToolStripMenuItem's Text is its UIA name, so the audit is
    /// that every non-separator item has one. The icon is never shown (Visible stays false until
    /// Initialize), so constructing the shell is safe on the STA thread.
    /// </summary>
    [Fact]
    public void TrayMenu_EveryItemHasVisibleText()
    {
        var texts = OnStaThread(() =>
        {
            using var harness = new WindowHarness();
            using var tray = new BugNarrator.Windows.Tray.TrayShell(harness.Diagnostics());
            return tray.MenuItemTexts;
        });

        var items = texts.Where(text => text is not null).ToArray();
        Assert.NotEmpty(items);
        Assert.All(items, text => Assert.False(string.IsNullOrWhiteSpace(text), "a tray item has no text"));
        // The entries a keyboard user reaches with Win+B → arrow keys, in order.
        Assert.Contains("Show Recording Controls", items);
        Assert.Contains("Open Session Library", items);
        Assert.Contains("Quit", items);
    }

    /// <summary>
    /// Proves the auditor reaches nested content: an unlabeled TextBox three levels deep inside a
    /// StackPanel inside a GroupBox must be reported with its path. Weakening the descent makes this
    /// fail.
    /// </summary>
    [Fact]
    public void Audit_FindsAnUnlabeledControlNestedThreeLevelsDeep()
    {
        var violations = OnStaThread(() =>
        {
            var window = new Window
            {
                Content = new GroupBox
                {
                    Header = "Provider",
                    Content = new StackPanel
                    {
                        Children =
                        {
                            new TextBlock { Text = "API key" },
                            new StackPanel { Children = { new TextBox() } },
                        },
                    },
                },
            };
            return AccessibleNameAudit.Run(window);
        });

        var violation = Assert.Single(violations);
        Assert.Equal("Window", violation.WindowType);
        Assert.Equal("TextBox", violation.ControlType);
        Assert.Contains("GroupBox", violation.Path);
        Assert.Contains("StackPanel", violation.Path);
    }

    [Fact]
    public void Audit_AcceptsVisibleTextForButtonsAndNamesOrLabelsForInputs()
    {
        var violations = OnStaThread(() =>
        {
            var label = new TextBlock { Text = "Repository owner" };
            var labelled = new TextBox();
            System.Windows.Automation.AutomationProperties.SetLabeledBy(labelled, label);
            var named = new PasswordBox();
            System.Windows.Automation.AutomationProperties.SetName(named, "GitHub token");
            var window = new Window
            {
                Content = new StackPanel
                {
                    Children =
                    {
                        new Button { Content = "Save" },
                        new CheckBox { Content = "Enable" },
                        label,
                        labelled,
                        named,
                        // Typed content is not a name.
                        new TextBox { Text = "typed text" },
                        // An icon-only button needs a name.
                        new Button { Content = new System.Windows.Shapes.Ellipse() },
                    },
                },
            };
            return AccessibleNameAudit.Run(window);
        });

        Assert.Equal(["TextBox", "Button"], violations.Select(violation => violation.ControlType).ToArray());
    }

    [Fact]
    public void Audit_ChecksHyperlinksWhichAreContentElementsNotControls()
    {
        var violations = OnStaThread(() =>
        {
            var textLink = new System.Windows.Documents.Hyperlink(new System.Windows.Documents.Run("View documentation"));
            var namedIconLink = new System.Windows.Documents.Hyperlink(new System.Windows.Documents.InlineUIContainer(new System.Windows.Shapes.Ellipse()));
            System.Windows.Automation.AutomationProperties.SetName(namedIconLink, "Open the release page");
            var emptyLink = new System.Windows.Documents.Hyperlink();
            var iconOnlyLink = new System.Windows.Documents.Hyperlink(new System.Windows.Documents.InlineUIContainer(new System.Windows.Shapes.Ellipse()));

            var window = new Window
            {
                Content = new StackPanel
                {
                    Children =
                    {
                        new TextBlock { Inlines = { textLink } },
                        new TextBlock { Inlines = { namedIconLink } },
                        new TextBlock { Inlines = { emptyLink } },
                        new TextBlock { Inlines = { iconOnlyLink } },
                    },
                },
            };
            return AccessibleNameAudit.Run(window);
        });

        // Only the empty and the icon-only links are reported.
        Assert.Equal(2, violations.Count);
        Assert.All(violations, violation => Assert.Equal("Hyperlink", violation.ControlType));
    }

    private static T OnStaThread<T>(Func<T> body)
    {
        T? result = default;
        Exception? failure = null;
        var thread = new Thread(() =>
        {
            try
            {
                result = body();
            }
            catch (Exception exception)
            {
                failure = exception;
            }
            finally
            {
                Dispatcher.CurrentDispatcher.InvokeShutdown();
            }
        });
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        thread.Join();
        if (failure is not null)
        {
            throw new InvalidOperationException("STA body failed: " + failure.Message, failure);
        }

        return result!;
    }

    private sealed class WindowHarness : IDisposable
    {
        private readonly string rootDirectory = Path.Combine(Path.GetTempPath(), "BugNarrator.Windows.Tests", Guid.NewGuid().ToString("N"));

        public string RootDirectory => rootDirectory;

        public WindowsDiagnostics Diagnostics()
        {
            var storagePaths = new AppStoragePaths(
                RootDirectory: rootDirectory,
                SessionsDirectory: Path.Combine(rootDirectory, "Sessions"),
                LogsDirectory: Path.Combine(rootDirectory, "Logs"));
            Directory.CreateDirectory(storagePaths.LogsDirectory);
            return new WindowsDiagnostics(storagePaths);
        }

        public Window Build(string windowName)
        {
            var storagePaths = new AppStoragePaths(
                RootDirectory: rootDirectory,
                SessionsDirectory: Path.Combine(rootDirectory, "Sessions"),
                LogsDirectory: Path.Combine(rootDirectory, "Logs"));
            Directory.CreateDirectory(storagePaths.LogsDirectory);
            var diagnostics = new WindowsDiagnostics(storagePaths);

            return windowName switch
            {
                "SettingsWindow" => new SettingsWindow(
                    new FakeSettingsStore(), new FakeSecretStore(), new FakeTranscriptionClient(),
                    new FakeHotkeyService(), diagnostics, new FakeDeviceCatalog()),
                "RecordingControlsWindow" => new RecordingControlsWindow(new FakeLifecycleService(), diagnostics, () => { }),
                "SessionLibraryWindow" => new SessionLibraryWindow(new FakeSessionStore(), new FakeReviewActions(), diagnostics),
                "AboutWindow" => new AboutWindow(),
                "HotkeyCaptureWindow" => new HotkeyCaptureWindow(WindowsHotkeyAction.StartRecording),
                _ => throw new ArgumentOutOfRangeException(nameof(windowName), windowName, "unknown window"),
            };
        }

        public void Dispose()
        {
            if (Directory.Exists(rootDirectory))
            {
                Directory.Delete(rootDirectory, recursive: true);
            }
        }
    }

    private sealed class FakeSettingsStore : IWindowsAppSettingsStore
    {
        public ValueTask<WindowsAppSettings> LoadAsync(CancellationToken cancellationToken = default) => ValueTask.FromResult(WindowsAppSettings.Default);
        public ValueTask SaveAsync(WindowsAppSettings settings, CancellationToken cancellationToken = default) => ValueTask.CompletedTask;
    }

    private sealed class FakeSecretStore : ISecretStore
    {
        public ValueTask<string?> GetAsync(string key, CancellationToken cancellationToken = default) => ValueTask.FromResult<string?>(null);
        public ValueTask SetAsync(string key, string value, CancellationToken cancellationToken = default) => ValueTask.CompletedTask;
        public ValueTask RemoveAsync(string key, CancellationToken cancellationToken = default) => ValueTask.CompletedTask;
    }

    private sealed class FakeTranscriptionClient : ITranscriptionClient
    {
        public Task<string> TranscribeToTextAsync(string audioFilePath, string apiKey, OpenAiTranscriptionRequest request, CancellationToken cancellationToken = default) => Task.FromResult(string.Empty);
        public Task ValidateApiKeyAsync(string apiKey, string? providerBaseUrl = null, CancellationToken cancellationToken = default) => Task.CompletedTask;
    }

    private sealed class FakeHotkeyService : IWindowsGlobalHotkeyService
    {
        public WindowsHotkeyRuntimeSnapshot CurrentSnapshot => WindowsHotkeyRuntimeSnapshot.Empty;
        public event EventHandler<WindowsHotkeyRuntimeSnapshot>? StateChanged { add { } remove { } }
        public Task<WindowsHotkeyRuntimeSnapshot> InitializeAsync(CancellationToken cancellationToken = default) => Task.FromResult(WindowsHotkeyRuntimeSnapshot.Empty);
        public Task<WindowsHotkeyRuntimeSnapshot> ApplySettingsAsync(WindowsAppSettings settings, CancellationToken cancellationToken = default) => Task.FromResult(WindowsHotkeyRuntimeSnapshot.Empty);
        public void Dispose() { }
    }

    private sealed class FakeDeviceCatalog : IAudioInputDeviceCatalog
    {
        public IReadOnlyList<AudioInputDeviceOption> GetAvailableInputDevices() => [];
    }

    private sealed class FakeLifecycleService : IRecordingLifecycleService
    {
        public RecordingControlState CurrentState => RecordingControlState.Idle();
        public event EventHandler<RecordingControlState>? StateChanged { add { } remove { } }
        public Task StartRecordingAsync(CancellationToken cancellationToken = default) => Task.CompletedTask;
        public Task StopRecordingAsync(CancellationToken cancellationToken = default) => Task.CompletedTask;
        public Task<ScreenshotCaptureResult> CaptureScreenshotAsync(CancellationToken cancellationToken = default) => throw new NotSupportedException();
        public void Dispose() { }
    }

    private sealed class FakeSessionStore : ICompletedSessionStore
    {
        public Task<IReadOnlyList<CompletedSession>> GetAllAsync(CancellationToken cancellationToken = default) => Task.FromResult<IReadOnlyList<CompletedSession>>([]);
        public Task SaveAsync(CompletedSession session, CancellationToken cancellationToken = default) => Task.CompletedTask;
        public Task DeleteAsync(CompletedSession session, CancellationToken cancellationToken = default) => Task.CompletedTask;
    }

    private sealed class FakeReviewActions : IReviewSessionActionService
    {
        public Task<CompletedSession> SaveSessionAsync(CompletedSession session, CancellationToken cancellationToken = default) => Task.FromResult(session);
        public Task DeleteSessionAsync(CompletedSession session, CancellationToken cancellationToken = default) => Task.CompletedTask;
        public Task<CompletedSession> RetryTranscriptionAsync(CompletedSession session, CancellationToken cancellationToken = default) => Task.FromResult(session);
        public Task<CompletedSession> ExtractIssuesAsync(CompletedSession session, CancellationToken cancellationToken = default) => Task.FromResult(session);
        public Task<IReadOnlyList<IssueExportResult>> ExportSelectedIssuesToGitHubAsync(CompletedSession session, CancellationToken cancellationToken = default) => Task.FromResult<IReadOnlyList<IssueExportResult>>([]);
        public Task<IReadOnlyList<IssueExportResult>> ExportSelectedIssuesToJiraAsync(CompletedSession session, CancellationToken cancellationToken = default) => Task.FromResult<IReadOnlyList<IssueExportResult>>([]);
        public Task<string> ExportSessionBundleAsync(CompletedSession session, CancellationToken cancellationToken = default) => Task.FromResult(string.Empty);
        public Task<string> ExportDebugBundleAsync(CompletedSession? session, CancellationToken cancellationToken = default) => Task.FromResult(string.Empty);
    }
}
