namespace BugNarrator.Windows.Services.Shell;

/// <summary>
/// The same destinations macOS declares in Sources/BugNarrator/Utilities/BugNarratorLinks.swift,
/// byte for byte, so the two platforms' menus lead to the same places. Tests pin each string.
/// </summary>
public static class BugNarratorLinks
{
    public const string Repository = "https://github.com/ABD-Enterprises/bug-narrator";
    public const string Documentation = "https://github.com/ABD-Enterprises/bug-narrator/blob/main/docs/UserGuide.md";
    public const string Issues = "https://github.com/ABD-Enterprises/bug-narrator/issues/new";
    public const string Releases = "https://github.com/ABD-Enterprises/bug-narrator/releases";
    public const string SupportDevelopment = "https://www.paypal.com/donate/?hosted_button_id=FWFQ6KCZBWWH8";
}

/// <summary>What activating a tray entry does; the tray raises the matching request.</summary>
public enum TrayMenuEntryKind
{
    Action,
    Url,
}

/// <summary>One tray menu entry as the presentation layer describes it, so tests can assert the menu without WinForms.</summary>
public sealed record TrayMenuEntry(string Label, TrayMenuEntryKind Kind, string? Url = null);
