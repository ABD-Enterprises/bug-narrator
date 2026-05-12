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
}
