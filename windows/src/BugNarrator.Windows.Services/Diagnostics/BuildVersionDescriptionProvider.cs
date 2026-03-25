using System.Reflection;

namespace BugNarrator.Windows.Services.Diagnostics;

public static class BuildVersionDescriptionProvider
{
    public static string GetVersionDescription(Assembly? assembly = null)
    {
        assembly ??= Assembly.GetEntryAssembly() ?? Assembly.GetExecutingAssembly();
        var informationalVersion = assembly
            .GetCustomAttribute<AssemblyInformationalVersionAttribute>()?
            .InformationalVersion;

        if (!string.IsNullOrWhiteSpace(informationalVersion))
        {
            return informationalVersion;
        }

        return assembly.GetName().Version?.ToString() ?? "0.0.0";
    }
}
