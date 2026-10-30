using System.Buffers.Binary;
using System.Security.Cryptography;

namespace BugNarrator.Windows.Services.Storage;

public interface ISessionDataProtector
{
    byte[] Protect(byte[] plaintext);
    byte[] Unprotect(byte[] payload);
}

public sealed class WindowsSessionDataProtector : ISessionDataProtector
{
    private static readonly byte[] Prefix = "BNWENC1\n"u8.ToArray();
    private const int NonceSize = 12;
    private const int TagSize = 16;
    private const int MaxWrappedKeySize = 16 * 1024;
    internal const int MaxEnvelopeOverhead = 8 + sizeof(int) + MaxWrappedKeySize + NonceSize + TagSize;

    public byte[] Protect(byte[] plaintext)
    {
        var key = RandomNumberGenerator.GetBytes(32);
        try
        {
            // A fresh per-file key avoids persistent-key creation races and is never stored in plaintext.
            var wrappedKey = ProtectedData.Protect(key, null, DataProtectionScope.CurrentUser);
            var payload = new byte[Prefix.Length + sizeof(int) + wrappedKey.Length + NonceSize + TagSize + plaintext.Length];
            Prefix.CopyTo(payload, 0);
            BinaryPrimitives.WriteInt32LittleEndian(payload.AsSpan(Prefix.Length), wrappedKey.Length);
            wrappedKey.CopyTo(payload, Prefix.Length + sizeof(int));
            var nonceOffset = Prefix.Length + sizeof(int) + wrappedKey.Length;
            var nonce = payload.AsSpan(nonceOffset, NonceSize);
            RandomNumberGenerator.Fill(nonce);
            using var aes = new AesGcm(key, TagSize);
            aes.Encrypt(
                nonce,
                plaintext,
                payload.AsSpan(nonceOffset + NonceSize + TagSize),
                payload.AsSpan(nonceOffset + NonceSize, TagSize),
                Prefix);
            return payload;
        }
        finally
        {
            CryptographicOperations.ZeroMemory(key);
        }
    }

    public byte[] Unprotect(byte[] payload)
    {
        if (!payload.AsSpan().StartsWith(Prefix))
        {
            // Older Windows libraries were plaintext, including early UTF-8 BOM JSON files.
            return payload;
        }

        if (payload.Length < Prefix.Length + sizeof(int))
        {
            throw new CryptographicException("The encrypted session envelope is incomplete.");
        }

        var wrappedKeySize = BinaryPrimitives.ReadInt32LittleEndian(payload.AsSpan(Prefix.Length));
        if (wrappedKeySize <= 0 || wrappedKeySize > MaxWrappedKeySize
            || payload.Length < Prefix.Length + sizeof(int) + wrappedKeySize + NonceSize + TagSize)
        {
            throw new CryptographicException("The encrypted session envelope is invalid.");
        }

        var key = ProtectedData.Unprotect(
            payload.AsSpan(Prefix.Length + sizeof(int), wrappedKeySize).ToArray(),
            null,
            DataProtectionScope.CurrentUser);
        try
        {
            var nonceOffset = Prefix.Length + sizeof(int) + wrappedKeySize;
            var plaintext = new byte[payload.Length - nonceOffset - NonceSize - TagSize];
            using var aes = new AesGcm(key, TagSize);
            aes.Decrypt(
                payload.AsSpan(nonceOffset, NonceSize),
                payload.AsSpan(nonceOffset + NonceSize + TagSize),
                payload.AsSpan(nonceOffset + NonceSize, TagSize),
                plaintext,
                Prefix);
            return plaintext;
        }
        finally
        {
            CryptographicOperations.ZeroMemory(key);
        }
    }
}
