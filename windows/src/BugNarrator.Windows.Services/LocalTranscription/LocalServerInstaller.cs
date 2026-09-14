using System.IO.Compression;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;

namespace BugNarrator.Windows.Services.LocalTranscription;

/// <summary>Verifies that an executable is signed by the BugNarrator publisher; throws <see cref="LocalServerFailure"/> otherwise.</summary>
public interface IAuthenticodeVerifier
{
    void Verify(string executablePath);
}

/// <summary>
/// Authenticode check pinned to the publisher subject and its issuer chain — the Windows analogue
/// of the macOS codesign requirement on the team OU rather than a rotating leaf thumbprint.
/// </summary>
public sealed class AuthenticodeVerifier : IAuthenticodeVerifier
{
    public const string PublisherSubjectFragment = "O=ABD Enterprises";

    public void Verify(string executablePath)
    {
        X509Certificate2 certificate;
        try
        {
            certificate = new X509Certificate2(X509Certificate.CreateFromSignedFile(executablePath));
        }
        catch (Exception exception)
        {
            throw new LocalServerFailure($"Invalid server executable: {exception.Message}");
        }

        using (certificate)
        {
            if (!certificate.Subject.Contains(PublisherSubjectFragment, StringComparison.Ordinal))
            {
                throw new LocalServerFailure("The local server executable is not signed by the BugNarrator publisher. Remove and reinstall it.");
            }

            using var chain = new X509Chain();
            chain.ChainPolicy.RevocationMode = X509RevocationMode.NoCheck;
            if (!chain.Build(certificate))
            {
                throw new LocalServerFailure("The local server executable's signature chain could not be verified. Remove and reinstall it.");
            }
        }
    }
}

/// <summary>
/// Download → SHA-256 + size check → extract to staging → publisher verification → atomic move,
/// mirroring macOS installImage. Every failure surfaces as <see cref="LocalServerFailure"/> with a
/// user-facing message; nothing is left in the install directory unless the whole chain passed.
/// </summary>
public sealed class LocalServerInstaller
{
    public const string ExecutableName = "bugnarrator-transcription.exe";

    private readonly IAuthenticodeVerifier verifier;

    public LocalServerInstaller(IAuthenticodeVerifier verifier)
    {
        this.verifier = verifier;
    }

    public static void VerifyChecksum(string file, string manifest, long expectedSize)
    {
        var expected = manifest.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries).FirstOrDefault();
        if (manifest.Length >= LocalServerPackageCatalog.MaxChecksumBytes
            || expected is null
            || expected.Length != 64
            || !expected.All(Uri.IsHexDigit)
            || new FileInfo(file).Length != expectedSize)
        {
            throw new LocalServerFailure("Invalid checksum manifest or download size");
        }

        using var stream = File.OpenRead(file);
        var actual = Convert.ToHexString(SHA256.HashData(stream)).ToLowerInvariant();
        if (actual != expected.ToLowerInvariant())
        {
            throw new LocalServerFailure("The server download failed its SHA-256 check");
        }
    }

    public void Install(string zipPath, string checksumManifest, long expectedSize, string installDirectory, CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        VerifyChecksum(zipPath, checksumManifest, expectedSize);

        Directory.CreateDirectory(installDirectory);
        if (new DirectoryInfo(installDirectory).LinkTarget is not null)
        {
            throw new LocalServerFailure("Install directory must not be a symbolic link");
        }

        var staging = Path.Combine(installDirectory, $".install-{Guid.NewGuid():N}");
        try
        {
            cancellationToken.ThrowIfCancellationRequested();
            Directory.CreateDirectory(staging);
            using (var archive = ZipFile.OpenRead(zipPath))
            {
                var entry = archive.Entries.FirstOrDefault(candidate => candidate.Name == ExecutableName && candidate.FullName == ExecutableName)
                    ?? throw new LocalServerFailure("Invalid server package: the executable is missing");
                entry.ExtractToFile(Path.Combine(staging, ExecutableName), overwrite: false);
            }

            cancellationToken.ThrowIfCancellationRequested();
            var stagedExecutable = Path.Combine(staging, ExecutableName);
            verifier.Verify(stagedExecutable);

            var destination = Path.Combine(installDirectory, ExecutableName);
            File.Move(stagedExecutable, destination, overwrite: true);
        }
        finally
        {
            if (Directory.Exists(staging))
            {
                Directory.Delete(staging, recursive: true);
            }
        }
    }
}
