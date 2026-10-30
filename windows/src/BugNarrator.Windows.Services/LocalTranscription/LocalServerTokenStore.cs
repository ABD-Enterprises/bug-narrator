using System;
using System.Collections.Generic;
using System.IO;
using System.Security.Cryptography;
using System.Text;

namespace BugNarrator.Windows.Services.LocalTranscription;

/// <summary>
/// Where the managed local transcription server is installed.
/// </summary>
public static class LocalServerPaths
{
    /// <summary>
    /// The directory the managed server lives in, and the directory the token
    /// file sits in.
    /// </summary>
    public static string DefaultInstallDirectory =>
        Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "BugNarrator",
            "LocalTranscription");
}

/// <summary>
/// The bearer token the local transcription server requires (#1270).
/// </summary>
/// <remarks>
/// The server is an HTTP endpoint on loopback that any process on the machine
/// can reach, so it refuses every request that does not carry the token. The
/// app and the server have to agree on one token, and the token file next to
/// the managed install is where they agree: the app creates the token before
/// it starts the server and hands the same value over through the environment,
/// and a server that was started on its own writes the same file so the app
/// can find it.
///
/// The path, the file name and the environment variable are pinned by
/// <c>contract-fixtures/local-server-token.json</c>, which the macOS port and
/// the Python server check against the same file.
/// </remarks>
public static class LocalServerTokenStore
{
    /// <summary>The file the token is stored in, next to the managed server.</summary>
    public const string TokenFileName = "bugnarrator-transcription.token";

    /// <summary>How the server is told which token to use.</summary>
    public const string EnvironmentVariable = "BUGNARRATOR_TRANSCRIPTION_TOKEN";

    /// <summary>The authorization scheme the server expects.</summary>
    public const string AuthorizationScheme = "Bearer";

    /// <summary>
    /// The header a client sends when it asks the server to prove that it is
    /// the server, and the header the answer carries.
    /// </summary>
    public const string ChallengeHeader = "X-BugNarrator-Nonce";

    /// <summary>The header the server's answer to a challenge carries.</summary>
    public const string ProofHeader = "X-BugNarrator-Proof";

    /// <summary>
    /// The proof that a peer knows the token: an HMAC of the client's nonce,
    /// keyed by the token.
    /// </summary>
    /// <remarks>
    /// A listener that answers on the port but cannot read the token cannot
    /// produce this, so the client can tell the server apart from it - and the
    /// challenge that asks for it carries no token, so nothing secret leaves
    /// the app before the peer has proved itself.
    /// </remarks>
    public static string Proof(string nonce, string token)
    {
        using var hmac = new HMACSHA256(Encoding.UTF8.GetBytes(token));
        var hash = hmac.ComputeHash(Encoding.UTF8.GetBytes(nonce));
        return Convert.ToHexString(hash).ToLowerInvariant();
    }

    public static string TokenFilePath(string installDirectory) =>
        Path.Combine(installDirectory, TokenFileName);

    /// <summary>
    /// The token to present to the server, creating and storing one when there
    /// is none yet. Returns null when the token cannot be stored, in which case
    /// the server refuses every request and the app must not talk to it.
    /// </summary>
    public static string? Token(string installDirectory)
    {
        var path = TokenFilePath(installDirectory);
        var stored = StoredTokenAtPath(path);
        if (stored is not null)
        {
            // The token file is written back, so a file an older build left
            // with wider permissions is given the ones it is supposed to
            // have. The macOS port does the same, and a token another
            // account can read is not a secret. It is written back once per
            // process: the health probe reads the token every couple of
            // seconds, and rewriting the file that often is pointless work.
            RepairOnce(path, stored);
            return stored;
        }

        var token = NewToken();
        return WriteToken(token, path) ? token : null;
    }

    private static readonly object RepairLock = new();
    private static readonly HashSet<string> RepairedPaths = new(StringComparer.OrdinalIgnoreCase);

    /// <summary>
    /// Write the token back once per process, so the file carries the
    /// permissions of the directory it was created in.
    /// </summary>
    private static void RepairOnce(string path, string token)
    {
        lock (RepairLock)
        {
            if (!RepairedPaths.Add(path))
            {
                return;
            }
        }

        if (!WriteToken(token, path))
        {
            // A file that could not be written is worth another try later.
            lock (RepairLock)
            {
                RepairedPaths.Remove(path);
            }
        }
    }

    /// <summary>The stored token, without creating one.</summary>
    public static string? StoredToken(string installDirectory) =>
        StoredTokenAtPath(TokenFilePath(installDirectory));

    /// <summary>The stored token at an exact path, without creating one.</summary>
    public static string? StoredTokenAtPath(string path)
    {
        try
        {
            if (!File.Exists(path))
            {
                return null;
            }

            var contents = File.ReadAllText(path).Trim();
            return contents.Length == 0 ? null : contents;
        }
        catch (IOException)
        {
            return null;
        }
        catch (UnauthorizedAccessException)
        {
            return null;
        }
    }

    /// <summary>
    /// Store the token for its owner only.
    /// </summary>
    /// <remarks>
    /// The file lives in the user's own LocalApplicationData directory, whose
    /// ACL already keeps it away from other accounts on the machine — the same
    /// posture the rest of the app's local data takes. The file is created
    /// there only after the directory exists.
    /// </remarks>
    public static bool WriteToken(string token, string path)
    {
        try
        {
            var directory = Path.GetDirectoryName(path);
            if (!string.IsNullOrEmpty(directory))
            {
                Directory.CreateDirectory(directory);
            }

            // The token goes into a temporary file that is moved into place
            // in one step, so a reader never sees a missing or an empty token
            // file.
            var temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
            try
            {
                File.WriteAllText(temporary, token);
                File.Move(temporary, path, overwrite: true);
            }
            finally
            {
                try
                {
                    if (File.Exists(temporary))
                    {
                        File.Delete(temporary);
                    }
                }
                catch (IOException)
                {
                }
                catch (UnauthorizedAccessException)
                {
                }
            }

            return true;
        }
        catch (IOException)
        {
            return false;
        }
        catch (UnauthorizedAccessException)
        {
            return false;
        }
    }

    /// <summary>A fresh random token: 32 random bytes, URL-safe and unpadded.</summary>
    public static string NewToken()
    {
        var bytes = new byte[32];
        using var random = RandomNumberGenerator.Create();
        random.GetBytes(bytes);
        return Convert.ToBase64String(bytes)
            .Replace('+', '-')
            .Replace('/', '_')
            .TrimEnd('=');
    }
}
