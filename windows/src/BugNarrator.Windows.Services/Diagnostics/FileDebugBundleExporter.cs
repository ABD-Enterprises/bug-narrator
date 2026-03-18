using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using BugNarrator.Core.Models;
using BugNarrator.Windows.Services.Settings;
using BugNarrator.Windows.Services.Storage;

namespace BugNarrator.Windows.Services.Diagnostics;

public sealed class FileDebugBundleExporter : IDebugBundleExporter
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web)
    {
        WriteIndented = true,
    };

    private readonly WindowsDiagnostics diagnostics;
    private readonly string exportRootDirectory;
    private readonly string sessionsRootDirectory;
    private readonly IWindowsAppSettingsStore settingsStore;

    public FileDebugBundleExporter(
        AppStoragePaths storagePaths,
        IWindowsAppSettingsStore settingsStore,
        WindowsDiagnostics diagnostics)
    {
        exportRootDirectory = storagePaths.DebugBundlesDirectory;
        sessionsRootDirectory = storagePaths.SessionsDirectory;
        Directory.CreateDirectory(exportRootDirectory);
        this.settingsStore = settingsStore;
        this.diagnostics = diagnostics;
    }

    public async Task<string> ExportAsync(
        CompletedSession? session,
        CancellationToken cancellationToken = default)
    {
        var settings = await settingsStore.LoadAsync(cancellationToken);
        var bundleDirectory = CreateUniqueBundleDirectory();
        Directory.CreateDirectory(bundleDirectory);
        var normalizedSession = TryNormalizeSession(session);

        var systemInfo = new DebugSystemInfoDocument(
            GeneratedAt: DateTimeOffset.UtcNow,
            AppName: "BugNarrator Windows",
            VersionDescription: BuildVersionDescription(),
            WindowsVersion: Environment.OSVersion.VersionString,
            DotNetVersion: Environment.Version.ToString(),
            Architecture: RuntimeInformation.OSArchitecture.ToString(),
            ActiveTranscriptionModel: settings.EffectiveTranscriptionModel,
            IssueExtractionModel: settings.EffectiveIssueExtractionModel,
            LogFilePath: diagnostics.LogFilePath);

        var sessionMetadata = new DebugSessionMetadataDocument(
            SessionId: normalizedSession?.SessionId,
            Title: normalizedSession?.Title,
            TranscriptionStatus: normalizedSession?.TranscriptionStatus.ToString(),
            CreatedAt: normalizedSession?.CreatedAt,
            RecordingStartedAt: normalizedSession?.RecordingStartedAt,
            RecordingStoppedAt: normalizedSession?.RecordingStoppedAt,
            DurationSeconds: normalizedSession?.Duration.TotalSeconds,
            TranscriptCharacterCount: normalizedSession?.TranscriptText.Length,
            SummaryCharacterCount: normalizedSession?.ReviewSummary.Length,
            ScreenshotCount: normalizedSession?.Screenshots.Count ?? 0,
            IssueCount: normalizedSession?.IssueExtraction?.Issues.Count ?? 0,
            TimelineMomentCount: normalizedSession?.TimelineMoments.Count ?? 0,
            SessionDirectoryExists: normalizedSession is not null && Directory.Exists(normalizedSession.SessionDirectory),
            MissingScreenshotFiles: normalizedSession?.Screenshots
                .Where(screenshot => !File.Exists(screenshot.AbsolutePath))
                .Select(screenshot => screenshot.RelativePath)
                .ToArray()
                ?? Array.Empty<string>());

        await AtomicFileOperations.WriteAllTextAsync(
            Path.Combine(bundleDirectory, "system-info.json"),
            JsonSerializer.Serialize(systemInfo, JsonOptions),
            cancellationToken);
        await AtomicFileOperations.WriteAllTextAsync(
            Path.Combine(bundleDirectory, "app-version.txt"),
            $"BugNarrator Windows {systemInfo.VersionDescription}{Environment.NewLine}",
            cancellationToken);
        await AtomicFileOperations.WriteAllTextAsync(
            Path.Combine(bundleDirectory, "windows-version.txt"),
            $"{systemInfo.WindowsVersion}{Environment.NewLine}.NET {systemInfo.DotNetVersion}{Environment.NewLine}",
            cancellationToken);
        await AtomicFileOperations.WriteAllTextAsync(
            Path.Combine(bundleDirectory, "recent-log.txt"),
            await ReadRecentLogTextAsync(cancellationToken),
            cancellationToken);
        await AtomicFileOperations.WriteAllTextAsync(
            Path.Combine(bundleDirectory, "session-metadata.json"),
            JsonSerializer.Serialize(sessionMetadata, JsonOptions),
            cancellationToken);

        diagnostics.Info("debug-bundle", $"debug bundle exported to {bundleDirectory}");
        return bundleDirectory;
    }

    private async Task<string> ReadRecentLogTextAsync(CancellationToken cancellationToken)
    {
        if (!File.Exists(diagnostics.LogFilePath))
        {
            return "No Windows log file was present." + Environment.NewLine;
        }

        var allLines = await File.ReadAllLinesAsync(diagnostics.LogFilePath, cancellationToken);
        var recentLines = allLines.Length <= 400
            ? allLines
            : allLines[^400..];
        var builder = new StringBuilder();

        foreach (var line in recentLines)
        {
            builder.AppendLine(SensitiveDataRedactor.Redact(line));
        }

        return builder.ToString();
    }

    private CompletedSession? TryNormalizeSession(CompletedSession? session)
    {
        if (session is null)
        {
            return null;
        }

        try
        {
            return SessionArtifactPathPolicy.NormalizeCompletedSession(session, sessionsRootDirectory);
        }
        catch
        {
            return null;
        }
    }

    private string CreateUniqueBundleDirectory()
    {
        var timestamp = DateTimeOffset.UtcNow.ToString("yyyy-MM-dd-HHmmss");
        var directoryName = $"bugnarrator-debug-bundle-{timestamp}";
        var candidatePath = Path.Combine(exportRootDirectory, directoryName);
        var suffix = 2;

        while (Directory.Exists(candidatePath))
        {
            candidatePath = Path.Combine(exportRootDirectory, $"{directoryName}-{suffix}");
            suffix++;
        }

        return candidatePath;
    }

    private static string BuildVersionDescription()
    {
        var assembly = Assembly.GetEntryAssembly() ?? Assembly.GetExecutingAssembly();
        var informationalVersion = assembly
            .GetCustomAttribute<AssemblyInformationalVersionAttribute>()?
            .InformationalVersion;

        if (!string.IsNullOrWhiteSpace(informationalVersion))
        {
            return informationalVersion;
        }

        return assembly.GetName().Version?.ToString() ?? "0.0.0";
    }

    private sealed record DebugSystemInfoDocument(
        DateTimeOffset GeneratedAt,
        string AppName,
        string VersionDescription,
        string WindowsVersion,
        string DotNetVersion,
        string Architecture,
        string ActiveTranscriptionModel,
        string IssueExtractionModel,
        string LogFilePath);

    private sealed record DebugSessionMetadataDocument(
        Guid? SessionId,
        string? Title,
        string? TranscriptionStatus,
        DateTimeOffset? CreatedAt,
        DateTimeOffset? RecordingStartedAt,
        DateTimeOffset? RecordingStoppedAt,
        double? DurationSeconds,
        int? TranscriptCharacterCount,
        int? SummaryCharacterCount,
        int ScreenshotCount,
        int IssueCount,
        int TimelineMomentCount,
        bool SessionDirectoryExists,
        IReadOnlyList<string> MissingScreenshotFiles);
}
