using BugNarrator.Windows.Services.Http;
using Xunit;

namespace BugNarrator.Windows.Tests;

public sealed class OpenAiCompatibleEndpointTests
{
    [Fact]
    public void Build_WithBlankBaseUrl_UsesOpenAiDefault()
    {
        var endpoint = OpenAiCompatibleEndpoint.Build(string.Empty, "chat/completions");

        Assert.Equal("https://api.openai.com/v1/chat/completions", endpoint.AbsoluteUri);
    }

    [Fact]
    public void Build_WithRootBaseUrl_AppendsV1Path()
    {
        var endpoint = OpenAiCompatibleEndpoint.Build("https://ai.example.test", "audio/transcriptions");

        Assert.Equal("https://ai.example.test/v1/audio/transcriptions", endpoint.AbsoluteUri);
    }

    [Fact]
    public void Build_WithVersionedBaseUrl_PreservesConfiguredPath()
    {
        var endpoint = OpenAiCompatibleEndpoint.Build("http://localhost:11434/v1", "/models");

        Assert.Equal("http://localhost:11434/v1/models", endpoint.AbsoluteUri);
    }

    [Theory]
    [InlineData("https://api.example.com/v1")]   // remote HTTPS
    [InlineData("http://localhost:1234/v1")]      // loopback HTTP
    [InlineData("http://127.0.0.1:8422")]
    [InlineData("http://192.168.1.50:1234")]      // private network
    [InlineData("http://10.0.0.5:8080")]
    [InlineData("http://lmstudio:1234")]          // single-label host
    [InlineData("http://nas.local:1234")]
    [InlineData("")]
    public void PlaintextRemoteWarning_AllowsHttpsAndLocalHttp(string baseUrl)
    {
        Assert.Null(OpenAiCompatibleEndpoint.PlaintextRemoteWarning(baseUrl));
    }

    [Theory]
    [InlineData("http://api.example.com/v1")]
    [InlineData("http://203.0.113.10:8080")]
    public void PlaintextRemoteWarning_WarnsForPlaintextRemoteHost(string baseUrl)
    {
        Assert.NotNull(OpenAiCompatibleEndpoint.PlaintextRemoteWarning(baseUrl));
    }

    [Theory]
    [InlineData("localhost")]
    [InlineData("127.0.0.1")]
    [InlineData("10.1.2.3")]
    [InlineData("172.16.0.1")]
    [InlineData("172.31.255.1")]
    [InlineData("192.168.0.1")]
    [InlineData("169.254.1.1")]
    [InlineData("myserver.local")]
    [InlineData("lmstudio")]
    [InlineData("::1")]
    public void IsLocalEndpointHost_DetectsLocalHosts(string host)
    {
        Assert.True(OpenAiCompatibleEndpoint.IsLocalEndpointHost(host));
    }

    [Theory]
    [InlineData("api.openai.com")]
    [InlineData("8.8.8.8")]
    [InlineData("172.32.0.1")]
    [InlineData("example.com")]
    public void IsLocalEndpointHost_RejectsRemoteHosts(string host)
    {
        Assert.False(OpenAiCompatibleEndpoint.IsLocalEndpointHost(host));
    }
}
