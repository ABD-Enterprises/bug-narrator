using BugNarrator.Windows.Services.Settings;

namespace BugNarrator.Windows.Services.Hotkeys;

public static class WindowsHotkeySettingsValidator
{
    public static IReadOnlyList<WindowsHotkeyValidationIssue> Validate(WindowsAppSettings settings)
    {
        return Validate(settings.GetHotkeyAssignments());
    }

    public static IReadOnlyList<WindowsHotkeyValidationIssue> Validate(
        IReadOnlyDictionary<WindowsHotkeyAction, WindowsHotkeyShortcut> assignments)
    {
        var issues = new Dictionary<WindowsHotkeyAction, WindowsHotkeyValidationIssue>();

        foreach (var action in WindowsHotkeyActionExtensions.All)
        {
            var shortcut = assignments.TryGetValue(action, out var configuredShortcut)
                ? configuredShortcut.Normalize()
                : WindowsHotkeyShortcut.NotSet;

            if (shortcut.IsNotSet)
            {
                continue;
            }

            if (shortcut.EffectiveModifiers == WindowsHotkeyModifiers.None)
            {
                issues[action] = new WindowsHotkeyValidationIssue(
                    action,
                    WindowsHotkeyRegistrationState.Invalid,
                    $"{action.DisplayName()} must include at least one modifier key.");
                continue;
            }

            if (shortcut.VirtualKey == 0)
            {
                issues[action] = new WindowsHotkeyValidationIssue(
                    action,
                    WindowsHotkeyRegistrationState.Invalid,
                    $"{action.DisplayName()} needs a non-modifier key in addition to its modifiers.");
                continue;
            }

            if (WindowsHotkeyShortcut.IsModifierKey(shortcut.VirtualKey))
            {
                issues[action] = new WindowsHotkeyValidationIssue(
                    action,
                    WindowsHotkeyRegistrationState.Invalid,
                    $"{action.DisplayName()} cannot use only a modifier key.");
            }
        }

        var duplicateGroups = WindowsHotkeyActionExtensions.All
            .Where(action => !issues.ContainsKey(action))
            .Select(action => new
            {
                Action = action,
                Shortcut = assignments.TryGetValue(action, out var shortcut)
                    ? shortcut.Normalize()
                    : WindowsHotkeyShortcut.NotSet,
            })
            .Where(entry => !entry.Shortcut.IsNotSet)
            .GroupBy(entry => entry.Shortcut)
            .Where(group => group.Count() > 1);

        foreach (var duplicateGroup in duplicateGroups)
        {
            var members = duplicateGroup.ToArray();

            foreach (var member in members)
            {
                var otherActionNames = members
                    .Where(entry => entry.Action != member.Action)
                    .Select(entry => entry.Action.DisplayName())
                    .OrderBy(name => name)
                    .ToArray();

                issues[member.Action] = new WindowsHotkeyValidationIssue(
                    member.Action,
                    WindowsHotkeyRegistrationState.Conflict,
                    $"{member.Shortcut.DisplayString} is already assigned to {string.Join(" and ", otherActionNames)}.");
            }
        }

        return WindowsHotkeyActionExtensions.All
            .Where(action => issues.ContainsKey(action))
            .Select(action => issues[action])
            .ToArray();
    }
}
