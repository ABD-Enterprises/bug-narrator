using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Automation;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
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
using BugNarrator.Windows.Services.Shell;
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
    [Theory]
    [InlineData(96, 440, 80)]
    [InlineData(192, 220, 190)]
    public void AnnotationPreview_DragAndKeyboardRespectTheAspectFitImageAndClampMovement(double dpiX, double expectedWidth, double expectedLeft)
    {
        OnStaThread(() =>
        {
            using var harness = new WindowHarness();
            var screenshot = CreateAnnotationScreenshot(harness.RootDirectory, dpiX);
            var annotation = new IssueScreenshotAnnotation(Guid.NewGuid(), screenshot.ScreenshotId, "Target", 0.1, 0.2, 0.3, 0.4, 0.85);
            var editor = new IssueScreenshotAnnotationEditor(screenshot, [annotation]);
            editor.Measure(new Size(600, 500));
            editor.Arrange(new Rect(0, 0, 600, 500));
            editor.RenderOverlays();
            var frame = editor.ImageFrame;
            // PNG stores resolution as integer pixels/metre, so nonsquare DPI has subpixel rounding.
            Assert.InRange(frame.Width, expectedWidth - 0.1, expectedWidth + 0.1);
            Assert.Equal(220, frame.Height, 4);
            Assert.InRange(frame.X, expectedLeft - 0.1, expectedLeft + 0.1);
            var thumb = Assert.Single(Descendants(editor).OfType<Thumb>());
            Assert.Equal(frame.X + 0.1 * frame.Width, Canvas.GetLeft(thumb), 4);

            thumb.RaiseEvent(new DragDeltaEventArgs(frame.Width * 0.1, frame.Height * 0.1));
            var moved = Assert.Single(editor.Annotations);
            Assert.Equal(0.2, moved.X, 4);
            Assert.Equal(0.3, moved.Y, 4);
            Assert.True(editor.MoveWithKey(annotation.AnnotationId, Key.Right, ModifierKeys.Shift));
            Assert.Equal(0.2 + 10.0 / frame.Width, Assert.Single(editor.Annotations).X, 4);
            thumb.RaiseEvent(new DragDeltaEventArgs(10000, -10000));
            moved = Assert.Single(editor.Annotations);
            Assert.Equal(0.7, moved.X, 4);
            Assert.Equal(0, moved.Y);
            Assert.Equal(annotation.AnnotationId, moved.AnnotationId);
            Assert.Equal(annotation.Confidence, moved.Confidence);
            Assert.Equal(0.1, annotation.X);
            Assert.False(string.IsNullOrWhiteSpace(AutomationProperties.GetName(thumb)));
            return true;
        });
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void AnnotationPreview_MissingOrCorruptImageKeepsMetadataAndOffersNamedRemoval(bool writeCorruptFile)
    {
        OnStaThread(() =>
        {
            using var harness = new WindowHarness();
            var screenshot = ReviewSessionTestData.CreateScreenshot(harness.RootDirectory, writeFile: writeCorruptFile);
            var annotation = new IssueScreenshotAnnotation(Guid.NewGuid(), screenshot.ScreenshotId, "Target", 0, 0, 0.3, 0.4);
            var editor = new IssueScreenshotAnnotationEditor(screenshot, [annotation]);
            var window = new Window { Content = editor };
            try
            {
                Assert.Same(annotation, Assert.Single(editor.Annotations));
                Assert.Contains(Descendants(editor).OfType<TextBlock>(), text => text.Text.Contains("preview unavailable"));
                Assert.Empty(AccessibleNameAudit.Run(window));
                var remove = Assert.Single(Descendants(editor).OfType<Button>());
                Assert.Contains("Target", AutomationProperties.GetName(remove));
                remove.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
                Assert.Empty(editor.Annotations);
            }
            finally
            {
                window.Close();
            }
            return true;
        });
    }

    [Fact]
    public async Task SessionLibrary_AnnotationEditsRoundTripThroughSaveAndSessionStorage()
    {
        using var harness = new WindowHarness();
        var edited = OnStaThread(() =>
        {
            var screenshot = CreateAnnotationScreenshot(harness.RootDirectory);
            var first = new IssueScreenshotAnnotation(Guid.NewGuid(), screenshot.ScreenshotId, "First", 0.1, 0.2, 0.3, 0.4, 0.85);
            var removed = new IssueScreenshotAnnotation(Guid.NewGuid(), screenshot.ScreenshotId, "Second", 0.5, 0.5, 0.2, 0.2);
            var unrelated = new IssueScreenshotAnnotation(Guid.NewGuid(), Guid.NewGuid(), "Unavailable", 0, 0, 0.5, 0.5);
            var extraction = ReviewSessionTestData.CreateIssueExtractionResult();
            var issue = extraction.Issues[0] with
            {
                RelatedScreenshotIds = [screenshot.ScreenshotId],
                ScreenshotAnnotations = [first, removed, unrelated],
            };
            var session = ReviewSessionTestData.CreateCompletedSession(harness.RootDirectory,
                screenshots: [screenshot], issueExtraction: extraction with { Issues = [issue] });
            var actions = new FakeReviewActions();
            var window = new SessionLibraryWindow(new FakeSessionStore { Sessions = [session] }, actions, new FakeSettingsStore(), harness.Diagnostics());
            try
            {
                window.RaiseEvent(new RoutedEventArgs(FrameworkElement.LoadedEvent));
                var editor = Assert.Single(Descendants(window).OfType<IssueScreenshotAnnotationEditor>());
                editor.Measure(new Size(600, 500));
                editor.Arrange(new Rect(0, 0, 600, 500));
                editor.MoveAnnotationPixels(first.AnnotationId, editor.ImageFrame.Width * 0.1, 0);
                var remove = Descendants(editor).OfType<Button>().Single(button => AutomationProperties.GetName(button).Contains("Second"));
                remove.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
                Assert.Empty(AccessibleNameAudit.Run(window));
                var save = Descendants(window).OfType<Button>().Single(button => Equals(button.Content, "Save Review"));
                save.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
                Assert.NotNull(actions.LastSavedSession);
                return (Session: actions.LastSavedSession!, First: first, Removed: removed, Unrelated: unrelated);
            }
            finally
            {
                window.Close();
            }
        });
        var paths = new AppStoragePaths(harness.RootDirectory, Path.Combine(harness.RootDirectory, "Sessions"), Path.Combine(harness.RootDirectory, "Logs"));
        var store = new FileCompletedSessionStore(paths);
        await store.SaveAsync(edited.Session);
        var saved = Assert.Single(await store.GetAllAsync());
        var annotations = Assert.Single(saved.IssueExtraction!.Issues).ScreenshotAnnotations;
        var moved = Assert.Single(annotations, item => item.AnnotationId == edited.First.AnnotationId);
        Assert.Equal(0.2, moved.X, 4);
        Assert.Equal(edited.First.Confidence, moved.Confidence);
        Assert.DoesNotContain(annotations, item => item.AnnotationId == edited.Removed.AnnotationId);
        Assert.Contains(annotations, item => item.AnnotationId == edited.Unrelated.AnnotationId);
    }

    private static ScreenshotArtifact CreateAnnotationScreenshot(string root, double dpiX = 96)
    {
        var screenshot = ReviewSessionTestData.CreateScreenshot(root, writeFile: false) with { Width = 400, Height = 200 };
        var bitmap = BitmapSource.Create(400, 200, dpiX, 96, PixelFormats.Bgra32, null, new byte[400 * 200 * 4], 400 * 4);
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(bitmap));
        using var stream = File.Create(screenshot.AbsolutePath);
        encoder.Save(stream);
        return screenshot;
    }

    [Fact]
    public void RecordingControls_OffersRecoveryAndSettingsAndDisablesRetryWhileBusy()
    {
        OnStaThread(() =>
        {
            using var harness = new WindowHarness();
            var saved = ReviewSessionTestData.CreateCompletedSession(harness.RootDirectory) with
            {
                TranscriptText = string.Empty,
                TranscriptionStatus = SessionTranscriptionStatus.NotConfigured,
            };
            var lifecycle = new FakeLifecycleService
            {
                CurrentState = RecordingControlState.Idle() with { SavedSession = saved },
            };
            var settingsOpened = false;
            var window = new RecordingControlsWindow(lifecycle, harness.Diagnostics(), () => { }, () => settingsOpened = true);
            try
            {
                var buttons = Descendants(window).OfType<Button>().ToDictionary(button => (string)button.Content);
                var retry = buttons["Retry Transcription"];
                Assert.True(retry.IsVisible || retry.Visibility == Visibility.Visible);
                Assert.True(retry.IsEnabled);
                Assert.Contains(Descendants(window).OfType<TextBlock>(), text => text.Text.Contains(saved.Title));
                buttons["Open Settings"].RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
                Assert.True(settingsOpened);
                retry.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
                Assert.Equal(1, lifecycle.RetryCalls);

                lifecycle.Publish(lifecycle.CurrentState with { CanStart = false, WorkflowState = RecordingWorkflowState.Saving });
                Assert.False(retry.IsEnabled);
                lifecycle.Publish(lifecycle.CurrentState with
                {
                    CanStart = true,
                    SavedSession = saved with { TranscriptionStatus = SessionTranscriptionStatus.Completed },
                });
                Assert.Equal(Visibility.Collapsed, ((StackPanel)LogicalTreeHelper.GetParent(retry)).Visibility);
                Assert.Empty(AccessibleNameAudit.Run(window));
            }
            finally
            {
                window.Close();
            }
            return true;
        });
    }

    private static IEnumerable<DependencyObject> Descendants(DependencyObject parent)
    {
        foreach (var child in LogicalTreeHelper.GetChildren(parent).OfType<DependencyObject>())
        {
            yield return child;
            foreach (var descendant in Descendants(child))
            {
                yield return descendant;
            }
        }
    }

    [Fact]
    public void SessionLibrary_RecoveryUpdatesOnlyItsSessionAndKeepsUnsavedIssueEdits()
    {
        OnStaThread(() =>
        {
            using var harness = new WindowHarness();
            var first = ReviewSessionTestData.CreateCompletedSession(harness.RootDirectory,
                issueExtraction: ReviewSessionTestData.CreateIssueExtractionResult()) with
            {
                CreatedAt = DateTimeOffset.Now,
                TranscriptionStatus = SessionTranscriptionStatus.NotConfigured,
                TranscriptText = string.Empty,
            };
            var second = ReviewSessionTestData.CreateCompletedSession(harness.RootDirectory) with
            {
                CreatedAt = first.CreatedAt.AddMinutes(-1),
            };
            var store = new FakeSessionStore { Sessions = [first, second] };
            var window = new SessionLibraryWindow(store, new FakeReviewActions(), new FakeSettingsStore(), harness.Diagnostics());
            try
            {
                window.RaiseEvent(new RoutedEventArgs(FrameworkElement.LoadedEvent));
                var title = Descendants(window).OfType<TextBox>().Single(text => text.Text == first.IssueExtraction!.Issues[0].Title);
                title.Text = "Unsaved review edit";
                window.ApplyRecoveredSession(second with { TranscriptText = "Second recovered transcript." });
                Assert.Equal("Unsaved review edit", title.Text);
                Assert.Contains(title, Descendants(window).OfType<TextBox>());

                window.ApplyRecoveredSession(first with { TranscriptionStatus = SessionTranscriptionStatus.Completed, TranscriptText = "Recovered transcript." });
                var textBoxes = Descendants(window).OfType<TextBox>().ToArray();
                Assert.Contains(textBoxes, text => text.Text == "Unsaved review edit");
                Assert.Contains(textBoxes, text => text.Text == "Recovered transcript.");
                var sessionList = Descendants(window).OfType<ListBox>().Single(list => list.Items.Count == 2);
                sessionList.SelectedIndex = 1;
                Assert.Contains(Descendants(window).OfType<TextBox>(), text => text.Text == "Second recovered transcript.");
            }
            finally
            {
                window.Close();
            }
            return true;
        });
    }

    public static IEnumerable<object[]> Windows()
    {
        yield return ["SettingsWindow"];
        yield return ["RecordingControlsWindow"];
        yield return ["SessionLibraryWindow"];
        yield return ["AboutWindow"];
        yield return ["HotkeyCaptureWindow"];
        yield return ["WelcomeWindow"];
    }

    /// <summary>
    /// WIN-038 (#1180): the Local (Parakeet) section follows the macOS localServerControls rules, and a
    /// server answering on 8422 that this app did not start disables Start and is never stopped.
    /// </summary>
    [Fact]
    public void SettingsWindow_LocalServerSection_FollowsTheMacControlRules()
    {
        var (texts, enabled) = OnStaThread(() =>
        {
            using var harness = new WindowHarness();
            var manager = new FakeLocalServerManager();
            var window = new SettingsWindow(
                new FakeSettingsStore(), new FakeSecretStore(), new FakeTranscriptionClient(),
                new FakeHotkeyService(), harness.Diagnostics(), new FakeDeviceCatalog(), new FakeLaunchAtLogin(),
                manager, new FakeLocalServerProbe());
            try
            {
                var buttons = window.LocalServerButtonsForTests.ToDictionary(button => (string)button.Content, button => button);

                // Not installed, no package yet: only Download (disabled) and Check server download.
                window.ApplyLocalServerState(manager.State);
                var initial = (buttons["Download the local transcription server"].IsEnabled, buttons["Check server download"].Visibility);

                // Installed and idle, but something else answers on 8422: Start disabled.
                window.SetLocalServerReachableForTests(true);
                window.ApplyLocalServerState(manager.State with { Installed = true });
                var foreign = (buttons["Start local server"].IsEnabled, buttons["Remove local server and models"].IsEnabled);

                // Installed, running and reachable: Stop enabled, Remove disabled.
                window.ApplyLocalServerState(manager.State with { Installed = true, Running = true });
                var startStop = buttons["Start local server"];
                var running = ((string)startStop.Content, startStop.IsEnabled, buttons["Remove local server and models"].IsEnabled);

                // Downloading: progress + Cancel visible.
                window.ApplyLocalServerState(manager.State with { Busy = true, Progress = 0.4 });
                var downloading = buttons["Cancel installation"].Visibility;

                return ((initial, foreign, running, downloading), manager.Stops);
            }
            finally
            {
                window.Close();
            }
        });

        Assert.Equal((false, Visibility.Visible), texts.initial);
        Assert.Equal((false, true), texts.foreign);
        Assert.Equal(("Stop local server", true, false), texts.running);
        Assert.Equal(Visibility.Visible, texts.downloading);
        Assert.Equal(0, enabled);
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
                    new FakeHotkeyService(), diagnostics, new FakeDeviceCatalog(), new FakeLaunchAtLogin(),
                    new FakeLocalServerManager(), new FakeLocalServerProbe()),
                "RecordingControlsWindow" => new RecordingControlsWindow(new FakeLifecycleService(), diagnostics, () => { }),
                "SessionLibraryWindow" => new SessionLibraryWindow(new FakeSessionStore(), new FakeReviewActions(), new FakeSettingsStore(), diagnostics),
                "AboutWindow" => new AboutWindow(),
                "HotkeyCaptureWindow" => new HotkeyCaptureWindow(WindowsHotkeyAction.StartRecording),
                "WelcomeWindow" => BuildWelcomeWindowWithEveryStepRendered(diagnostics),
                _ => throw new ArgumentOutOfRangeException(nameof(windowName), windowName, "unknown window"),
            };
        }

        /// <summary>
        /// The tour renders one step at a time, so a single audit would only see the provider
        /// step. Walk all three (with nothing configured, so every action button is present) and
        /// return the window on the last one; the audit of the earlier steps runs here.
        /// </summary>
        private static Window BuildWelcomeWindowWithEveryStepRendered(WindowsDiagnostics diagnostics)
        {
            var window = new WelcomeWindow(
                new FakeSettingsStore(), new FakeSecretStore(), new FakeHotkeyService(),
                new FakeMicrophonePreflight(), new FakeDeviceCatalog(), diagnostics, () => { });
            var earlierViolations = new List<AccessibleNameAudit.Violation>();
            for (var step = 0; step < FirstRunFunnel.Steps.Count - 1; step++)
            {
                window.RenderStepForAudit(step);
                earlierViolations.AddRange(AccessibleNameAudit.Run(window));
            }

            window.RenderStepForAudit(FirstRunFunnel.Steps.Count - 1);
            Assert.True(earlierViolations.Count == 0, string.Join("\n", earlierViolations));
            return window;
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

    internal sealed class FakeLocalServerManager : BugNarrator.Windows.Services.LocalTranscription.ILocalTranscriptionServerManager
    {
        public BugNarrator.Windows.Services.LocalTranscription.LocalTranscriptionServerState State { get; set; } =
            new(Package: null, Progress: null, Busy: false, Installed: false, Running: false, Message: string.Empty);
        public event EventHandler<BugNarrator.Windows.Services.LocalTranscription.LocalTranscriptionServerState>? StateChanged { add { } remove { } }
        public string InstallDirectory => @"C:\Users\tester\AppData\Local\BugNarrator\LocalTranscription";
        public int Stops { get; private set; }
        public int Starts { get; private set; }
        public Task DiscoverAsync(CancellationToken cancellationToken = default) => Task.CompletedTask;
        public Task InstallAndStartAsync(CancellationToken cancellationToken = default) => Task.CompletedTask;
        public Task StartAsync(CancellationToken cancellationToken = default) { Starts++; return Task.CompletedTask; }
        public void Stop() => Stops++;
        public Task ShutdownAsync() => Task.CompletedTask;
        public void Remove() { }
    }

    internal sealed class FakeLocalServerProbe : BugNarrator.Windows.Services.LocalTranscription.ILocalServerHealthProbe
    {
        public bool Reachable { get; set; }
        public Task<bool> IsReachableAsync(string baseUrl, CancellationToken cancellationToken = default) => Task.FromResult(Reachable);
    }

    private sealed class FakeLaunchAtLogin : ILaunchAtLoginService
    {
        public LaunchAtLoginStatus CurrentStatus() => LaunchAtLoginStatus.Disabled;
        public LaunchAtLoginStatus SetEnabled(bool enabled) => enabled ? LaunchAtLoginStatus.Enabled : LaunchAtLoginStatus.Disabled;
    }

    private sealed class FakeMicrophonePreflight : BugNarrator.Windows.Services.Permissions.IMicrophonePreflightService
    {
        public RecordingPreflightResult CheckReadyToRecord(bool isAlreadyRecording, int deviceNumber) =>
            new(RecordingPreflightStatus.Ready, CanStart: true, "Microphone ready.");
    }

    private sealed class FakeDeviceCatalog : IAudioInputDeviceCatalog
    {
        public IReadOnlyList<AudioInputDeviceOption> GetAvailableInputDevices() => [];
    }

    private sealed class FakeLifecycleService : IRecordingLifecycleService, IRecordingRecoveryService
    {
        public RecordingControlState CurrentState { get; set; } = RecordingControlState.Idle();
        public event EventHandler<RecordingControlState>? StateChanged;
        public int RetryCalls { get; private set; }
        public void Publish(RecordingControlState state) { CurrentState = state; StateChanged?.Invoke(this, state); }
        public Task RefreshRecoveryAsync(CancellationToken cancellationToken = default) => Task.CompletedTask;
        public Task RetrySavedTranscriptionAsync(CancellationToken cancellationToken = default) { RetryCalls++; return Task.CompletedTask; }
        public Task<CompletedSession> RetryTranscriptionAsync(CompletedSession session, CancellationToken cancellationToken = default) => Task.FromResult(session);
        public Task StartRecordingAsync(CancellationToken cancellationToken = default) => Task.CompletedTask;
        public Task StopRecordingAsync(CancellationToken cancellationToken = default) => Task.CompletedTask;
        public Task<ScreenshotCaptureResult> CaptureScreenshotAsync(CancellationToken cancellationToken = default) => throw new NotSupportedException();
        public void Dispose() { }
    }

    private sealed class FakeSessionStore : ICompletedSessionStore
    {
        public IReadOnlyList<CompletedSession> Sessions { get; set; } = [];
        public string SessionsDirectory => Path.GetTempPath();
        public Task<IReadOnlyList<CompletedSession>> GetAllAsync(CancellationToken cancellationToken = default) => Task.FromResult(Sessions);
        public Task SaveAsync(CompletedSession session, CancellationToken cancellationToken = default) => Task.CompletedTask;
        public Task DeleteAsync(CompletedSession session, CancellationToken cancellationToken = default) => Task.CompletedTask;
    }

    private sealed class FakeReviewActions : IReviewSessionActionService
    {
        public CompletedSession? LastSavedSession { get; private set; }
        public Task<CompletedSession> SaveSessionAsync(CompletedSession session, CancellationToken cancellationToken = default)
        {
            LastSavedSession = session;
            return Task.FromResult(session);
        }
        public Task DeleteSessionAsync(CompletedSession session, CancellationToken cancellationToken = default) => Task.CompletedTask;
        public Task<CompletedSession> RetryTranscriptionAsync(CompletedSession session, CancellationToken cancellationToken = default) => Task.FromResult(session);
        public Task<CompletedSession> ExtractIssuesAsync(CompletedSession session, CancellationToken cancellationToken = default) => Task.FromResult(session);
        public Task<IReadOnlyList<IssueExportResult>> ExportSelectedIssuesToGitHubAsync(CompletedSession session, CancellationToken cancellationToken = default) => Task.FromResult<IReadOnlyList<IssueExportResult>>([]);
        public Task<IReadOnlyList<IssueExportResult>> ExportSelectedIssuesToJiraAsync(CompletedSession session, CancellationToken cancellationToken = default) => Task.FromResult<IReadOnlyList<IssueExportResult>>([]);
        public Task<string> ExportSessionBundleAsync(CompletedSession session, CancellationToken cancellationToken = default) => Task.FromResult(string.Empty);
        public Task<string> ExportDebugBundleAsync(CompletedSession? session, CancellationToken cancellationToken = default) => Task.FromResult(string.Empty);
    }
}
