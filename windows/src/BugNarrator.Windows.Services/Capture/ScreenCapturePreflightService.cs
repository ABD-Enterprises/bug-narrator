using BugNarrator.Core.Workflow;
using System.Runtime.InteropServices;

namespace BugNarrator.Windows.Services.Capture;

public static class NativeScreenMetrics
{
    public const int SM_CXVIRTUALSCREEN = 78;
    public const int SM_CYVIRTUALSCREEN = 79;

    [DllImport("user32.dll")]
    public static extern int GetSystemMetrics(int index);
}

public sealed class ScreenCapturePreflightService : IScreenCapturePreflightService
{
    public ScreenCapturePreflightResult CheckReady()
    {
        var width = NativeScreenMetrics.GetSystemMetrics(NativeScreenMetrics.SM_CXVIRTUALSCREEN);
        var height = NativeScreenMetrics.GetSystemMetrics(NativeScreenMetrics.SM_CYVIRTUALSCREEN);

        if (width <= 0 || height <= 0)
        {
            return new ScreenCapturePreflightResult(
                ScreenCapturePreflightStatus.Unavailable,
                CanCapture: false,
                "Screen capture is unavailable on this system.");
        }

        return new ScreenCapturePreflightResult(
            ScreenCapturePreflightStatus.Ready,
            CanCapture: true,
            "Screen capture is ready.");
    }
}
