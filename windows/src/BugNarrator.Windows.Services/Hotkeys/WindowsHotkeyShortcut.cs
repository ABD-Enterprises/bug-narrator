namespace BugNarrator.Windows.Services.Hotkeys;

public readonly record struct WindowsHotkeyShortcut(int VirtualKey, WindowsHotkeyModifiers Modifiers)
{
    private const WindowsHotkeyModifiers SupportedModifiers =
        WindowsHotkeyModifiers.Alt
        | WindowsHotkeyModifiers.Control
        | WindowsHotkeyModifiers.Shift
        | WindowsHotkeyModifiers.Windows;

    public static WindowsHotkeyShortcut NotSet => default;

    public WindowsHotkeyModifiers EffectiveModifiers => Modifiers & SupportedModifiers;

    public bool IsConfigured => VirtualKey != 0 || EffectiveModifiers != WindowsHotkeyModifiers.None;

    public bool IsNotSet => !IsConfigured;

    public bool IsValid => VirtualKey != 0
                           && EffectiveModifiers != WindowsHotkeyModifiers.None
                           && !IsModifierKey(VirtualKey);

    public WindowsHotkeyShortcut Normalize()
    {
        return new WindowsHotkeyShortcut(VirtualKey, EffectiveModifiers);
    }

    public string DisplayString
    {
        get
        {
            if (IsNotSet)
            {
                return "Not Set";
            }

            var parts = new List<string>();
            var effectiveModifiers = EffectiveModifiers;

            if (effectiveModifiers.HasFlag(WindowsHotkeyModifiers.Control))
            {
                parts.Add("Ctrl");
            }

            if (effectiveModifiers.HasFlag(WindowsHotkeyModifiers.Alt))
            {
                parts.Add("Alt");
            }

            if (effectiveModifiers.HasFlag(WindowsHotkeyModifiers.Shift))
            {
                parts.Add("Shift");
            }

            if (effectiveModifiers.HasFlag(WindowsHotkeyModifiers.Windows))
            {
                parts.Add("Win");
            }

            if (VirtualKey != 0)
            {
                parts.Add(GetKeyDisplayName(VirtualKey));
            }

            return parts.Count == 0
                ? "Not Set"
                : string.Join("+", parts);
        }
    }

    public static bool IsModifierKey(int virtualKey)
    {
        return virtualKey is 0x10 or 0x11 or 0x12 or 0x5B or 0x5C or 0xA0 or 0xA1 or 0xA2 or 0xA3 or 0xA4 or 0xA5;
    }

    private static string GetKeyDisplayName(int virtualKey)
    {
        if (virtualKey is >= 0x30 and <= 0x39)
        {
            return ((char)virtualKey).ToString();
        }

        if (virtualKey is >= 0x41 and <= 0x5A)
        {
            return ((char)virtualKey).ToString();
        }

        if (virtualKey is >= 0x70 and <= 0x87)
        {
            return $"F{virtualKey - 0x6F}";
        }

        if (virtualKey is >= 0x60 and <= 0x69)
        {
            return $"Num {virtualKey - 0x60}";
        }

        return virtualKey switch
        {
            0x08 => "Backspace",
            0x09 => "Tab",
            0x0D => "Enter",
            0x14 => "Caps Lock",
            0x1B => "Esc",
            0x20 => "Space",
            0x21 => "Page Up",
            0x22 => "Page Down",
            0x23 => "End",
            0x24 => "Home",
            0x25 => "Left",
            0x26 => "Up",
            0x27 => "Right",
            0x28 => "Down",
            0x2C => "Print Screen",
            0x2D => "Insert",
            0x2E => "Delete",
            0x6A => "Num *",
            0x6B => "Num +",
            0x6D => "Num -",
            0x6E => "Num .",
            0x6F => "Num /",
            0x90 => "Num Lock",
            0x91 => "Scroll Lock",
            0xA0 => "Left Shift",
            0xA1 => "Right Shift",
            0xA2 => "Left Ctrl",
            0xA3 => "Right Ctrl",
            0xA4 => "Left Alt",
            0xA5 => "Right Alt",
            0x5B => "Left Win",
            0x5C => "Right Win",
            _ => $"Key {virtualKey}",
        };
    }
}
