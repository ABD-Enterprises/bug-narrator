using BugNarrator.Windows.Services.Diagnostics;
using Drawing = System.Drawing;
using Forms = System.Windows.Forms;

namespace BugNarrator.Windows.Tray;

public sealed class TrayShell : IDisposable
{
    private readonly Forms.ContextMenuStrip contextMenu;
    private readonly WindowsDiagnostics diagnostics;
    private readonly Forms.NotifyIcon notifyIcon;

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

        notifyIcon.DoubleClick += (_, _) => RaiseShowRecordingControlsRequested();

        BuildMenu();
    }

    public event EventHandler? AboutRequested;
    public event EventHandler? OpenSessionLibraryRequested;
    public event EventHandler? QuitRequested;
    public event EventHandler? SettingsRequested;
    public event EventHandler? ShowRecordingControlsRequested;

    public void Initialize()
    {
        notifyIcon.Visible = true;
        diagnostics.Info("tray", "tray shell initialized");
    }

    public void Dispose()
    {
        notifyIcon.Visible = false;
        contextMenu.Dispose();
        notifyIcon.Dispose();
    }

    private void BuildMenu()
    {
        contextMenu.Items.Add(CreateMenuItem("Show Recording Controls", RaiseShowRecordingControlsRequested));
        contextMenu.Items.Add(CreateMenuItem("Open Session Library", RaiseOpenSessionLibraryRequested));
        contextMenu.Items.Add(new Forms.ToolStripSeparator());
        contextMenu.Items.Add(CreateMenuItem("Settings", RaiseSettingsRequested));
        contextMenu.Items.Add(CreateMenuItem("About", RaiseAboutRequested));
        contextMenu.Items.Add(new Forms.ToolStripSeparator());
        contextMenu.Items.Add(CreateMenuItem("Quit", RaiseQuitRequested));
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

    private void RaiseShowRecordingControlsRequested()
    {
        diagnostics.Info("tray", "show recording controls requested");
        ShowRecordingControlsRequested?.Invoke(this, EventArgs.Empty);
    }
}
