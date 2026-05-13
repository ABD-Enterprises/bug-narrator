using BugNarrator.Windows.Services.Diagnostics;
using BugNarrator.Windows.Shell;
using System.Runtime.CompilerServices;

namespace BugNarrator.Windows;

internal static class Program
{
    public const string ApplicationId = "ABDEnterprises.BugNarrator.Windows";

    [ModuleInitializer]
    internal static void InitializeSmokeProbe()
    {
        if (string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable(WindowsSmokeProbe.SmokeOutputEnvironmentVariable)))
        {
            return;
        }

        RunSmokeProbe(Array.Empty<string>());
    }

    [STAThread]
    public static void Main(string[] args)
    {
        RunSmokeProbe(args);

        using var singleInstanceGuard = new EarlySingleInstanceGuard(ApplicationId);
        if (!singleInstanceGuard.TryAcquire())
        {
            Environment.Exit(0);
        }

        var app = new App();
        app.PrimarySingleInstanceService = singleInstanceGuard.TransferOwnership();
        app.InitializeComponent();
        app.Run();
    }

    private static void RunSmokeProbe(IReadOnlyList<string> args)
    {
        try
        {
            if (WindowsSmokeProbe.TryWriteReport(args, out var smokeExitCode))
            {
                Environment.Exit(smokeExitCode);
            }
        }
        catch (Exception exception)
        {
            Console.Error.WriteLine($"BugNarrator Windows smoke probe failed: {exception.Message}");
            Environment.Exit(1);
        }
    }
}
