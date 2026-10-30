import Foundation
import Security

/// Where the managed local transcription server is installed.
enum LocalServerPaths {
    /// The directory the managed server lives in, and the directory the token
    /// file sits in.
    static var defaultInstallDirectory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BugNarrator/LocalTranscription", isDirectory: true)
    }
}

/// The bearer token the local transcription server requires (#1270).
///
/// The server is an HTTP endpoint on loopback that any process on the machine
/// can reach, so it refuses every request that does not carry the token. The
/// app and the server have to agree on one token, and the token file next to
/// the managed install is where they agree: the app creates the token before
/// it starts the server and hands the same value over through the
/// environment, and a server that was started on its own writes the same file
/// so the app can find it.
///
/// The path, the file name and the environment variable are pinned by
/// `contract-fixtures/local-server-token.json`, which the Windows port and the
/// Python server check against the same file.
enum LocalServerTokenStore {
    /// The file the token is stored in, next to the managed server.
    static let tokenFileName = "bugnarrator-transcription.token"

    /// How the server is told which token to use.
    static let environmentVariable = "BUGNARRATOR_TRANSCRIPTION_TOKEN"

    /// The authorization scheme the server expects.
    static let authorizationScheme = "Bearer"

    static func tokenFileURL(installDirectory: URL) -> URL {
        installDirectory.appendingPathComponent(tokenFileName)
    }

    /// The token to present to the server, creating and storing one when there
    /// is none yet. Returns nil when the token cannot be stored, in which case
    /// the server refuses every request and the app must not talk to it.
    static func token(installDirectory: URL) -> String? {
        let url = tokenFileURL(installDirectory: installDirectory)
        if let stored = storedToken(at: url) {
            // A token file that an older build left readable by anyone else
            // is repaired when the app reads it: the token is written back
            // with the permissions it is supposed to have. A token another
            // account can read is not a secret, so a file that cannot be
            // repaired is a file the app must not use.
            if !isReadableOnlyByItsOwner(url) {
                guard writeToken(stored, at: url) else { return nil }
            }
            return stored
        }
        let token = newToken()
        guard writeToken(token, at: url) else { return nil }
        return token
    }

    /// Whether the file at `url` can be read by its owner and nobody else.
    private static func isReadableOnlyByItsOwner(_ url: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let permissions = attributes[.posixPermissions] as? NSNumber else {
            return false
        }
        return permissions.int16Value == 0o600
    }

    /// The stored token, without creating one.
    static func storedToken(installDirectory: URL) -> String? {
        storedToken(at: tokenFileURL(installDirectory: installDirectory))
    }

    static func storedToken(at url: URL) -> String? {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Store the token for its owner only. The token is written into a
    /// temporary file that only its owner can read and moved into place in one
    /// step, so a reader never sees a missing or an empty token file, and the
    /// token is never readable by anyone else.
    @discardableResult
    static func writeToken(_ token: String, at url: URL) -> Bool {
        let manager = FileManager.default
        do {
            try manager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            // The temporary file is created owner-only and empty, and the
            // token is written into it afterwards: `createFile` applies the
            // mode after it has written, so the token would otherwise sit in
            // a file anyone else could read.
            let temporary = url.deletingLastPathComponent()
                .appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString)")
            guard manager.createFile(
                atPath: temporary.path,
                contents: nil,
                attributes: [.posixPermissions: NSNumber(value: 0o600)]
            ) else {
                return false
            }
            do {
                try Data(token.utf8).write(to: temporary)
                // The file is replaced in one step, so a reader never sees a
                // missing or an empty token file. The new file's metadata is
                // the one that is kept: a token file that was already there
                // with wider permissions would otherwise stay readable by
                // everyone else.
                _ = try manager.replaceItemAt(
                    url,
                    withItemAt: temporary,
                    options: [.usingNewMetadataOnly]
                )
            } catch {
                try? manager.removeItem(at: temporary)
                return false
            }
            return true
        } catch {
            return false
        }
    }

    /// A fresh random token: 32 random bytes, URL-safe and unpadded.
    static func newToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            return UUID().uuidString
        }
        return Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
