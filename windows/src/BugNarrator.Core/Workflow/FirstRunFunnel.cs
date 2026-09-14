namespace BugNarrator.Core.Workflow;

/// <summary>
/// The steps a first-run user is walked through, in presentation order. Mirrors the macOS
/// OnboardingStep enum (Utilities/OnboardingFlow.swift): the provider step comes first because it is
/// the only one that gates recording; microphone and hotkeys improve the experience but never block it.
/// </summary>
public enum OnboardingStep
{
    Provider,
    Microphone,
    Hotkeys,
}

/// <summary>
/// A snapshot of everything the flow needs, as plain values, so the gating logic is testable
/// without a window or a settings store. Mirrors macOS OnboardingSnapshot.
/// </summary>
/// <param name="HasUsableAiProviderCredential">A credential is saved, or the provider needs none.</param>
/// <param name="ProviderConfigurationIsCompatible">WindowsAppSettings.AiProviderCompatibilityIssue is null.</param>
/// <param name="MicrophoneAuthorized">True only for a confirmed working microphone; "not yet checked" maps to false.</param>
/// <param name="HasAnyCaptureHotkeyAssigned">At least one capture hotkey is assigned.</param>
public sealed record OnboardingSnapshot(
    bool HasUsableAiProviderCredential,
    bool ProviderConfigurationIsCompatible,
    bool MicrophoneAuthorized,
    bool HasAnyCaptureHotkeyAssigned);

/// <summary>
/// Pure step-gating for the first-run welcome flow. Every decision the welcome window makes lives
/// here, as macOS OnboardingFlow does, so it is unit-testable without WPF.
/// </summary>
public static class FirstRunFunnel
{
    public static IReadOnlyList<OnboardingStep> Steps { get; } =
        [OnboardingStep.Provider, OnboardingStep.Microphone, OnboardingStep.Hotkeys];

    /// <summary>Titles copied verbatim from macOS OnboardingStep.title.</summary>
    public static string Title(OnboardingStep step) => step switch
    {
        OnboardingStep.Provider => "Choose an AI provider",
        OnboardingStep.Microphone => "Allow microphone access",
        OnboardingStep.Hotkeys => "Set capture hotkeys",
        _ => throw new ArgumentOutOfRangeException(nameof(step), step, null),
    };

    /// <summary>Whether skipping this step leaves the user unable to record. Only the provider step does.</summary>
    public static bool BlocksRecording(OnboardingStep step) => step == OnboardingStep.Provider;

    public static bool IsComplete(OnboardingStep step, OnboardingSnapshot snapshot) => step switch
    {
        // Both halves matter: a credential that fails compatibility (for example whisper-1 selected
        // on a local provider) is not a usable setup even though the credential check passes.
        OnboardingStep.Provider => snapshot.HasUsableAiProviderCredential && snapshot.ProviderConfigurationIsCompatible,
        OnboardingStep.Microphone => snapshot.MicrophoneAuthorized,
        OnboardingStep.Hotkeys => snapshot.HasAnyCaptureHotkeyAssigned,
        _ => throw new ArgumentOutOfRangeException(nameof(step), step, null),
    };

    /// <summary>The first step still needing attention, or null when everything is set.</summary>
    public static OnboardingStep? FirstIncompleteStep(OnboardingSnapshot snapshot)
    {
        foreach (var step in Steps)
        {
            if (!IsComplete(step, snapshot))
            {
                return step;
            }
        }

        return null;
    }

    public static bool IsFullyConfigured(OnboardingSnapshot snapshot) => FirstIncompleteStep(snapshot) is null;

    /// <summary>
    /// Steps that still block recording if left undone — what a skip warning should name, rather
    /// than warning about every incomplete step.
    /// </summary>
    public static IReadOnlyList<OnboardingStep> BlockingIncompleteSteps(OnboardingSnapshot snapshot) =>
        Steps.Where(step => BlocksRecording(step) && !IsComplete(step, snapshot)).ToList();

    /// <summary>
    /// Whether to present the welcome flow unprompted at startup. Three independent reasons not
    /// to, as on macOS (OnboardingFlow.shouldPresentOnLaunch): the user has already been through it
    /// or skipped it, they already have recorded sessions, or there is nothing left to tell them.
    /// The session gate is load-bearing: hotkeys ship unbound, so nearly every existing install is
    /// "not fully configured", and without it an upgrade would greet every long-time user with a tour.
    /// </summary>
    public static bool ShouldPresentWelcome(bool hasCompletedWelcome, int sessionCount, OnboardingSnapshot snapshot)
    {
        if (hasCompletedWelcome || sessionCount > 0)
        {
            return false;
        }

        return !IsFullyConfigured(snapshot);
    }
}
