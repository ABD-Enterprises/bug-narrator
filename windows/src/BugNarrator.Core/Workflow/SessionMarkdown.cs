namespace BugNarrator.Core.Workflow;

/// <summary>
/// Shared line joining for session markdown output. macOS joins its markdown lines with <c>\n</c>,
/// so Windows emits LF as well: the exported documents are a cross-platform contract and must not
/// vary with the host's newline convention.
/// </summary>
internal static class SessionMarkdown
{
    internal const string LineSeparator = "\n";

    internal static string Join(IEnumerable<string> lines)
    {
        return string.Join(LineSeparator, lines).TrimEnd() + LineSeparator;
    }
}
