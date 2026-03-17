namespace BugNarrator.Core.Export;

public sealed record SessionBundleManifest(
    string TranscriptMarkdownPath,
    string ScreenshotsDirectoryPath
);
