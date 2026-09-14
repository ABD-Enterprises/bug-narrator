using System.IO.Compression;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using BugNarrator.Windows.Services.LocalTranscription;
using Xunit;

namespace BugNarrator.Windows.Tests;

/// <summary>
/// WIN-037 (#1179): the discovery and install half of the macOS LocalTranscriptionManager port,
/// driven with a fake HTTP handler, a fake publisher verifier, and a fake process.
/// </summary>
public sealed class LocalTranscriptionServerManagerTests : IDisposable
{
    private const string ImageUrl = "https://github.com/ABD-Enterprises/bug-narrator/releases/download/server-v1/" + LocalServerPackageCatalog.AssetName;
    private const string ChecksumUrl = ImageUrl + ".sha256";

    private readonly string root = Path.Combine(Path.GetTempPath(), "BugNarrator.Windows.Tests", Guid.NewGuid().ToString("N"));
    private readonly string installDirectory;

    public LocalTranscriptionServerManagerTests()
    {
        installDirectory = Path.Combine(root, "LocalTranscription");
        Directory.CreateDirectory(root);
    }

    public void Dispose()
    {
        if (Directory.Exists(root))
        {
            Directory.Delete(root, recursive: true);
        }
    }

    // ---- catalog ----

    [Fact]
    public void SelectPackage_SkipsDraftsPrereleasesAndReleasesMissingEitherAsset()
    {
        var good = Release(draft: false, prerelease: false, ImageAsset(1000), ChecksumAsset(70));

        Assert.Null(LocalServerPackageCatalog.SelectPackage([Release(draft: true, prerelease: false, ImageAsset(1000), ChecksumAsset(70))]));
        Assert.Null(LocalServerPackageCatalog.SelectPackage([Release(draft: false, prerelease: true, ImageAsset(1000), ChecksumAsset(70))]));
        Assert.Null(LocalServerPackageCatalog.SelectPackage([Release(draft: false, prerelease: false, ImageAsset(1000))]));
        Assert.NotNull(LocalServerPackageCatalog.SelectPackage([Release(draft: true, prerelease: false, ImageAsset(1000), ChecksumAsset(70)), good]));
    }

    [Theory]
    [InlineData(0, 70)]
    [InlineData(1_000_000_000, 70)]
    [InlineData(1000, 0)]
    [InlineData(1000, 4096)]
    public void SelectPackage_RejectsAssetsOutsideTheSizeBounds(long imageSize, long checksumSize)
    {
        Assert.Null(LocalServerPackageCatalog.SelectPackage([Release(false, false, ImageAsset(imageSize), ChecksumAsset(checksumSize))]));
    }

    [Theory]
    [InlineData("https://github.com/ABD-Enterprises/bug-narrator/releases/download/v1/x.zip", true)]
    [InlineData("http://github.com/ABD-Enterprises/bug-narrator/releases/download/v1/x.zip", false)]
    [InlineData("https://evil.example/ABD-Enterprises/bug-narrator/releases/download/v1/x.zip", false)]
    [InlineData("https://github.com/Someone-Else/bug-narrator/releases/download/v1/x.zip", false)]
    [InlineData("https://user:pw@github.com/ABD-Enterprises/bug-narrator/releases/download/v1/x.zip", false)]
    [InlineData("not a url", false)]
    public void TrustedAssetUrl_OnlyAcceptsTheProjectsOwnReleaseDownloads(string url, bool expected)
    {
        Assert.Equal(expected, LocalServerPackageCatalog.TrustedAssetUrl(url));
    }

    [Fact]
    public async Task Discover_ReportsNoReleaseWhenTheFeedRunsOutOfPages()
    {
        var handler = new FakeHandler(_ => Json("[]"));
        var manager = CreateManager(handler);

        await manager.DiscoverAsync();

        Assert.Null(manager.State.Package);
        Assert.Equal("No compatible signed server release was found. Try again later or choose OpenAI.", manager.State.Message);
        Assert.False(manager.State.Busy);
    }

    [Fact]
    public async Task Discover_FindsThePackageOnALaterPage()
    {
        var page1 = Enumerable.Range(0, 30).Select(_ => Release(false, true, ImageAsset(1000), ChecksumAsset(70))).ToList();
        var page2 = new[] { Release(false, false, ImageAsset(1000), ChecksumAsset(70)) };
        var handler = new FakeHandler(request => Json(JsonSerializer.Serialize<IReadOnlyList<LocalServerRelease>>(request.RequestUri!.Query.Contains("page=1") ? page1 : page2)));
        var manager = CreateManager(handler);

        await manager.DiscoverAsync();

        Assert.NotNull(manager.State.Package);
        Assert.Equal(2, handler.Calls);
    }

