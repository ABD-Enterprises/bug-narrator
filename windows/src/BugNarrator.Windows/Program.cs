using BugNarrator.Windows.Services.Diagnostics;
using System.Runtime.CompilerServices;

namespace BugNarrator.Windows;

internal static class Program
{
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

        var app = new App();
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
