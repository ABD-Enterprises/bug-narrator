using System.Text.Json;

namespace BugNarrator.Windows.Services.Diagnostics;

public static class WindowsSmokeProbe
{
    public const string SmokeOutputArgument = "--smoke-output";

    public static bool TryWriteReport(IReadOnlyList<string> args, out int exitCode)
    {
        exitCode = 0;

        var outputPath = GetSmokeOutputPath(args);
        if (outputPath is null)
        {
            return false;
        }

        if (string.IsNullOrWhiteSpace(outputPath))
        {
            exitCode = 2;
            return true;
        }

        var outputDirectory = Path.GetDirectoryName(outputPath);
        if (!string.IsNullOrWhiteSpace(outputDirectory))
        {
            Directory.CreateDirectory(outputDirectory);
        }

        var report = new WindowsSmokeReport(
            AppName: "BugNarrator.Windows",
            Mode: "smoke",
            Version: BuildVersionDescriptionProvider.GetVersionDescription(),
            WindowsVersion: Environment.OSVersion.VersionString,
            DotNetVersion: Environment.Version.ToString(),
            GeneratedAt: DateTimeOffset.UtcNow);

        var json = JsonSerializer.Serialize(
            report,
            new JsonSerializerOptions
            {
                WriteIndented = true,
            });

        File.WriteAllText(outputPath, json);
        return true;
    }

    internal static string? GetSmokeOutputPath(IReadOnlyList<string> args)
    {
        for (var index = 0; index < args.Count; index++)
        {
            if (!string.Equals(args[index], SmokeOutputArgument, StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            return index + 1 < args.Count ? args[index + 1] : string.Empty;
        }

        return null;
    }

    public sealed record WindowsSmokeReport(
        string AppName,
        string Mode,
        string Version,
        string WindowsVersion,
        string DotNetVersion,
        DateTimeOffset GeneratedAt);
}
