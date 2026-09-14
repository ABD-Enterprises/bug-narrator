using System.IO.Compression;
using System.Security.Cryptography;

namespace BugNarrator.Windows.Services.LocalTranscription;

/// <summary>
/// Download → SHA-256 + size check → extract to staging → publisher verification → atomic move,
/// mirroring macOS installImage. Every failure surfaces as <see cref="LocalServerFailure"/> with a
/// user-facing message; nothing is left in the install directory unless the whole chain passed.
/// </summary>
public sealed class LocalServerInstaller
{
    public const string ExecutableName = "bugnarrator-transcription.exe";

    /// <summary>The executable is a PyInstaller onefile bundle; anything past this is not ours.</summary>
    public const long MaxExecutableBytes = 400_000_000;

    private readonly IAuthenticodeVerifier verifier;
    private readonly long maxExecutableBytes;

    public LocalServerInstaller(IAuthenticodeVerifier verifier, long maxExecutableBytes = MaxExecutableBytes)
    {
        this.verifier = verifier;
        this.maxExecutableBytes = maxExecutableBytes;
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
                if (entry.Length <= 0 || entry.Length > maxExecutableBytes)
                {
                    throw new LocalServerFailure("Invalid server package: the executable size is out of bounds");
                }

                // Bounded copy: the declared length is not trusted either.
                using var source = entry.Open();
                using var target = new FileStream(Path.Combine(staging, ExecutableName), FileMode.CreateNew, FileAccess.Write);
                var buffer = new byte[81920];
                long written = 0;
                int read;
                while ((read = source.Read(buffer, 0, buffer.Length)) > 0)
                {
                    written += read;
                    if (written > maxExecutableBytes)
                    {
                        throw new LocalServerFailure("Invalid server package: the executable size is out of bounds");
                    }

                    target.Write(buffer, 0, read);
                }
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
