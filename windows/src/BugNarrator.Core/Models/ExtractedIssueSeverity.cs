namespace BugNarrator.Core.Models;

/// <summary>
/// Triage severity for an extracted issue. Mirrors the macOS `ExtractedIssueSeverity`
/// (Sources/BugNarrator/Models/IssueCoreSubtypes.swift), including its `Medium` default.
/// </summary>
public enum ExtractedIssueSeverity
{
    Critical,
    High,
    Medium,
    Low,
}
