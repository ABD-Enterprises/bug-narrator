namespace BugNarrator.Core.Workflow;

/// <summary>
/// Shared line joining for session markdown output. macOS joins its markdown lines with <c>\n</c>
/// and adds no trailing newline, so Windows does the same: these documents are a cross-platform
/// contract, byte-compared against <c>contract-fixtures/</c>, and must not vary with the host's
/// newline convention or gain an extra terminator.
/// </summary>
internal static class SessionMarkdown
{
    internal const string LineSeparator = "\n";

    internal static string Join(IEnumerable<string> lines)
    {
        return string.Join(LineSeparator, lines).TrimEnd();
    }
}
