using BugNarrator.Windows.Services.Http;
using Xunit;

namespace BugNarrator.Windows.Tests;

/// <summary>
/// The Windows port has its own copy of the plaintext-endpoint classifier, and
/// it has to reach the same answers as the macOS one: the same host has to be
/// trusted on both ports, or the same secret goes out in the clear on one of
/// them.
/// </summary>
public sealed class PlaintextEndpointClassifierTests
{
    /// <summary>
    /// The unspecified address is this machine, in every spelling the two
    /// ports know: <c>0.0.0.0</c>, <c>::</c> and the IPv4-mapped form of it.
    /// A connection to any of them reaches the loopback interface.
    /// </summary>
    [Theory]
    [InlineData("0.0.0.0")]
    [InlineData("::")]
    [InlineData("0:0:0:0:0:0:0:0")]
    [InlineData("::ffff:0.0.0.0")]
    public void TheUnspecifiedAddressIsThisMachine(string host)
    {
        Assert.True(OpenAiCompatibleEndpoint.IsLocalEndpointHost(host), $"expected {host} to be trusted");
        Assert.False(OpenAiCompatibleEndpoint.IsPublicAddress(host), $"expected {host} not to be a remote host");
    }

    /// <summary>
    /// The rest of the 0.0.0.0/8 range is not this machine: 0.0.0.5 does not
    /// reach it, it is refused with EHOSTUNREACH.
    /// </summary>
    [Fact]
    public void TheRestOfTheUnspecifiedRangeIsNotThisMachine()
    {
        Assert.False(OpenAiCompatibleEndpoint.IsLocalEndpointHost("0.0.0.5"));
        Assert.False(OpenAiCompatibleEndpoint.IsPublicAddress("0.0.0.5"));
    }

    /// <summary>
    /// The IPv6 loopback and link-local addresses can be written in more than
    /// one way, and the port has to recognise all of them. Comparing the
    /// strings would refuse an endpoint the user can reach.
    /// </summary>
    [Theory]
    [InlineData("::1")]
    [InlineData("0:0:0:0:0:0:0:1")]
    [InlineData("::ffff:127.0.0.1")]
    [InlineData("fe80::1")]
    [InlineData("fe80::1%en0")]
    public void EverySpellingOfTheIPv6LocalAddressesIsTrusted(string host)
    {
        Assert.True(OpenAiCompatibleEndpoint.IsLocalEndpointHost(host), $"expected {host} to be trusted");
    }

    /// <summary>
    /// Brackets belong to an IPv6 literal. <c>[localhost]</c> is not one, and
    /// reading it as <c>localhost</c> would make the app trust a name it
    /// cannot check.
    /// </summary>
    [Fact]
    public void ABracketedNameIsNotAnIPv6Literal()
    {
        Assert.False(OpenAiCompatibleEndpoint.IsLocalEndpointHost("[localhost]"));
        Assert.False(OpenAiCompatibleEndpoint.IsLocalEndpointHost("[127.0.0.1]"));
    }

    /// <summary>
    /// A trailing dot makes a name absolute rather than different: a resolver
    /// answers the same name either way, so the two have to be classified the
    /// same way. An address is not a name, so <c>127.0.0.1.</c> stays refused.
    /// </summary>
    [Fact]
    public void ATrailingDotDoesNotChangeWhichClassAHostIsIn()
    {
        Assert.True(
            OpenAiCompatibleEndpoint.IsUnqualifiedLocalName("nas.local."),
            "a trailing dot does not make a claimable name a different host");
        Assert.True(
            OpenAiCompatibleEndpoint.IsUnqualifiedLocalName("lmstudio."),
            "a trailing dot does not make a claimable name a different host");
        Assert.False(
            OpenAiCompatibleEndpoint.IsUnqualifiedLocalName("localhost."),
            "localhost is reserved, however it is written");
        Assert.True(
            OpenAiCompatibleEndpoint.IsLocalEndpointHost("localhost."),
            "the absolute form of a reserved name is the same host");
        Assert.True(
            OpenAiCompatibleEndpoint.IsLocalEndpointHost("app.localhost."),
            "the absolute form of a reserved name is the same host");
        Assert.False(
            OpenAiCompatibleEndpoint.IsLocalEndpointHost("127.0.0.1."),
            "a trailing dot turns an address into a name the app cannot check");
    }

    /// <summary>
    /// The unspecified, multicast and broadcast addresses are not a host on
    /// the public internet, so the app must not call them remote.
    /// </summary>
    [Theory]
    [InlineData("224.0.0.1")]
    [InlineData("239.255.255.250")]
    [InlineData("255.255.255.255")]
    public void TheMulticastAndBroadcastAddressesAreNotCalledRemote(string host)
    {
        Assert.False(OpenAiCompatibleEndpoint.IsPublicAddress(host), $"expected {host} not to be a remote host");
    }

    /// <summary>
    /// The spelling has to be canonical, because the app and the network have
    /// to read the host the same way. A leading zero is a different octet to a
    /// resolver that reads it as octal, and a short form is a form the app
    /// will not guess at.
    /// </summary>
    [Theory]
    [InlineData("010.0.0.1")]
    [InlineData("127.000.000.001")]
    [InlineData("127.1")]
    [InlineData("2130706433")]
    [InlineData("::ffff:010.0.0.1")]
    public void ANonCanonicalAddressIsNotTrusted(string host)
    {
        Assert.False(OpenAiCompatibleEndpoint.IsLocalEndpointHost(host), $"expected {host} not to be trusted");
    }
}
