using System.Runtime.CompilerServices;
using BugNarrator.Core.Workflow;
using BugNarrator.Windows.Services.Shell;
using Xunit;

namespace BugNarrator.Windows.Tests;

public sealed class TrayPresentationStateTests
{
    [Fact]
    public void FromRecordingState_MapsIdleToStartableTrayState()
    {
        var state = RecordingControlState.Idle();

        var presentation = TrayPresentationState.FromRecordingState(state);

        Assert.Equal("Status: Ready", presentation.StatusLabel);
        Assert.Equal("BugNarrator - Ready", presentation.IconText);
        Assert.True(presentation.CanStartRecording);
        Assert.False(presentation.CanStopRecording);
        Assert.False(presentation.CanCaptureScreenshot);
    }

    [Fact]
    public void FromRecordingState_MapsRecordingToCaptureCapableTrayState()
    {
        var state = new RecordingControlState(
            RecordingWorkflowState.Recording,
            CanStart: false,
            CanStop: true,
            CanCaptureScreenshot: true,
            "Recording is active.",
            ActiveSession: null);

        var presentation = TrayPresentationState.FromRecordingState(state);

        Assert.Equal("Status: Recording", presentation.StatusLabel);
        Assert.Equal("BugNarrator - Recording", presentation.IconText);
        Assert.False(presentation.CanStartRecording);
        Assert.True(presentation.CanStopRecording);
        Assert.True(presentation.CanCaptureScreenshot);
    }

    [Fact]
    public void FromRecordingState_MapsFailuresToAttentionState()
    {
        var state = new RecordingControlState(
            RecordingWorkflowState.Failed,
            CanStart: true,
            CanStop: false,
            CanCaptureScreenshot: false,
            "Microphone is unavailable.",
            ActiveSession: null);

        var presentation = TrayPresentationState.FromRecordingState(state);

        Assert.Equal("Status: Needs Attention", presentation.StatusLabel);
        Assert.Equal("BugNarrator - Needs Attention", presentation.IconText);
        Assert.True(presentation.CanStartRecording);
        Assert.False(presentation.CanStopRecording);
        Assert.False(presentation.CanCaptureScreenshot);
    }

    [Theory]
    [InlineData(RecoveryBlockerCategory.Permission, RecoveryDestination.Settings)]
    [InlineData(RecoveryBlockerCategory.Credential, RecoveryDestination.Settings)]
    [InlineData(RecoveryBlockerCategory.Storage, RecoveryDestination.RecordingControls)]
    [InlineData(RecoveryBlockerCategory.Other, RecoveryDestination.SessionLibrary)]
    public void FromRecordingState_OffersARecoveryEntryForEachBlockerCategory(
        RecoveryBlockerCategory category, RecoveryDestination destination)
    {
        var state = new RecordingControlState(
            RecordingWorkflowState.Failed,
            CanStart: true,
            CanStop: false,
            CanCaptureScreenshot: false,
            "Something is blocking progress.",
            ActiveSession: null,
            Blocker: new RecoveryBlocker(category, "Do the thing in the right place.", destination));

        var entry = TrayPresentationState.FromRecordingState(state).RecoveryEntry;

        Assert.NotNull(entry);
        Assert.Equal("Fix: Do the thing in the right place.", entry!.Label);
        Assert.Equal(category, entry.Category);
        Assert.Equal(destination, entry.Destination);
    }

    [Fact]
    public void FromRecordingState_OffersRecoveryForACompletedSessionThatStillNeedsAProvider()
    {
        // Completed is not Failed, but a NotConfigured transcript is a refused step (#1160).
        var state = new RecordingControlState(
            RecordingWorkflowState.Completed,
            CanStart: true,
            CanStop: false,
            CanCaptureScreenshot: false,
            "Recording saved. Finish AI provider setup in Settings to enable transcription.",
            ActiveSession: null,
            Blocker: RecoveryBlocker.ProviderNotConfigured);

        var entry = TrayPresentationState.FromRecordingState(state).RecoveryEntry;

        Assert.Equal(RecoveryBlockerCategory.Credential, entry!.Category);
        Assert.Equal(RecoveryDestination.Settings, entry.Destination);
    }

    [Theory]
    [InlineData(RecordingWorkflowState.Idle)]
    [InlineData(RecordingWorkflowState.Recording)]
    public void FromRecordingState_NeverOffersRecoveryWhileIdleOrRecording(RecordingWorkflowState workflowState)
    {
        var clean = new RecordingControlState(workflowState, CanStart: true, CanStop: true, CanCaptureScreenshot: true, "ok", ActiveSession: null);
        var stale = clean with { Blocker = RecoveryBlocker.ProviderNotConfigured };

        Assert.Null(TrayPresentationState.FromRecordingState(clean).RecoveryEntry);
        Assert.Null(TrayPresentationState.FromRecordingState(stale).RecoveryEntry);
        Assert.Null(TrayPresentationState.FromRecordingState(RecordingControlState.Idle()).RecoveryEntry);
    }

    [Fact]
    public void FromRecordingState_WithoutABlocker_HasNoRecoveryEntryEvenWhenFailed()
    {
        var state = new RecordingControlState(RecordingWorkflowState.Failed, CanStart: true, CanStop: false, CanCaptureScreenshot: false, "Microphone is unavailable.", ActiveSession: null);

        Assert.Null(TrayPresentationState.FromRecordingState(state).RecoveryEntry);
    }

