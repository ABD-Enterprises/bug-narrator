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

        if (endpoint.Scheme == Uri.UriSchemeHttp && !OpenAiCompatibleEndpoint.IsLocalEndpointHost(endpoint.Host))
        {
            if (OpenAiCompatibleEndpoint.IsUnqualifiedLocalName(endpoint.Host))
            {
                return OpenAiCompatibleEndpoint.UnqualifiedLocalHostPlaintextMessage(
                    endpoint.Host, "Jira email, API token and issue content");
            }

            return "The Jira base URL uses plaintext HTTP to a host that is not an address this app "
                + $"can check as local ({endpoint.Host}). "
                + "Your Jira email, API token and issue content would cross the network unencrypted. "
                + "Use https://, or configure a trusted local endpoint in Settings.";
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