    // ---- installer ----

    [Fact]
    public void Install_VerifiesChecksumExtractsVerifiesSignatureAndMovesIntoPlace()
    {
        var (zip, manifest, size) = BuildPackage("exe-bytes");
        var verifier = new FakeVerifier();

        new LocalServerInstaller(verifier).Install(zip, manifest, size, installDirectory);

        var installed = Path.Combine(installDirectory, LocalServerInstaller.ExecutableName);
        Assert.True(File.Exists(installed));
        Assert.Equal("exe-bytes", File.ReadAllText(installed));
        Assert.Contains(verifier.Verified, path => path.Contains(".install-", StringComparison.Ordinal));
        Assert.Empty(Directory.GetDirectories(installDirectory));
    }

    [Fact]
    public void Install_WithAWrongChecksum_FailsBeforeExtracting()
    {
        var (zip, _, size) = BuildPackage("exe-bytes");
        var verifier = new FakeVerifier();

        var failure = Assert.Throws<LocalServerFailure>(() =>
            new LocalServerInstaller(verifier).Install(zip, new string('0', 64), size, installDirectory));

        Assert.Equal("The server download failed its SHA-256 check", failure.Message);
        Assert.Empty(verifier.Verified);
        Assert.False(File.Exists(Path.Combine(installDirectory, LocalServerInstaller.ExecutableName)));
    }

    [Theory]
    [InlineData("not-hex-not-64")]
    [InlineData("")]
    public void Install_WithAMalformedManifest_Fails(string manifest)
    {
        var (zip, _, size) = BuildPackage("exe-bytes");

        var failure = Assert.Throws<LocalServerFailure>(() => new LocalServerInstaller(new FakeVerifier()).Install(zip, manifest, size, installDirectory));

        Assert.Equal("Invalid checksum manifest or download size", failure.Message);
    }

    [Fact]
    public void Install_WithAWrongSize_Fails()
    {
        var (zip, manifest, size) = BuildPackage("exe-bytes");

        Assert.Throws<LocalServerFailure>(() => new LocalServerInstaller(new FakeVerifier()).Install(zip, manifest, size + 1, installDirectory));
    }

    [Fact]
    public void Install_WhenTheSignatureFails_LeavesNothingInstalled()
    {
        var (zip, manifest, size) = BuildPackage("exe-bytes");
        var verifier = new FakeVerifier { Failure = "The local server executable is not signed by the BugNarrator publisher. Remove and reinstall it." };

        var failure = Assert.Throws<LocalServerFailure>(() => new LocalServerInstaller(verifier).Install(zip, manifest, size, installDirectory));

        Assert.Equal(verifier.Failure, failure.Message);
        Assert.False(File.Exists(Path.Combine(installDirectory, LocalServerInstaller.ExecutableName)));
        Assert.Empty(Directory.GetDirectories(installDirectory));
    }

    [Fact]
    public void Install_RefusesASymlinkedInstallDirectory()
    {
        var (zip, manifest, size) = BuildPackage("exe-bytes");
        var target = Path.Combine(root, "real");
        Directory.CreateDirectory(target);
        var link = Path.Combine(root, "link");
        try
        {
            Directory.CreateSymbolicLink(link, target);
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            return; // symlink creation needs Developer Mode or elevation on this host; nothing to assert
        }

        var failure = Assert.Throws<LocalServerFailure>(() => new LocalServerInstaller(new FakeVerifier()).Install(zip, manifest, size, link));

        Assert.Equal("Install directory must not be a symbolic link", failure.Message);
    }

    [Fact]
    public void Install_RejectsAPackageWhoseExecutableIsNested()
    {
        var zip = Path.Combine(root, "nested.zip");
        using (var archive = ZipFile.Open(zip, ZipArchiveMode.Create))
        {
            var entry = archive.CreateEntry("sub/" + LocalServerInstaller.ExecutableName);
            using var writer = new StreamWriter(entry.Open());
            writer.Write("exe");
        }

        var size = new FileInfo(zip).Length;
        var manifest = Sha256(zip) + "  " + LocalServerPackageCatalog.AssetName;

        var failure = Assert.Throws<LocalServerFailure>(() => new LocalServerInstaller(new FakeVerifier()).Install(zip, manifest, size, installDirectory));

        Assert.Equal("Invalid server package: the executable is missing", failure.Message);
    }