    [Theory]
    [InlineData(RecordingPreflightStatus.PermissionDenied, RecoveryBlockerCategory.Permission, RecoveryDestination.Settings)]
    [InlineData(RecordingPreflightStatus.DeviceUnavailable, RecoveryBlockerCategory.Other, RecoveryDestination.Settings)]
    [InlineData(RecordingPreflightStatus.CaptureSetupFailed, RecoveryBlockerCategory.Other, RecoveryDestination.Settings)]
    [InlineData(RecordingPreflightStatus.AlreadyRecording, RecoveryBlockerCategory.Other, RecoveryDestination.RecordingControls)]
    public void RecoveryBlocker_ClassifiesPreflightFailures(RecordingPreflightStatus status, RecoveryBlockerCategory category, RecoveryDestination destination)
    {
        var blocker = RecoveryBlocker.FromPreflight(status);

        Assert.NotNull(blocker);
        Assert.Equal(category, blocker!.Category);
        Assert.Equal(destination, blocker.Destination);
        Assert.Null(RecoveryBlocker.FromPreflight(RecordingPreflightStatus.Ready));
    }

    [Fact]
    public void RecoveryBlocker_ClassifiesFileSystemFailuresAsStorage()
    {
        Assert.Equal(RecoveryBlockerCategory.Storage, RecoveryBlocker.FromException(new IOException("disk full")).Category);
        Assert.Equal(RecoveryBlockerCategory.Storage, RecoveryBlocker.FromException(new UnauthorizedAccessException()).Category);
        Assert.Equal(RecoveryBlockerCategory.Other, RecoveryBlocker.FromException(new InvalidOperationException()).Category);
    }

    [Theory]
    [InlineData(0, true)]
    [InlineData(1, false)]
    [InlineData(12, false)]
    public void ShouldOfferSampleSession_OnlyWhileTheLibraryIsEmpty(int sessionCount, bool expected)
    {
        // FirstRunFunnel.shouldOfferSampleSession(libraryIsEmpty:) on macOS.
        Assert.Equal(expected, TrayPresentationState.ShouldOfferSampleSession(sessionCount));
    }

    [Fact]
    public void SupportEntries_MatchTheMacProductInfoMenuInOrder()
    {
        // MenuProductInfoView.swift lists documentation, issue reporting, changelog, support — in
        // that order. Labels are the macOS button titles; the two web entries use the macOS URLs.
        Assert.Equal(
            ["View Documentation", "Report an Issue", "View Changelog", "Support Development"],
            TrayPresentationState.SupportEntries.Select(entry => entry.Label).ToArray());
        Assert.All(TrayPresentationState.SupportEntries, entry => Assert.Equal(TrayMenuEntryKind.Url, entry.Kind));
        Assert.Equal(BugNarratorLinks.Documentation, TrayPresentationState.SupportEntries[0].Url);
        Assert.Equal(BugNarratorLinks.Issues, TrayPresentationState.SupportEntries[1].Url);
        Assert.Equal(BugNarratorLinks.Releases, TrayPresentationState.SupportEntries[2].Url);
        Assert.Equal(BugNarratorLinks.SupportDevelopment, TrayPresentationState.SupportEntries[3].Url);
    }

    /// <summary>
    /// The Windows constants are read against the macOS source of truth rather than restated, so a
    /// link changed on one platform fails here on the other.
    /// </summary>
    [Theory]
    [InlineData("documentation", BugNarratorLinks.Documentation)]
    [InlineData("issues", BugNarratorLinks.Issues)]
    [InlineData("releases", BugNarratorLinks.Releases)]
    [InlineData("supportDevelopment", BugNarratorLinks.SupportDevelopment)]
    [InlineData("repository", BugNarratorLinks.Repository)]
    public void Links_EqualTheMacConstants(string swiftName, string windowsValue)
    {
        var swiftPath = Path.Combine(RepositoryRoot(), "Sources", "BugNarrator", "Utilities", "BugNarratorLinks.swift");
        Assert.True(File.Exists(swiftPath), $"Missing macOS link source at {swiftPath}.");
        var line = File.ReadAllLines(swiftPath).Single(candidate => candidate.Contains($"static let {swiftName} = URL(string: ", StringComparison.Ordinal));
        var start = line.IndexOf('"') + 1;
        var macValue = line[start..line.IndexOf('"', start)];

        Assert.Equal(macValue, windowsValue);
    }

    [Theory]
    [InlineData("file:///C:/Windows/System32/cmd.exe")]
    [InlineData("javascript:alert(1)")]
    [InlineData("not a url")]
    public void ShellExternalLinkLauncher_RefusesAnythingButWebLinks(string url)
    {
        Assert.Throws<InvalidOperationException>(() => new ShellExternalLinkLauncher().Open(url));
    }

    private static string RepositoryRoot([CallerFilePath] string sourceFilePath = "")
    {
        // <root>/windows/tests/BugNarrator.Windows.Tests/<this file>
        var directory = Path.GetDirectoryName(sourceFilePath)!;
        return Path.GetFullPath(Path.Combine(directory, "..", "..", ".."));
    }
}
