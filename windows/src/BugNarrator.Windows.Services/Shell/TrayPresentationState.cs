using BugNarrator.Core.Workflow;

namespace BugNarrator.Windows.Services.Shell;

public sealed record TrayPresentationState(
    string StatusLabel,
    string IconText,
    bool CanStartRecording,
    bool CanStopRecording,
    bool CanCaptureScreenshot,
    // The Fix entry shown directly under the Status line while a blocker is present (#1160).
    TrayRecoveryEntry? RecoveryEntry = null)
{
    /// <summary>
    /// Whether the tray offers the bundled sample session — only while the library is empty, the
    /// rule macOS FirstRunFunnel.shouldOfferSampleSession encodes: once there is real history the
    /// offer is noise.
    /// </summary>
    public static bool ShouldOfferSampleSession(int sessionCount) => sessionCount == 0;

    /// <summary>
    /// The help-and-support block of the tray menu, in the order macOS MenuProductInfoView lists
    /// them: documentation, issue reporting, changelog, support. Documentation and Report an Issue
    /// open the same URLs macOS opens. macOS shows the changelog in an internal window and Support
    /// Development in a view whose button opens the donation page; Windows has neither surface, so
    /// both go straight to the web destination macOS ultimately exposes.
    /// </summary>
    public static IReadOnlyList<TrayMenuEntry> SupportEntries { get; } =
    [
        new TrayMenuEntry("View Documentation", TrayMenuEntryKind.Url, BugNarratorLinks.Documentation),
        new TrayMenuEntry("Report an Issue", TrayMenuEntryKind.Url, BugNarratorLinks.Issues),
        new TrayMenuEntry("View Changelog", TrayMenuEntryKind.Url, BugNarratorLinks.Releases),
        new TrayMenuEntry("Support Development", TrayMenuEntryKind.Url, BugNarratorLinks.SupportDevelopment),
    ];

    public static TrayPresentationState FromRecordingState(RecordingControlState state)
    {
        var statusLabel = state.WorkflowState switch
        {
            RecordingWorkflowState.Idle => "Status: Ready",
            RecordingWorkflowState.Recording => "Status: Recording",
            RecordingWorkflowState.Stopping => "Status: Stopping",
            RecordingWorkflowState.Saving => "Status: Saving Session",
            RecordingWorkflowState.Completed => "Status: Session Saved",
            RecordingWorkflowState.Failed => "Status: Needs Attention",
            _ => "Status: BugNarrator"
        };

        var iconText = $"BugNarrator - {statusLabel["Status: ".Length..]}";
        if (iconText.Length > 63)
        {
            iconText = iconText[..63];
        }

        return new TrayPresentationState(
            statusLabel,
            iconText,
            state.CanStart,
            state.CanStop,
            state.CanCaptureScreenshot,
            RecoveryEntryFor(state));
    }

    /// <summary>
    /// Only a state carrying a blocker gets a recovery entry; Idle and Recording never do, even if a
    /// caller left a stale blocker on them, so the menu cannot offer a fix for a problem that is over.
    /// </summary>
    public static TrayRecoveryEntry? RecoveryEntryFor(RecordingControlState state)
    {
        if (state.Blocker is not { } blocker
            || state.WorkflowState is RecordingWorkflowState.Idle or RecordingWorkflowState.Recording)
        {
            return null;
        }

        return new TrayRecoveryEntry($"Fix: {blocker.Guidance}", blocker.Category, blocker.Destination);
    }
}

/// <summary>A recovery menu entry as the presentation layer describes it; the tray routes the destination.</summary>
public sealed record TrayRecoveryEntry(string Label, RecoveryBlockerCategory Category, RecoveryDestination Destination);
