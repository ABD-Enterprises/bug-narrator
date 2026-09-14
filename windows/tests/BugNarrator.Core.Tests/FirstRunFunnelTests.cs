using BugNarrator.Core.Workflow;
using System.Runtime.CompilerServices;
using Xunit;

namespace BugNarrator.Core.Tests;

public sealed class FirstRunFunnelTests
{
    private static readonly OnboardingSnapshot Fresh = new(
        HasUsableAiProviderCredential: false,
        ProviderConfigurationIsCompatible: true,
        MicrophoneAuthorized: false,
        HasAnyCaptureHotkeyAssigned: false);

    private static readonly OnboardingSnapshot Configured = new(
        HasUsableAiProviderCredential: true,
        ProviderConfigurationIsCompatible: true,
        MicrophoneAuthorized: true,
        HasAnyCaptureHotkeyAssigned: true);

    [Fact]
    public void Shown_OnAFreshInstall()
    {
        Assert.True(FirstRunFunnel.ShouldPresentWelcome(hasCompletedWelcome: false, sessionCount: 0, Fresh));
    }

    [Fact]
    public void NotShown_WhenTheUserAlreadyHasSessions()
    {
        // Load-bearing: hotkeys ship unbound, so nearly every existing install is "not fully
        // configured"; without this gate an upgrade would greet every long-time user with a tour.
        Assert.False(FirstRunFunnel.ShouldPresentWelcome(hasCompletedWelcome: false, sessionCount: 1, Fresh));
    }

    [Fact]
    public void NotShown_AfterCompletionOrSkip()
    {
        Assert.False(FirstRunFunnel.ShouldPresentWelcome(hasCompletedWelcome: true, sessionCount: 0, Fresh));
    }

    [Fact]
    public void NotShown_WhenEverythingIsAlreadyConfigured()
    {
        Assert.False(FirstRunFunnel.ShouldPresentWelcome(hasCompletedWelcome: false, sessionCount: 0, Configured));
        Assert.True(FirstRunFunnel.IsFullyConfigured(Configured));
    }

    [Fact]
    public void FirstIncompleteStep_FollowsProviderMicrophoneHotkeysOrder()
    {
        Assert.Equal(OnboardingStep.Provider, FirstRunFunnel.FirstIncompleteStep(Fresh));
        Assert.Equal(
            OnboardingStep.Microphone,
            FirstRunFunnel.FirstIncompleteStep(Fresh with { HasUsableAiProviderCredential = true }));
        Assert.Equal(
            OnboardingStep.Hotkeys,
            FirstRunFunnel.FirstIncompleteStep(Fresh with { HasUsableAiProviderCredential = true, MicrophoneAuthorized = true }));
        Assert.Null(FirstRunFunnel.FirstIncompleteStep(Configured));
    }

    [Fact]
    public void ProviderStep_NeedsBothACredentialAndACompatibleConfiguration()
    {
        // A credential that fails compatibility (whisper-1 on a local provider) is not a usable setup.
        var incompatible = Configured with { ProviderConfigurationIsCompatible = false };

        Assert.False(FirstRunFunnel.IsComplete(OnboardingStep.Provider, incompatible));
        Assert.Equal(OnboardingStep.Provider, FirstRunFunnel.FirstIncompleteStep(incompatible));
    }

    [Fact]
    public void OnlyTheProviderStepBlocksRecording()
    {
        Assert.Equal([OnboardingStep.Provider], FirstRunFunnel.BlockingIncompleteSteps(Fresh));
        Assert.Empty(FirstRunFunnel.BlockingIncompleteSteps(Fresh with { HasUsableAiProviderCredential = true }));
    }

    [Fact]
    public void StepTitles_MatchTheMacOnboardingStepCopy()
    {
        var swift = File.ReadAllText(Path.Combine(RepositoryRoot(), "Sources", "BugNarrator", "Utilities", "OnboardingFlow.swift"));

        foreach (var step in FirstRunFunnel.Steps)
        {
            Assert.Contains($"return \"{FirstRunFunnel.Title(step)}\"", swift, StringComparison.Ordinal);
        }

        // Same order as the Swift enum's case declarations.
        var caseOrder = FirstRunFunnel.Steps
            .Select(step => swift.IndexOf($"case {step.ToString().ToLowerInvariant()}", StringComparison.Ordinal))
            .ToList();
        Assert.All(caseOrder, index => Assert.True(index >= 0));
        Assert.Equal(caseOrder.OrderBy(index => index), caseOrder);
    }

    private static string RepositoryRoot([CallerFilePath] string sourceFilePath = "")
    {
        // <root>/windows/tests/BugNarrator.Core.Tests/<this file>
        var directory = Path.GetDirectoryName(sourceFilePath)!;
        return Path.GetFullPath(Path.Combine(directory, "..", "..", ".."));
    }
}
