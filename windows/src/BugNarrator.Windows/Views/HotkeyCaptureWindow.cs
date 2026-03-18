using BugNarrator.Windows.Services.Hotkeys;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;

namespace BugNarrator.Windows.Views;

public sealed class HotkeyCaptureWindow : Window
{
    private readonly TextBlock statusTextBlock;

    public HotkeyCaptureWindow(WindowsHotkeyAction action)
    {
        Title = $"Assign {action.DisplayName()} Hotkey";
        Width = 420;
        Height = 210;
        MinWidth = 380;
        MinHeight = 190;
        ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        Background = Brushes.White;

        statusTextBlock = new TextBlock
        {
            Margin = new Thickness(0, 14, 0, 0),
            Foreground = Brushes.DimGray,
            Text = "Press the shortcut you want to use. Include Ctrl, Alt, Shift, or Win plus a non-modifier key.",
            TextWrapping = TextWrapping.Wrap,
        };

        var cancelButton = new Button
        {
            Content = "Cancel",
            Width = 90,
            Height = 32,
        };
        cancelButton.Click += (_, _) => Close();

        Content = new Border
        {
            Padding = new Thickness(24),
            Child = new DockPanel
            {
                Children =
                {
                    new StackPanel
                    {
                        Children =
                        {
                            new TextBlock
                            {
                                FontSize = 24,
                                FontWeight = FontWeights.Bold,
                                Text = action.DisplayName(),
                            },
                            new TextBlock
                            {
                                Margin = new Thickness(0, 10, 0, 0),
                                Text = "Press the shortcut now. Escape closes this window without saving.",
                                TextWrapping = TextWrapping.Wrap,
                            },
                            new Border
                            {
                                Margin = new Thickness(0, 18, 0, 0),
                                Padding = new Thickness(14),
                                BorderBrush = Brushes.LightGray,
                                BorderThickness = new Thickness(1),
                                CornerRadius = new CornerRadius(8),
                                Child = statusTextBlock,
                            },
                        },
                    },
                    new StackPanel
                    {
                        Margin = new Thickness(0, 18, 0, 0),
                        Orientation = Orientation.Horizontal,
                        HorizontalAlignment = HorizontalAlignment.Right,
                        Children =
                        {
                            cancelButton,
                        },
                    },
                },
            },
        };

        PreviewKeyDown += OnPreviewKeyDown;
    }

    public WindowsHotkeyShortcut? CapturedShortcut { get; private set; }

    private void OnPreviewKeyDown(object sender, KeyEventArgs e)
    {
        var key = e.Key == Key.System
            ? e.SystemKey
            : e.Key;

        if (key == Key.Escape && Keyboard.Modifiers == ModifierKeys.None)
        {
            e.Handled = true;
            Close();
            return;
        }

        if (IsModifierKey(key))
        {
            statusTextBlock.Text = "Add a non-modifier key along with Ctrl, Alt, Shift, or Win.";
            e.Handled = true;
            return;
        }

        var modifiers = ToHotkeyModifiers(Keyboard.Modifiers);
        if (modifiers == WindowsHotkeyModifiers.None)
        {
            statusTextBlock.Text = "Include at least one modifier key: Ctrl, Alt, Shift, or Win.";
            e.Handled = true;
            return;
        }

        var virtualKey = KeyInterop.VirtualKeyFromKey(key);
        var shortcut = new WindowsHotkeyShortcut(virtualKey, modifiers).Normalize();
        if (!shortcut.IsValid)
        {
            statusTextBlock.Text = "That shortcut is not valid. Try again with one modifier and a non-modifier key.";
            e.Handled = true;
            return;
        }

        CapturedShortcut = shortcut;
        e.Handled = true;
        DialogResult = true;
    }

    private static bool IsModifierKey(Key key)
    {
        return key is Key.LeftAlt
            or Key.RightAlt
            or Key.LeftCtrl
            or Key.RightCtrl
            or Key.LeftShift
            or Key.RightShift
            or Key.LWin
            or Key.RWin;
    }

    private static WindowsHotkeyModifiers ToHotkeyModifiers(ModifierKeys modifiers)
    {
        var hotkeyModifiers = WindowsHotkeyModifiers.None;

        if (modifiers.HasFlag(ModifierKeys.Control))
        {
            hotkeyModifiers |= WindowsHotkeyModifiers.Control;
        }

        if (modifiers.HasFlag(ModifierKeys.Alt))
        {
            hotkeyModifiers |= WindowsHotkeyModifiers.Alt;
        }

        if (modifiers.HasFlag(ModifierKeys.Shift))
        {
            hotkeyModifiers |= WindowsHotkeyModifiers.Shift;
        }

        if (modifiers.HasFlag(ModifierKeys.Windows))
        {
            hotkeyModifiers |= WindowsHotkeyModifiers.Windows;
        }

        return hotkeyModifiers;
    }
}