    [Fact]
    public void Install_RejectsAnExecutableEntryLargerThanTheBound()
    {
        // The bound is injectable so the test does not have to write hundreds of megabytes.
        const long limit = 4096;
        var zip = Path.Combine(root, "huge.zip");
        using (var archive = ZipFile.Open(zip, ZipArchiveMode.Create))
        {
            var entry = archive.CreateEntry(LocalServerInstaller.ExecutableName, CompressionLevel.SmallestSize);
            using var stream = entry.Open();
            stream.Write(new byte[limit + 1]);
        }

        var size = new FileInfo(zip).Length;
        var manifest = Sha256(zip) + "  " + LocalServerPackageCatalog.AssetName;

        var failure = Assert.Throws<LocalServerFailure>(() => new LocalServerInstaller(new FakeVerifier(), limit).Install(zip, manifest, size, installDirectory));

        Assert.Equal("Invalid server package: the executable size is out of bounds", failure.Message);
        Assert.False(File.Exists(Path.Combine(installDirectory, LocalServerInstaller.ExecutableName)));
    }

    [Theory]
    [InlineData("CN=ABD Enterprises, O=ABD Enterprises, L=Somewhere, C=US", true)]
    [InlineData("CN=Evil, O=ABD Enterprises Evil, C=US", false)]
    [InlineData("CN=ABD Enterprises, C=US", false)]
    [InlineData("O=abd enterprises", false)]
    public void AuthenticodeVerifier_RequiresTheExactPublisherOrganization(string subject, bool expected)
    {
        var name = new System.Security.Cryptography.X509Certificates.X500DistinguishedName(subject);

        Assert.Equal(expected, AuthenticodeVerifier.SignedBy(name, AuthenticodeVerifier.PublisherOrganization));
    }

    [Fact]
    public void AuthenticodeVerifier_RejectsAnUnsignedFile()
    {
        if (!OperatingSystem.IsWindows())
        {
            return; // WinVerifyTrust only exists on Windows; SignedBy is covered everywhere above
        }

        var unsigned = Path.Combine(root, "unsigned.exe");
        File.WriteAllText(unsigned, "not signed");

        // Not a PE at all, so WinVerifyTrust reports a provider error rather than TRUST_E_NOSIGNATURE;
        // either way the file never runs and the user is told to reinstall.
        var failure = Assert.Throws<LocalServerFailure>(() => new AuthenticodeVerifier().Verify(unsigned));

        Assert.EndsWith("Remove and reinstall it.", failure.Message);
    }

    [Fact]
    public async Task AProcessThatExitsDuringLaunch_IsNeverReportedRunning()
    {
        Directory.CreateDirectory(installDirectory);
        File.WriteAllText(Path.Combine(installDirectory, LocalServerInstaller.ExecutableName), "exe");
        var manager = CreateManager(new FakeHandler(_ => Json("[]")), (_, _, onExit) =>
        {
            var process = new FakeProcess { OnExit = onExit };
            process.Exit(1, "crashed at startup"); // exits before launch returns
            return process;
        });

        await manager.StartAsync();

        Assert.False(manager.State.Running);
        Assert.Equal("Local server exited (1). crashed at startup", manager.State.Message);
        await manager.StartAsync(); // a dead process must not block a retry
    }

    [Fact]
    public async Task InstallAndStart_WithAnOversizedChecksumResponse_Fails()
    {
        var (zip, _, size) = BuildPackage("exe-bytes");
        var handler = new FakeHandler(request => request.RequestUri!.AbsoluteUri switch
        {
            ChecksumUrl => Text(new string('a', 8192)),
            ImageUrl => Bytes(File.ReadAllBytes(zip)),
            _ => Json(JsonSerializer.Serialize(new[] { Release(false, false, ImageAsset(size), ChecksumAsset(70)) })),
        });
        var manager = CreateManager(handler);

        await manager.DiscoverAsync();
        await manager.InstallAndStartAsync();

        Assert.Equal("Installation failed: Invalid checksum manifest. You can retry.", manager.State.Message);
        Assert.False(manager.State.Installed);
    }

    [Fact]
    public async Task ConcurrentStarts_LaunchOnce()
    {
        Directory.CreateDirectory(installDirectory);
        File.WriteAllText(Path.Combine(installDirectory, LocalServerInstaller.ExecutableName), "exe");
        var launches = 0;
        var manager = CreateManager(new FakeHandler(_ => Json("[]")), (_, _, _) => { Interlocked.Increment(ref launches); return new FakeProcess(); });

        await Task.WhenAll(Enumerable.Range(0, 8).Select(_ => Task.Run(() => manager.StartAsync())));

        Assert.Equal(1, launches);
    }

    // ---- manager state guards ----

