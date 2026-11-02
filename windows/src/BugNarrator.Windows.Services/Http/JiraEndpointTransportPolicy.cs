namespace BugNarrator.Windows.Services.Http;

public static class JiraEndpointTransportPolicy
{
    public static string? CompatibilityIssue(Uri? endpoint)
    {
        if (endpoint is null || !endpoint.IsAbsoluteUri
            || endpoint.Scheme is not ("http" or "https"))
        {
            return "The Jira base URL must be an absolute HTTP or HTTPS URL. Update it in Settings.";
        }

        // The host is read as it was written: .NET rewrites a number written
        // in another notation into the address it stands for, and the macOS
        // port refuses those spellings.
        var host = OpenAiCompatibleEndpoint.HostAsWritten(endpoint) ?? endpoint.Host;

        if (endpoint.Scheme == Uri.UriSchemeHttp && !OpenAiCompatibleEndpoint.IsLocalEndpointHost(host))
        {
            // The same sentence the warning next to the setting shows, built
            // by the same helper: one host gets one answer.
            return OpenAiCompatibleEndpoint.PlaintextTransportRefusal(
                host, "This Jira URL", "email, API token and issue content", "server");
        }

        return null;
    }

    public static void RequireCompatible(Uri? endpoint)
    {
        if (CompatibilityIssue(endpoint) is { } issue)
        {
            throw new InvalidOperationException(issue);
        }
    }
}
