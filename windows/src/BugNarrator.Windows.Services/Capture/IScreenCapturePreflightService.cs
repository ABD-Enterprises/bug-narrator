using BugNarrator.Core.Workflow;

namespace BugNarrator.Windows.Services.Capture;

public interface IScreenCapturePreflightService
{
    ScreenCapturePreflightResult CheckReady();
}
