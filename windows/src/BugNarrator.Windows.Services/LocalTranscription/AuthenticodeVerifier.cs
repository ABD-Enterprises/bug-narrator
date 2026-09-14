using System.Runtime.InteropServices;
using System.Security.Cryptography.X509Certificates;

namespace BugNarrator.Windows.Services.LocalTranscription;

/// <summary>Verifies that an executable is signed by the BugNarrator publisher; throws <see cref="LocalServerFailure"/> otherwise.</summary>
public interface IAuthenticodeVerifier
{
    void Verify(string executablePath);
}

/// <summary>
/// Authenticode check in two halves, the Windows analogue of the macOS <c>codesign --verify --strict -R</c>
/// on the team OU: WinVerifyTrust validates the signature and the file digest (a binary modified
/// after signing fails here), then the signer's distinguished name must carry the exact publisher
/// organization. Revocation is checked online when reachable and does not fail the check offline,
/// so an offline machine can still start an already-installed server.
/// </summary>
public sealed class AuthenticodeVerifier : IAuthenticodeVerifier
{
    public const string PublisherOrganization = "ABD Enterprises";

    public void Verify(string executablePath)
    {
        var status = WinVerifyTrustFile(executablePath);
        if (status != 0)
        {
            throw new LocalServerFailure(status == TrustENoSignature
                ? "The local server executable is not signed by the BugNarrator publisher. Remove and reinstall it."
                : $"The local server executable's signature could not be verified (0x{status:X8}). Remove and reinstall it.");
        }

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
            if (!SignedBy(certificate.SubjectName, PublisherOrganization))
            {
                throw new LocalServerFailure("The local server executable is not signed by the BugNarrator publisher. Remove and reinstall it.");
            }
        }
    }

    /// <summary>Exact match on the O= relative distinguished name — never a substring.</summary>
    public static bool SignedBy(X500DistinguishedName subject, string organization)
    {
        foreach (var rdn in subject.EnumerateRelativeDistinguishedNames())
        {
            if (rdn.HasMultipleElements)
            {
                continue;
            }

            if (rdn.GetSingleElementType().Value == "2.5.4.10"
                && string.Equals(rdn.GetSingleElementValue(), organization, StringComparison.Ordinal))
            {
                return true;
            }
        }

        return false;
    }

    private const uint TrustENoSignature = 0x800B0100;
    private const uint WtdUiNone = 2;
    private const uint WtdRevokeWholeChain = 1;
    private const uint WtdChoiceFile = 1;
    private const uint WtdStateActionVerify = 1;
    private const uint WtdStateActionClose = 2;
    private const uint WtdRevocationCheckChain = 0x40;
    private const uint WtdCacheOnlyUrlRetrieval = 0x1000;
    private static readonly Guid WintrustActionGenericVerifyV2 = new("00AAC56B-CD44-11d0-8CC2-00C04FC295EE");

    private static uint WinVerifyTrustFile(string path)
    {
        var fileInfo = new WintrustFileInfo
        {
            cbStruct = (uint)Marshal.SizeOf<WintrustFileInfo>(),
            pcwszFilePath = path,
        };
        var fileInfoPointer = Marshal.AllocHGlobal(Marshal.SizeOf<WintrustFileInfo>());
        try
        {
            Marshal.StructureToPtr(fileInfo, fileInfoPointer, fDeleteOld: false);
            var data = new WintrustData
            {
                cbStruct = (uint)Marshal.SizeOf<WintrustData>(),
                dwUIChoice = WtdUiNone,
                fdwRevocationChecks = WtdRevokeWholeChain,
                dwUnionChoice = WtdChoiceFile,
                pFile = fileInfoPointer,
                dwStateAction = WtdStateActionVerify,
                // Revocation from the chain when reachable; cache-only retrieval keeps an offline
                // start from hanging on a CRL fetch and does not turn "unreachable" into "revoked".
                dwProvFlags = WtdRevocationCheckChain | WtdCacheOnlyUrlRetrieval,
            };
            var action = WintrustActionGenericVerifyV2;
            var status = WinVerifyTrust(IntPtr.Zero, ref action, ref data);
            data.dwStateAction = WtdStateActionClose;
            WinVerifyTrust(IntPtr.Zero, ref action, ref data);
            return status;
        }
        finally
        {
            Marshal.FreeHGlobal(fileInfoPointer);
        }
    }

    [DllImport("wintrust.dll", ExactSpelling = true, SetLastError = false)]
    private static extern uint WinVerifyTrust(IntPtr hwnd, ref Guid pgActionID, ref WintrustData pWVTData);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct WintrustFileInfo
    {
        public uint cbStruct;
        [MarshalAs(UnmanagedType.LPWStr)] public string pcwszFilePath;
        public IntPtr hFile;
        public IntPtr pgKnownSubject;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct WintrustData
    {
        public uint cbStruct;
        public IntPtr pPolicyCallbackData;
        public IntPtr pSIPClientData;
        public uint dwUIChoice;
        public uint fdwRevocationChecks;
        public uint dwUnionChoice;
        public IntPtr pFile;
        public uint dwStateAction;
        public IntPtr hWVTStateData;
        public IntPtr pwszURLReference;
        public uint dwProvFlags;
        public uint dwUIContext;
        public IntPtr pSignatureSettings;
    }
}