    [Fact]
    public async Task InstallAndStart_DownloadsVerifiesInstallsAndLaunches()
    {
        var (zip, manifest, size) = BuildPackage("exe-bytes");
        var handler = new FakeHandler(request => request.RequestUri!.AbsoluteUri switch
        {
            ChecksumUrl => Text(manifest),
            ImageUrl => Bytes(File.ReadAllBytes(zip)),
            _ => Json(JsonSerializer.Serialize(new[] { Release(false, false, ImageAsset(size), ChecksumAsset(manifest.Length)) })),
        });
        var launches = new List<(string Exe, string Models)>();
        var process = new FakeProcess();
        var manager = CreateManager(handler, (exe, models, _) => { launches.Add((exe, models)); return process; });

        await manager.DiscoverAsync();
        await manager.InstallAndStartAsync();

        Assert.True(manager.State.Installed);
        Assert.True(manager.State.Running);
        Assert.False(manager.State.Busy);
        Assert.Null(manager.State.Progress);
        Assert.StartsWith("Server starting.", manager.State.Message);
        var launched = Assert.Single(launches);
        Assert.Equal(Path.Combine(installDirectory, LocalServerInstaller.ExecutableName), launched.Exe);
        Assert.Equal(Path.Combine(installDirectory, "Models"), launched.Models);
    }

    [Fact]
    public async Task InstallAndStart_WhenTheChecksumMismatches_ReportsFailureAndInstallsNothing()
    {
        var (zip, _, size) = BuildPackage("exe-bytes");
        var handler = new FakeHandler(request => request.RequestUri!.AbsoluteUri switch
        {
            ChecksumUrl => Text(new string('a', 64)),
            ImageUrl => Bytes(File.ReadAllBytes(zip)),
            _ => Json(JsonSerializer.Serialize(new[] { Release(false, false, ImageAsset(size), ChecksumAsset(64)) })),
        });
        var manager = CreateManager(handler);

        await manager.DiscoverAsync();
        await manager.InstallAndStartAsync();

        Assert.False(manager.State.Installed);
        Assert.False(manager.State.Running);
        Assert.Equal("Installation failed: The server download failed its SHA-256 check. You can retry.", manager.State.Message);
    }

    [Fact]
    public async Task Start_ReVerifiesTheSignatureBeforeEveryLaunch_AndRefusesAnUnsignedExecutable()
    {
        Directory.CreateDirectory(installDirectory);
        File.WriteAllText(Path.Combine(installDirectory, LocalServerInstaller.ExecutableName), "dropped-in");
        var verifier = new FakeVerifier { Failure = "The local server executable is not signed by the BugNarrator publisher. Remove and reinstall it." };
        var launched = false;
        var manager = CreateManager(new FakeHandler(_ => Json("[]")), (_, _, _) => { launched = true; return new FakeProcess(); }, verifier);

        Assert.True(manager.State.Installed); // a pre-existing exe counts as installed...
        await manager.StartAsync();

        Assert.False(launched); // ...but never runs unverified
        Assert.False(manager.State.Running);
        Assert.Equal($"Could not start the server: {verifier.Failure}. Remove and reinstall it if verification failed.", manager.State.Message);
    }

    [Fact]
    public async Task Start_WithAPreExistingSignedExecutable_Launches()
    {
        Directory.CreateDirectory(installDirectory);
        File.WriteAllText(Path.Combine(installDirectory, LocalServerInstaller.ExecutableName), "dropped-in");
        var verifier = new FakeVerifier();
        var manager = CreateManager(new FakeHandler(_ => Json("[]")), (_, _, _) => new FakeProcess(), verifier);

        await manager.StartAsync();
        await manager.StartAsync(); // second start is a no-op while the server lives

        Assert.True(manager.State.Running);
        Assert.Single(verifier.Verified);
    }

    [Fact]
    public async Task Remove_IsRefusedWhileRunning_AndDeletesTheInstallAfterwards()
    {
        Directory.CreateDirectory(installDirectory);
        File.WriteAllText(Path.Combine(installDirectory, LocalServerInstaller.ExecutableName), "exe");
        Directory.CreateDirectory(Path.Combine(installDirectory, "Models"));
        var process = new FakeProcess();
        var manager = CreateManager(new FakeHandler(_ => Json("[]")), (_, _, onExit) => { process.OnExit = onExit; return process; });

        await manager.StartAsync();
        manager.Remove();
        Assert.True(Directory.Exists(installDirectory));

        manager.Stop();
        process.Exit(0);
        Assert.Equal("Local server stopped.", manager.State.Message);
        Assert.False(manager.State.Running);

        manager.Remove();
        Assert.False(Directory.Exists(installDirectory));
        Assert.False(manager.State.Installed);
        Assert.Equal("Local server and its managed model cache removed.", manager.State.Message);
    }

