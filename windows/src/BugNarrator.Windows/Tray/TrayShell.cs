using System.Linq;
using BugNarrator.Windows.Services.Diagnostics;
using BugNarrator.Windows.Services.Shell;
using BugNarrator.Core.Workflow;
using Drawing = System.Drawing;
using Forms = System.Windows.Forms;

namespace BugNarrator.Windows.Tray;

public sealed class TrayShell : IDisposable
{
    private readonly Forms.ContextMenuStrip contextMenu;
    private readonly WindowsDiagnostics diagnostics;
    private readonly Forms.NotifyIcon notifyIcon;
    private Forms.ToolStripMenuItem? captureScreenshotMenuItem;
    private Forms.ToolStripMenuItem? startRecordingMenuItem;
    private Forms.ToolStripMenuItem? statusMenuItem;
    private Forms.ToolStripMenuItem? recoveryMenuItem;
    private RecoveryDestination recoveryDestination = RecoveryDestination.None;
    private Forms.ToolStripMenuItem? stopRecordingMenuItem;

    public TrayShell(WindowsDiagnostics diagnostics)
    {
        this.diagnostics = diagnostics;

        contextMenu = new Forms.ContextMenuStrip();
        contextMenu.Opening += (_, _) => MenuOpening?.Invoke(this, EventArgs.Empty);
        notifyIcon = new Forms.NotifyIcon
        {
            ContextMenuStrip = contextMenu,
            Icon = Drawing.SystemIcons.Application,
            Text = "BugNarrator",
            Visible = false,
        };

        notifyIcon.MouseClick += OnNotifyIconMouseClick;
        notifyIcon.DoubleClick += (_, _) => RaiseShowRecordingControlsRequested();

        BuildMenu();
        ApplyRecordingState(RecordingControlState.Idle());
    }

    public event EventHandler? AboutRequested;
    public event EventHandler<string>? OpenLinkRequested;
    public event EventHandler? SampleSessionRequested;
    public event EventHandler? WelcomeTourRequested;
    public event EventHandler<RecoveryDestination>? RecoveryRequested;
    public event EventHandler? CheckForUpdatesRequested;
    /// <summary>Raised as the context menu opens, so state that depends on the library can be refreshed.</summary>
    public event EventHandler? MenuOpening;
    private Forms.ToolStripMenuItem? sampleSessionMenuItem;
    public event EventHandler? CaptureScreenshotRequested;
    public event EventHandler? OpenSessionLibraryRequested;
    public event EventHandler? QuitRequested;
    public event EventHandler? SettingsRequested;
    public event EventHandler? StartRecordingRequested;
    public event EventHandler? StopRecordingRequested;
    public event EventHandler? ToggleRecordingControlsRequested;
    public event EventHandler? ShowRecordingControlsRequested;

    public void Initialize()
    {
        notifyIcon.Visible = true;
        diagnostics.Info("tray", "tray shell initialized");
    }

    public void ShowWarning(string title, string message)
    {
        notifyIcon.ShowBalloonTip(
            5000,
            title,
            message,
            Forms.ToolTipIcon.Warning);
    }

    public void ApplyRecordingState(RecordingControlState state)
    {
        var presentation = TrayPresentationState.FromRecordingState(state);

        if (statusMenuItem is not null)
        {
            statusMenuItem.Text = presentation.StatusLabel;
        }

        if (recoveryMenuItem is not null)
        {
            recoveryDestination = presentation.RecoveryEntry?.Destination ?? RecoveryDestination.None;
            recoveryMenuItem.Text = presentation.RecoveryEntry?.Label ?? "Fix";
            recoveryMenuItem.Visible = presentation.RecoveryEntry is not null;
            recoveryMenuItem.Enabled = recoveryDestination != RecoveryDestination.None;
        }

        if (startRecordingMenuItem is not null)
        {
            startRecordingMenuItem.Enabled = presentation.CanStartRecording;
        }

        if (stopRecordingMenuItem is not null)
        {
            stopRecordingMenuItem.Enabled = presentation.CanStopRecording;
        }

        if (captureScreenshotMenuItem is not null)
        {
            captureScreenshotMenuItem.Enabled = presentation.CanCaptureScreenshot;
        }

        notifyIcon.Text = presentation.IconText;
    }

    public void Dispose()
    {
        notifyIcon.Visible = false;
        contextMenu.Dispose();
        notifyIcon.Dispose();
    }

