using System.ComponentModel;
using System.Runtime.InteropServices;
using BugNarrator.Windows.Services.Hotkeys;
using Forms = System.Windows.Forms;

namespace BugNarrator.Windows.Hotkeys;

public sealed class Win32GlobalHotkeyPlatform : Forms.NativeWindow, IWindowsHotkeyPlatform
{
    private const int ModNoRepeat = 0x4000;
    private const int WmHotkey = 0x0312;

    private readonly HashSet<WindowsHotkeyAction> registeredActions = [];
    private bool disposed;

    public Win32GlobalHotkeyPlatform()
    {
        CreateHandle(new Forms.CreateParams
        {
            Caption = "BugNarratorHotkeySink",
        });
    }

    public event EventHandler<WindowsHotkeyAction>? HotkeyPressed;

    public WindowsHotkeyRegistrationAttempt Register(WindowsHotkeyAction action, WindowsHotkeyShortcut shortcut)
    {
        if (disposed)
        {
            return new WindowsHotkeyRegistrationAttempt(
                IsRegistered: false,
                Message: $"Windows could not register {action.DisplayName()} because the hotkey platform is already disposed.");
        }

        Unregister(action);

        if (shortcut.IsNotSet)
        {
            return new WindowsHotkeyRegistrationAttempt(
                IsRegistered: true,
                Message: $"{action.DisplayName()} is not assigned.");
        }

        var modifiers = (uint)shortcut.EffectiveModifiers | ModNoRepeat;
        var registered = RegisterHotKey(Handle, (int)action, modifiers, (uint)shortcut.VirtualKey);
        if (!registered)
        {
            var errorCode = Marshal.GetLastWin32Error();
            return new WindowsHotkeyRegistrationAttempt(
                IsRegistered: false,
                Message: BuildRegistrationFailureMessage(action, shortcut, errorCode),
                Win32ErrorCode: errorCode);
        }

        registeredActions.Add(action);
        return new WindowsHotkeyRegistrationAttempt(
            IsRegistered: true,
            Message: $"{action.DisplayName()} is active globally as {shortcut.DisplayString}.");
    }

    public void Unregister(WindowsHotkeyAction action)
    {
        if (disposed || Handle == IntPtr.Zero)
        {
            registeredActions.Remove(action);
            return;
        }

        if (!registeredActions.Remove(action))
        {
            return;
        }

        UnregisterHotKey(Handle, (int)action);
    }

    public void UnregisterAll()
    {
        foreach (var action in registeredActions.ToArray())
        {
            Unregister(action);
        }
    }

    public void Dispose()
    {
        if (disposed)
        {
            return;
        }

        disposed = true;
        UnregisterAll();
        DestroyHandle();
        GC.SuppressFinalize(this);
    }

    protected override void WndProc(ref Forms.Message m)
    {
        if (m.Msg == WmHotkey
            && Enum.IsDefined(typeof(WindowsHotkeyAction), m.WParam.ToInt32()))
        {
            HotkeyPressed?.Invoke(this, (WindowsHotkeyAction)m.WParam.ToInt32());
        }

        base.WndProc(ref m);
    }

    private static string BuildRegistrationFailureMessage(
        WindowsHotkeyAction action,
        WindowsHotkeyShortcut shortcut,
        int errorCode)
    {
        return errorCode switch
        {
            1409 => $"Windows could not register {shortcut.DisplayString} for {action.DisplayName()} because another app is already using that shortcut.",
            87 => $"Windows rejected {shortcut.DisplayString} for {action.DisplayName()} because that shortcut is not valid on this system.",
            _ => $"Windows could not register {shortcut.DisplayString} for {action.DisplayName()} (Win32 error {errorCode}: {new Win32Exception(errorCode).Message}).",
        };
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UnregisterHotKey(IntPtr hWnd, int id);
}
