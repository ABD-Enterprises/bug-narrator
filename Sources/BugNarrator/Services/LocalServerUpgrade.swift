import Darwin
import Foundation
import Security

extension LocalTranscriptionManager {
    nonisolated static let protocolReceipt = "server-protocol-version"

    nonisolated static func requiresUpgrade(_ directory: URL) -> Bool {
        let binary = directory.appendingPathComponent("bugnarrator-transcription")
        guard let handle = try? FileHandle(forReadingFrom: binary) else { return false }
        defer { try? handle.close() }
        let magic = try? handle.read(upToCount: 4)
        guard magic == Data([0xcf, 0xfa, 0xed, 0xfe]) || magic == Data([0xca, 0xfe, 0xba, 0xbe]) else { return false }
        return (try? String(contentsOf: directory.appendingPathComponent(protocolReceipt), encoding: .utf8)) != "1\n"
    }

    // Only retire this user's signed managed executable. Never kill a process
    // merely because it occupies the transcription port or shares a name.
    nonisolated static func retireVerifiedProcesses(
        _ binary: URL,
        authenticate: (pid_t) -> Bool = authenticatedServer
    ) throws {
        let expectedPath = binary.resolvingSymlinksInPath().standardizedFileURL.path
        let capacity = Int(proc_listallpids(nil, 0)) + 256
        var pids = [pid_t](repeating: 0, count: capacity)
        let count = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        guard count > 0, count < capacity else { throw Failure("Could not safely enumerate local server processes. Try again.") }
        func matches(_ pid: pid_t) -> Bool {
            var info = proc_bsdinfo()
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout.size(ofValue: info))) > 0,
                  info.pbi_uid == getuid() else { return false }
            var path = [CChar](repeating: 0, count: 4096)
            guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { return false }
            let reportedPath = String(decoding: path.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            let canonicalPath = URL(fileURLWithPath: reportedPath).resolvingSymlinksInPath().standardizedFileURL.path
            return canonicalPath == expectedPath && authenticate(pid)
        }
        for pid in pids.prefix(Int(count)) where pid != getpid() && matches(pid) {
            try Task.checkCancellation()
            // Recheck identity immediately before signaling; don't escalate to
            // SIGKILL or act on a PID whose identity has changed.
            guard matches(pid) else { continue }
            if kill(pid, SIGTERM) != 0 && errno != ESRCH { throw Failure("Could not stop the previous local server.") }
            let deadline = Date().addingTimeInterval(5)
            while matches(pid), Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if matches(pid) { throw Failure("The previous local server is still stopping. Try updating again.") }
        }
    }

    nonisolated static func authenticatedServer(_ pid: pid_t) -> Bool {
        var code: SecCode?
        let attributes = [kSecGuestAttributePid: NSNumber(value: pid)] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess,
              let code else { return false }
        var requirement: SecRequirement?
        let expression = publisherRequirement + " and identifier \"bugnarrator-transcription\""
        guard SecRequirementCreateWithString(expression as CFString, [], &requirement) == errSecSuccess else { return false }
        return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
    }
}
