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
    [InlineData("")]
    public void PlaintextRemoteWarning_AllowsHttpsAndLocalHttp(string baseUrl)
    {
        Assert.Null(OpenAiCompatibleEndpoint.PlaintextRemoteWarning(baseUrl));
    }

    [Theory]
    [InlineData("http://api.example.com/v1")]
    [InlineData("http://203.0.113.10:8080")]
    [InlineData("http://lmstudio:1234")]          // single-label host
    [InlineData("http://nas.local:1234")]
    public void PlaintextRemoteWarning_WarnsForPlaintextRemoteHost(string baseUrl)
    {
        Assert.NotNull(OpenAiCompatibleEndpoint.PlaintextRemoteWarning(baseUrl));
    }

    [Theory]
    [InlineData("localhost")]
    [InlineData("LOCALHOST")]
    [InlineData("app.localhost")]
    [InlineData("127.0.0.1")]
    [InlineData("10.1.2.3")]
    [InlineData("172.16.0.1")]
    [InlineData("172.31.255.1")]
    [InlineData("192.168.0.1")]
    [InlineData("169.254.1.1")]
    [InlineData("::1")]
    [InlineData("fe80::1")]
    public void IsLocalEndpointHost_DetectsLocalHosts(string host)
    {
        Assert.True(OpenAiCompatibleEndpoint.IsLocalEndpointHost(host));
    }

    [Theory]
    [InlineData("myserver.local")]
    [InlineData("nas.local")]
    [InlineData("lmstudio")]
    [InlineData("server")]
    [InlineData("134744072")]
    [InlineData("api.openai.com")]
    [InlineData("8.8.8.8")]
    [InlineData("172.32.0.1")]
    [InlineData("example.com")]
    public void IsLocalEndpointHost_RejectsRemoteHosts(string host)
    {
        Assert.False(OpenAiCompatibleEndpoint.IsLocalEndpointHost(host));
    }

    /// <summary>
    /// A <c>.local</c> name and a single-label name are resolved over mDNS, which
    /// any device on the local network can answer for, so neither is trusted for
    /// plaintext HTTP even though it looks local.
    /// </summary>
    [Theory]
    [InlineData("myserver.local")]
    [InlineData("nas.local")]
    [InlineData("lmstudio")]
    [InlineData("server")]
    public void IsUnqualifiedLocalName_DetectsClaimableNames(string host)
    {
        Assert.True(OpenAiCompatibleEndpoint.IsUnqualifiedLocalName(host));
    }

    [Theory]
    [InlineData("api.openai.com")]
    [InlineData("8.8.8.8")]
    [InlineData("192.168.1.10")]
    [InlineData("::1")]
    [InlineData("fe80::1")]
    [InlineData("localhost")]
    [InlineData("app.localhost")]
    [InlineData("134744072")]
    [InlineData("0x7f000001")]
    [InlineData("")]
    public void IsUnqualifiedLocalName_RejectsAddressesAndQualifiedNames(string host)
    {
        Assert.False(OpenAiCompatibleEndpoint.IsUnqualifiedLocalName(host));
    }

    /// <summary>
    /// An IPv4 literal written in another notation is an address, not a name that
    /// any device on the local network could answer for.
    /// </summary>
    [Theory]
    [InlineData("134744072")]
    [InlineData("0x7f000001")]
    [InlineData("0X08080808")]
    [InlineData("2130706433")]
    public void IsNumericAddressLiteral_DetectsAddressLiterals(string host)
    {
        Assert.True(OpenAiCompatibleEndpoint.IsNumericAddressLiteral(host));
        Assert.False(OpenAiCompatibleEndpoint.IsUnqualifiedLocalName(host));
    }

    [Theory]
    [InlineData("lmstudio")]
    [InlineData("nas.local")]
    [InlineData("8.8.8.8")]
    [InlineData("example.com")]
    public void IsNumericAddressLiteral_RejectsNames(string host)
    {
        Assert.False(OpenAiCompatibleEndpoint.IsNumericAddressLiteral(host));
    }

    /// <summary>
    /// The refusal for a host the app cannot check as local says so, instead of
    /// calling every refused host a remote one: a loopback address written in
    /// another notation is not remote, it is simply not checkable.
    /// </summary>
    [Fact]
    public void PlaintextRemoteWarning_NamesAHostTheAppCannotCheckAsLocal()
    {
        var warning = OpenAiCompatibleEndpoint.PlaintextRemoteWarning("http://jira.example.com:1234/v1");

        Assert.NotNull(warning);
        Assert.Contains("cannot check as a local address", warning, StringComparison.Ordinal);
        Assert.DoesNotContain("remote host", warning, StringComparison.Ordinal);
        Assert.Contains("API key and transcript text would be sent unencrypted", warning, StringComparison.Ordinal);
    }

    /// <summary>
    /// .NET normalises a legacy IPv4 notation when it parses a URL, so a host
    /// written as a single number arrives as the dotted quad it stands for. The
    /// app then knows where it points and can call it remote. The address is
    /// refused either way, which is the part that matters.
    /// </summary>
    [Fact]
    public void PlaintextRemoteWarning_RefusesANumericAddressWrittenInAnotherNotation()
    {
        var warning = OpenAiCompatibleEndpoint.PlaintextRemoteWarning("http://134744072:1234/v1");

        Assert.NotNull(warning);
        Assert.Contains("remote host", warning, StringComparison.Ordinal);
        Assert.Contains("API key and transcript text would be sent unencrypted", warning, StringComparison.Ordinal);
    }

    /// <summary>
    /// An address the app parsed and found to be public is remote, and the
    /// refusal says so and names what would cross the network in the clear.
    /// </summary>
    [Fact]
    public void PlaintextRemoteWarning_CallsAPublicAddressRemote()
    {
        var warning = OpenAiCompatibleEndpoint.PlaintextRemoteWarning("http://8.8.8.8:1234/v1");

        Assert.NotNull(warning);
        Assert.Contains("remote host", warning, StringComparison.Ordinal);
        Assert.Contains("API key and transcript text would be sent unencrypted", warning, StringComparison.Ordinal);
    }

    /// <summary>
    /// A public address is one the app could parse and found to be somewhere
    /// else. A local address is not public, and a host in another notation is
    /// not parseable at all, so the app cannot call it public either.
    /// </summary>
    [Theory]
    [InlineData("8.8.8.8")]
    [InlineData("203.0.113.10")]
    [InlineData("172.32.0.1")]
    public void IsPublicAddress_DetectsPublicAddresses(string host)
    {
        Assert.True(OpenAiCompatibleEndpoint.IsPublicAddress(host));
    }

    [Theory]
    [InlineData("127.0.0.1")]
    [InlineData("10.1.2.3")]
    [InlineData("192.168.1.10")]
    [InlineData("169.254.1.1")]
    [InlineData("172.16.0.1")]
    [InlineData("example.com")]
    [InlineData("134744072")]   // an address in another notation: not parseable
    [InlineData("999.1.1.1")]   // not an octet
    [InlineData("")]
    public void IsPublicAddress_RejectsLocalAndUnparseableHosts(string host)
    {
        Assert.False(OpenAiCompatibleEndpoint.IsPublicAddress(host));
    }

    /// <summary>
    /// The empty host is not an address literal.
    /// </summary>
    [Fact]
    public void IsNumericAddressLiteral_RejectsTheEmptyHost()
    {
        Assert.False(OpenAiCompatibleEndpoint.IsNumericAddressLiteral(string.Empty));
    }

    /// <summary>
    /// A name that any device on the local network can claim gets the refusal
    /// that names the fix: point the setting at the machine's IP address.
    /// </summary>
    [Fact]
    public void PlaintextRemoteWarning_ExplainsAClaimableLocalName()
    {
        var warning = OpenAiCompatibleEndpoint.PlaintextRemoteWarning("http://lmstudio:1234/v1");

        Assert.NotNull(warning);
        Assert.Contains("not an address this app trusts for plaintext HTTP", warning, StringComparison.Ordinal);
        Assert.Contains("192.168.1.20", warning, StringComparison.Ordinal);
    }
}
