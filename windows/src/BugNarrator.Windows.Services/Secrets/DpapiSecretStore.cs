using System.Security.Cryptography;
using System.Text;
using BugNarrator.Windows.Services.Diagnostics;
using BugNarrator.Windows.Services.Storage;

namespace BugNarrator.Windows.Services.Secrets;

public sealed class DpapiSecretStore : ISecretStore
{
    private const long MaxSecretBytes = 16 * 1024;

    private readonly WindowsDiagnostics? diagnostics;
    private readonly string secretsDirectory;

    public DpapiSecretStore(
        AppStoragePaths storagePaths,
        WindowsDiagnostics? diagnostics = null)
    {
        secretsDirectory = storagePaths.SecretsDirectory;
        this.diagnostics = diagnostics;
        Directory.CreateDirectory(secretsDirectory);
    }

    public async ValueTask<string?> GetAsync(string key, CancellationToken cancellationToken = default)
    {
        var secretPath = GetSecretPath(key);
        if (!File.Exists(secretPath))
        {
            return null;
        }

        try
        {
            var fileInfo = new FileInfo(secretPath);
            if (fileInfo.Length > MaxSecretBytes)
            {
                diagnostics?.Warning("secrets", $"ignoring oversized secret material for key {key}");
                return null;
            }

            var protectedBytes = await File.ReadAllBytesAsync(secretPath, cancellationToken);
            var unprotectedBytes = ProtectedData.Unprotect(
                protectedBytes,
                optionalEntropy: null,
                scope: DataProtectionScope.CurrentUser);

            return Encoding.UTF8.GetString(unprotectedBytes);
        }
        catch (CryptographicException)
        {
            diagnostics?.Warning("secrets", $"ignoring unreadable protected secret material for key {key}");
            return null;
        }
        catch (IOException)
        {
            diagnostics?.Warning("secrets", $"ignoring inaccessible secret material for key {key}");
            return null;
        }
    }

    public async ValueTask SetAsync(string key, string value, CancellationToken cancellationToken = default)
    {
        var normalizedValue = value.Trim();
        if (normalizedValue.Length == 0)
        {
            await RemoveAsync(key, cancellationToken);
            return;
        }

        Directory.CreateDirectory(secretsDirectory);

        var secretPath = GetSecretPath(key);
        var protectedBytes = ProtectedData.Protect(
            Encoding.UTF8.GetBytes(normalizedValue),
            optionalEntropy: null,
            scope: DataProtectionScope.CurrentUser);

        await AtomicFileOperations.WriteAllBytesAsync(secretPath, protectedBytes, cancellationToken);
    }

    public ValueTask RemoveAsync(string key, CancellationToken cancellationToken = default)
    {
        var secretPath = GetSecretPath(key);
        if (File.Exists(secretPath))
        {
            File.Delete(secretPath);
        }

        return ValueTask.CompletedTask;
    }

    private string GetSecretPath(string key)
    {
        var keyBytes = Encoding.UTF8.GetBytes(key);
        var hash = Convert.ToHexString(SHA256.HashData(keyBytes));
        return Path.Combine(secretsDirectory, $"{hash}.secret");
    }
}