    private void BuildMenu()
    {
        statusMenuItem = CreateMenuItem("Status: Ready", () => { });
        statusMenuItem.Enabled = false;
        recoveryMenuItem = CreateMenuItem("Fix", () => RecoveryRequested?.Invoke(this, recoveryDestination));
        recoveryMenuItem.Visible = false;

        startRecordingMenuItem = CreateMenuItem("Start Recording", RaiseStartRecordingRequested);
        stopRecordingMenuItem = CreateMenuItem("Stop Recording", RaiseStopRecordingRequested);
        captureScreenshotMenuItem = CreateMenuItem("Capture Screenshot", RaiseCaptureScreenshotRequested);

        contextMenu.Items.Add(statusMenuItem);
        contextMenu.Items.Add(recoveryMenuItem);
        contextMenu.Items.Add(new Forms.ToolStripSeparator());
        contextMenu.Items.Add(startRecordingMenuItem);
        contextMenu.Items.Add(stopRecordingMenuItem);
        contextMenu.Items.Add(captureScreenshotMenuItem);
        contextMenu.Items.Add(new Forms.ToolStripSeparator());
        contextMenu.Items.Add(CreateMenuItem("Show Recording Controls", RaiseShowRecordingControlsRequested));
        contextMenu.Items.Add(CreateMenuItem("Open Session Library", RaiseOpenSessionLibraryRequested));
        // The macOS menu-bar offer (MenuBarView+SampleOffer.swift); hidden until the shell says the library is empty.
        sampleSessionMenuItem = CreateMenuItem("See a Sample Session", () => SampleSessionRequested?.Invoke(this, EventArgs.Empty));
        sampleSessionMenuItem.Visible = false;
        contextMenu.Items.Add(sampleSessionMenuItem);
        contextMenu.Items.Add(new Forms.ToolStripSeparator());
        contextMenu.Items.Add(CreateMenuItem("Settings", RaiseSettingsRequested));
        contextMenu.Items.Add(CreateMenuItem("About", RaiseAboutRequested));
        contextMenu.Items.Add(new Forms.ToolStripSeparator());
        // macOS Help > Show Welcome Tour: the first-run tour is reopenable from here at any time.
        contextMenu.Items.Add(CreateMenuItem("Show Welcome Tour", () => WelcomeTourRequested?.Invoke(this, EventArgs.Empty)));
        foreach (var entry in TrayPresentationState.SupportEntries)
        {
            var url = entry.Url!;
            contextMenu.Items.Add(CreateMenuItem(entry.Label, () => OpenLinkRequested?.Invoke(this, url)));
        }

        contextMenu.Items.Add(CreateMenuItem(
            TrayPresentationState.CheckForUpdatesEntry.Label,
            () => CheckForUpdatesRequested?.Invoke(this, EventArgs.Empty)));

        contextMenu.Items.Add(new Forms.ToolStripSeparator());
        contextMenu.Items.Add(CreateMenuItem("Quit", RaiseQuitRequested));
    }

    private void OnNotifyIconMouseClick(object? sender, Forms.MouseEventArgs eventArgs)
    {
        if (eventArgs.Button == Forms.MouseButtons.Left)
        {
            RaiseToggleRecordingControlsRequested();
        }
    }

    private Forms.ToolStripMenuItem CreateMenuItem(string text, Action onClick)
    {
        var menuItem = new Forms.ToolStripMenuItem(text);
        menuItem.Click += (_, _) => onClick();
        return menuItem;
    }

    /// <summary>
    /// The menu as a screen reader will read it: every item's Text (its UIA name) in order, with
    /// separators as null. Exposed so AccessibleNameAuditTests can audit the tray without WinForms UI.
    /// </summary>
    public IReadOnlyList<string?> MenuItemTexts =>
        contextMenu.Items.Cast<Forms.ToolStripItem>().Select(item => item is Forms.ToolStripSeparator ? null : item.Text).ToArray();

    public void SetSampleSessionOfferVisible(bool visible)
    {
        if (sampleSessionMenuItem is not null)
        {
            sampleSessionMenuItem.Visible = visible;
        }
    }

    /// <summary>Replaces the status line until the next presentation update.</summary>
    public void ShowStatus(string text)
    {
        if (statusMenuItem is not null)
        {
            statusMenuItem.Text = text;
        }
    }

    private void RaiseAboutRequested()
    {
        diagnostics.Info("tray", "about requested");
        AboutRequested?.Invoke(this, EventArgs.Empty);
    }

    private void RaiseCaptureScreenshotRequested()
    {
        diagnostics.Info("tray", "capture screenshot requested");
        CaptureScreenshotRequested?.Invoke(this, EventArgs.Empty);
    }

    private void RaiseOpenSessionLibraryRequested()
    {
        diagnostics.Info("tray", "open session library requested");
        OpenSessionLibraryRequested?.Invoke(this, EventArgs.Empty);
    }

    private void RaiseQuitRequested()
    {
        diagnostics.Info("tray", "quit requested");
        QuitRequested?.Invoke(this, EventArgs.Empty);
    }

    private void RaiseSettingsRequested()
    {
        diagnostics.Info("tray", "settings requested");
        SettingsRequested?.Invoke(this, EventArgs.Empty);
    }

    private void RaiseStartRecordingRequested()
    {
        diagnostics.Info("tray", "start recording requested");
        StartRecordingRequested?.Invoke(this, EventArgs.Empty);
    }

    private void RaiseStopRecordingRequested()
    {
        diagnostics.Info("tray", "stop recording requested");
        StopRecordingRequested?.Invoke(this, EventArgs.Empty);
    }

    private void RaiseToggleRecordingControlsRequested()
    {
        diagnostics.Info("tray", "toggle recording controls requested");
        ToggleRecordingControlsRequested?.Invoke(this, EventArgs.Empty);
    }

    private void RaiseShowRecordingControlsRequested()
    {
        diagnostics.Info("tray", "show recording controls requested");
        ShowRecordingControlsRequested?.Invoke(this, EventArgs.Empty);
    }
}