    [Fact]
    public async Task ProcessExitWithAStatus_ReportsTheStatusAndStderrTail()
    {
        Directory.CreateDirectory(installDirectory);
        File.WriteAllText(Path.Combine(installDirectory, LocalServerInstaller.ExecutableName), "exe");
        var process = new FakeProcess();
        var manager = CreateManager(new FakeHandler(_ => Json("[]")), (_, _, onExit) => { process.OnExit = onExit; return process; });

        await manager.StartAsync();
        process.Exit(3, "port 8422 already in use");

        Assert.Equal("Local server exited (3). port 8422 already in use", manager.State.Message);
    }

    [Fact]
    public async Task Shutdown_TerminatesTheServerAndWaitsForExit()
    {
        Directory.CreateDirectory(installDirectory);
        File.WriteAllText(Path.Combine(installDirectory, LocalServerInstaller.ExecutableName), "exe");
        var process = new FakeProcess();
        var manager = CreateManager(new FakeHandler(_ => Json("[]")), (_, _, onExit) => { process.OnExit = onExit; return process; });
        await manager.StartAsync();

        var shutdown = manager.ShutdownAsync();
        Assert.True(process.Terminated);
        Assert.False(shutdown.IsCompleted);
        process.Exit(0);
        await shutdown;

        Assert.False(manager.State.Running);
    }

    // ---- helpers ----

    private LocalTranscriptionServerManager CreateManager(FakeHandler handler, LocalServerLaunch? launch = null, IAuthenticodeVerifier? verifier = null)
    {
        var client = new HttpClient(handler);
        return new LocalTranscriptionServerManager(
            installDirectory,
            new LocalServerPackageCatalog(client),
            client,
            verifier ?? new FakeVerifier(),
            launch ?? ((_, _, _) => new FakeProcess()));
    }

    private (string Zip, string Manifest, long Size) BuildPackage(string executableContent)
    {
        var zip = Path.Combine(root, $"{Guid.NewGuid():N}.zip");
        using (var archive = ZipFile.Open(zip, ZipArchiveMode.Create))
        {
            var entry = archive.CreateEntry(LocalServerInstaller.ExecutableName);
            using var writer = new StreamWriter(entry.Open());
            writer.Write(executableContent);
        }

        return (zip, Sha256(zip) + "  " + LocalServerPackageCatalog.AssetName + "\n", new FileInfo(zip).Length);
    }

    private static string Sha256(string file)
    {
        using var stream = File.OpenRead(file);
        return Convert.ToHexString(SHA256.HashData(stream)).ToLowerInvariant();
    }

    private static LocalServerAsset ImageAsset(long size) => new(LocalServerPackageCatalog.AssetName, size, ImageUrl);

    private static LocalServerAsset ChecksumAsset(long size) => new(LocalServerPackageCatalog.ChecksumAssetName, size, ChecksumUrl);

    private static LocalServerRelease Release(bool draft, bool prerelease, params LocalServerAsset[] assets) => new(draft, prerelease, assets);

    private static HttpResponseMessage Json(string body) => new(HttpStatusCode.OK) { Content = new StringContent(body, Encoding.UTF8, "application/json") };

    private static HttpResponseMessage Text(string body) => new(HttpStatusCode.OK) { Content = new StringContent(body, Encoding.UTF8, "text/plain") };

    private static HttpResponseMessage Bytes(byte[] body) => new(HttpStatusCode.OK) { Content = new ByteArrayContent(body) };

    private sealed class FakeHandler(Func<HttpRequestMessage, HttpResponseMessage> respond) : HttpMessageHandler
    {
        public int Calls { get; private set; }

        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            Calls++;
            return Task.FromResult(respond(request));
        }
    }

    private sealed class FakeVerifier : IAuthenticodeVerifier
    {
        public string? Failure { get; init; }
        public List<string> Verified { get; } = [];

        public void Verify(string executablePath)
        {
            Verified.Add(executablePath);
            if (Failure is not null)
            {
                throw new LocalServerFailure(Failure);
            }
        }
    }

    private sealed class FakeProcess : ILocalServerProcess
    {
        private readonly TaskCompletionSource exited = new();

        public Action<int, string>? OnExit { get; set; }
        public bool Terminated { get; private set; }

        public void Exit(int status, string detail = "")
        {
            OnExit?.Invoke(status, detail);
            exited.TrySetResult();
        }

        public Task WaitForExitAsync() => exited.Task;

        public void Terminate() => Terminated = true;
    }
}
