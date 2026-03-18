using System.Net.Http;

namespace BugNarrator.Windows.Services.Http;

internal static class RemoteServiceRequestGuard
{
    public static async Task<HttpResponseMessage> SendAsync(
        HttpClient httpClient,
        HttpRequestMessage request,
        string serviceName,
        CancellationToken cancellationToken = default)
    {
        try
        {
            return await httpClient.SendAsync(request, cancellationToken);
        }
        catch (OperationCanceledException exception) when (!cancellationToken.IsCancellationRequested)
        {
            throw new InvalidOperationException(
                $"{serviceName} timed out. Check the network connection and try again.",
                exception);
        }
        catch (HttpRequestException exception)
        {
            throw new InvalidOperationException(
                $"BugNarrator could not reach {serviceName}. Check the network connection and try again.",
                exception);
        }
    }
}
