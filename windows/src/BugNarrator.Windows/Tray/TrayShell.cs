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
    private Forms.ToolStripMenuItem? stopRecordingMenuItem;

    public TrayShell(WindowsDiagnostics diagnostics)
    {
        this.diagnostics = diagnostics;

        contextMenu = new Forms.ContextMenuStrip();
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

        startRecordingMenuItem = CreateMenuItem("Start Recording", RaiseStartRecordingRequested);
        stopRecordingMenuItem = CreateMenuItem("Stop Recording", RaiseStopRecordingRequested);
        captureScreenshotMenuItem = CreateMenuItem("Capture Screenshot", RaiseCaptureScreenshotRequested);

        contextMenu.Items.Add(statusMenuItem);
        contextMenu.Items.Add(new Forms.ToolStripSeparator());
        contextMenu.Items.Add(startRecordingMenuItem);
        contextMenu.Items.Add(stopRecordingMenuItem);
        contextMenu.Items.Add(captureScreenshotMenuItem);
        contextMenu.Items.Add(new Forms.ToolStripSeparator());
        contextMenu.Items.Add(CreateMenuItem("Show Recording Controls", RaiseShowRecordingControlsRequested));
        contextMenu.Items.Add(CreateMenuItem("Open Session Library", RaiseOpenSessionLibraryRequested));
        contextMenu.Items.Add(new Forms.ToolStripSeparator());
        contextMenu.Items.Add(CreateMenuItem("Settings", RaiseSettingsRequested));
        contextMenu.Items.Add(CreateMenuItem("About", RaiseAboutRequested));
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
