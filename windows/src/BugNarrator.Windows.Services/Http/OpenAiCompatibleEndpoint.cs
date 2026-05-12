namespace BugNarrator.Windows.Services.Http;

public static class OpenAiCompatibleEndpoint
{
    private static readonly Uri DefaultBaseUri = new("https://api.openai.com/v1/");

    public static Uri Build(string? configuredBaseUrl, string relativePath)
    {
        if (string.IsNullOrWhiteSpace(relativePath))
        {
            throw new ArgumentException("Endpoint path is required.", nameof(relativePath));
        }

        var baseUri = NormalizeBaseUri(configuredBaseUrl);
        return new Uri(baseUri, relativePath.TrimStart('/'));
    }

    public static string NormalizeForStorage(string? configuredBaseUrl)
    {
        if (string.IsNullOrWhiteSpace(configuredBaseUrl))
        {
            return string.Empty;
        }

        return NormalizeBaseUri(configuredBaseUrl).ToString().TrimEnd('/');
    }

    private static Uri NormalizeBaseUri(string? configuredBaseUrl)
    {
        if (string.IsNullOrWhiteSpace(configuredBaseUrl))
        {
            return DefaultBaseUri;
        }

        if (!Uri.TryCreate(configuredBaseUrl.Trim(), UriKind.Absolute, out var parsed)
            || parsed.Scheme is not ("http" or "https"))
        {
            throw new InvalidOperationException("AI provider base URL must be an absolute HTTP or HTTPS URL.");
        }

        var builder = new UriBuilder(parsed);
        var path = builder.Path.Trim('/');
        builder.Path = string.IsNullOrWhiteSpace(path)
            ? "v1/"
            : $"{path}/";
        builder.Query = string.Empty;
        builder.Fragment = string.Empty;
        return builder.Uri;
    }
}
