using System.Runtime.CompilerServices;
using System.Text.Json;
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
    /// A bracket belongs to an IPv6 literal, so <c>http://[localhost]:1234/v1</c>
    /// is not a URL .NET can parse - and a URL the app cannot parse must not
    /// become a URL the app trusts. The macOS port refuses it, so the Windows
    /// port refuses it too.
    /// </summary>
    [Theory]
    [InlineData("http://[localhost]:1234/v1")]
    [InlineData("http://[127.0.0.1]:1234/v1")]
    public void ABracketedNameIsRefusedEvenThoughTheUrlDoesNotParse(string url)
    {
        var refusal = OpenAiCompatibleEndpoint.PlaintextRemoteWarning(url);

        Assert.NotNull(refusal);
        Assert.Contains("cannot use as a local address", refusal, StringComparison.Ordinal);
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
    [InlineData("::ffff:127.000.000.001")]
    public void ANonCanonicalAddressIsNotTrusted(string host)
    {
        Assert.False(OpenAiCompatibleEndpoint.IsLocalEndpointHost(host), $"expected {host} not to be trusted");
    }

    /// <summary>
    /// A hex group is written with at most four digits. The macOS parser
    /// silently truncated a longer one, so <c>0fe80::1</c> was read as
    /// <c>fe80::1</c> and trusted there while this port refused it. Both ports
    /// refuse the spelling now: an address has to be written the way an
    /// address is written.
    /// </summary>
    [Theory]
    [InlineData("::000000")]
    [InlineData("0fe80::1")]
    [InlineData("0c0a8::1")]
    public void AnIPv6GroupLongerThanFourDigitsIsRefused(string host)
    {
        Assert.False(OpenAiCompatibleEndpoint.IsLocalEndpointHost(host), $"expected {host} not to be trusted");
    }

    /// <summary>
    /// The names the standards reserve for the loopback are the only ones that
    /// are trusted. A name that only looks like one - a Debian convention, a
    /// name under a name that looks reserved, a word that merely contains
    /// "localhost" - is a name the network can answer with anything.
    /// </summary>
    [Theory]
    [InlineData("localhost.localdomain")]
    [InlineData("myhost.localhost.example.com")]
    [InlineData("notlocalhost")]
    public void ANameThatOnlyLooksLikeTheReservedOneIsRefused(string host)
    {
        Assert.False(OpenAiCompatibleEndpoint.IsLocalEndpointHost(host), $"expected {host} not to be trusted");
    }

    /// <summary>
    /// A host that only has a zone id has nothing before it, and the text
    /// after the <c>%</c> is not an address the app checked.
    /// </summary>
    [Theory]
    [InlineData("%::")]
    [InlineData("%::1")]
    [InlineData("%fe80::1")]
    public void AHostThatOnlyHasAZoneIdIsRefused(string host)
    {
        Assert.False(OpenAiCompatibleEndpoint.IsLocalEndpointHost(host), $"expected {host} not to be trusted");
    }

    /// <summary>
    /// Brackets belong to an IPv6 literal, and only one pair of them comes
    /// off: <c>[[::1]]</c> is not a literal, and .NET's parser would read the
    /// inner brackets as one.
    /// </summary>
    [Fact]
    public void ADoublyBracketedLiteralIsNotOne()
    {
        Assert.False(OpenAiCompatibleEndpoint.IsLocalEndpointHost("[[::1]]"));
    }

    /// <summary>
    /// A string that only starts like a link-local address is not one. The
    /// prefix is not a shortcut: the address has to parse.
    /// </summary>
    [Theory]
    [InlineData("fe80:evil.example.com")]
    [InlineData("fe80:1:2:3:4:5:6:7:8")]
    [InlineData("fe80:")]
    public void AStringThatOnlyLooksLikeALinkLocalAddressIsRefused(string host)
    {
        Assert.False(OpenAiCompatibleEndpoint.IsLocalEndpointHost(host), $"expected {host} not to be trusted");
    }

    /// <summary>
    /// The two ports have their own copy of the classifier, and they have to
    /// agree: the same host has to be trusted on both, or the same secret
    /// goes out in the clear on one of them. The table is shared, so a change
    /// to one port that the other does not follow fails a build.
    /// </summary>
    [Fact]
    public void TheClassifierAgreesWithTheSharedHostTable()
    {
        var path = Path.Combine(RepositoryRoot(), "contract-fixtures", "plaintext-endpoint-hosts.json");
        Assert.True(File.Exists(path), $"Missing contract fixture at {path}.");

        using var document = JsonDocument.Parse(File.ReadAllText(path));
        var entries = document.RootElement.EnumerateArray().ToList();
        Assert.NotEmpty(entries);

        foreach (var entry in entries)
        {
            var host = entry.GetProperty("host").GetString() ?? string.Empty;
            var trusted = entry.GetProperty("trusted").GetBoolean();
            var note = entry.GetProperty("note").GetString() ?? string.Empty;

            Assert.True(
                OpenAiCompatibleEndpoint.IsLocalEndpointHost(host) == trusted,
                $"{host}: {note}");
        }
    }

    private static string RepositoryRoot([CallerFilePath] string sourceFilePath = "")
    {
        // <root>/windows/tests/BugNarrator.Windows.Tests/<this file>
        var directory = Path.GetDirectoryName(sourceFilePath)!;
        return Path.GetFullPath(Path.Combine(directory, "..", "..", ".."));
    }


    /// <summary>
    /// The two ports read the host out of a URL differently — Foundation takes
    /// the brackets off whatever is in them, .NET keeps them — so the same URL
    /// could be trusted on one port and refused on the other. The table of
    /// URLs is shared, so a change to one port that the other does not follow
    /// fails a build.
    /// </summary>
    [Fact]
    public void TheRefusalAgreesWithTheSharedURLTable()
    {
        var path = Path.Combine(RepositoryRoot(), "contract-fixtures", "plaintext-endpoint-urls.json");
        Assert.True(File.Exists(path), $"Missing contract fixture at {path}.");

        using var document = JsonDocument.Parse(File.ReadAllText(path));
        var entries = document.RootElement.EnumerateArray().ToList();
        Assert.NotEmpty(entries);

        foreach (var entry in entries)
        {
            var url = entry.GetProperty("url").GetString() ?? string.Empty;
            var trusted = entry.GetProperty("trusted").GetBoolean();
            var note = entry.GetProperty("note").GetString() ?? string.Empty;

            // No refusal means the app may send a secret to that URL over
            // plaintext HTTP.
            var refusal = OpenAiCompatibleEndpoint.PlaintextRemoteWarning(url);

            Assert.True(
                (refusal is null) == trusted,
                $"{url}: {note}");
        }
    }

}
