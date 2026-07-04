import AudioToolbox
@preconcurrency import AVFoundation
import Foundation

@MainActor
final class SystemAudioRecorder: AudioRecording {
    private let recordingLogger = DiagnosticsLogger(category: .recording)
    private let recoveryDirectoryURL: URL
    private let ioQueue = DispatchQueue(label: "BugNarrator.SystemAudioRecorder.IO", qos: .userInitiated)

    private var tapSession: SystemAudioTapSession?
    private var activeWriter: SystemAudioFileWriter?
    private var currentFileURL: URL?
    private var recordingStartedAt: Date?

    init(
        recoveryDirectoryURL: URL = AppSupportLocation.appDirectory()
            .appendingPathComponent("RecoveredRecordings", isDirectory: true)
    ) {
        self.recoveryDirectoryURL = recoveryDirectoryURL
    }

    var currentDuration: TimeInterval {
        guard let recordingStartedAt else {
            return 0
        }

        return Date().timeIntervalSince(recordingStartedAt)
    }

    var requiresMicrophonePermission: Bool {
        false
    }

    func validateRecordingPrerequisites() async -> AppError? {
        guard tapSession == nil, activeWriter == nil else {
            return .recordingFailure("A recording session is already active.")
        }

        guard #available(macOS 14.2, *) else {
            return .systemAudioUnavailable("System audio capture requires macOS 14.2 or later.")
        }

        logAggregateDeviceCleanupSummary(SystemAudioTapSession.cleanupStaleAggregateDevices())

        do {
            let probe = SystemAudioTapSession()
            do {
                _ = try probe.prepare()
                probe.invalidate()
            } catch {
                probe.invalidate()
                throw error
            }
            return nil
        } catch let error as AppError {
            return error
        } catch {
            return .systemAudioUnavailable(systemAudioRecoveryMessage(details: error.localizedDescription))
        }
    }

    func validateRecordingActivation() async -> AppError? {
        await validateRecordingPrerequisites()
    }

    func startRecording() async throws {
        recordingLogger.info("system_audio_recording_start_requested", "System audio recording start was requested.")

        guard tapSession == nil, activeWriter == nil else {
            throw AppError.recordingFailure("A recording session is already active.")
        }

        guard #available(macOS 14.2, *) else {
            throw AppError.systemAudioUnavailable("System audio capture requires macOS 14.2 or later.")
        }

        logAggregateDeviceCleanupSummary(SystemAudioTapSession.cleanupStaleAggregateDevices())

        let session = SystemAudioTapSession()
        var writer: SystemAudioFileWriter?

        do {
            try FileManager.default.createDirectory(at: recoveryDirectoryURL, withIntermediateDirectories: true)
            let format = try session.prepare()
            let fileURL = makeRecoverableRecordingURL()
            let preparedWriter = try SystemAudioFileWriter(fileURL: fileURL, format: format)
            writer = preparedWriter

            try session.start(on: ioQueue, writer: preparedWriter)

            tapSession = session
            activeWriter = writer
            currentFileURL = fileURL
            recordingStartedAt = Date()

            recordingLogger.info(
                "system_audio_recording_started",
                "System audio recording started successfully.",
                metadata: ["file_name": fileURL.lastPathComponent]
            )
        } catch let error as AppError {
            session.invalidate()
            try? writer?.close()
            recordingLogger.error("system_audio_recording_start_failed", error.userMessage)
            throw error
        } catch {
            session.invalidate()
            try? writer?.close()
            recordingLogger.error("system_audio_recording_start_failed", error.localizedDescription)
            throw AppError.systemAudioUnavailable(systemAudioRecoveryMessage(details: error.localizedDescription))
        }
    }

    func stopRecording() async throws -> RecordedAudio {
        guard let tapSession, let activeWriter, let currentFileURL else {
            throw AppError.recordingFailure("There is no active recording.")
        }

        let duration = currentDuration
        recordingLogger.info(
            "system_audio_recording_stop_requested",
            "System audio recording is being finalized.",
            metadata: ["file_name": currentFileURL.lastPathComponent]
        )

        tapSession.invalidate()
        await ioQueue.drain()
        try await Self.closeWriter(activeWriter)
        cleanupActiveState()

        try await Self.validateRecordedAudioFile(at: currentFileURL)

        recordingLogger.info(
            "system_audio_recording_stopped",
            "System audio recording finished successfully.",
            metadata: [
                "file_name": currentFileURL.lastPathComponent,
                "duration_seconds": String(format: "%.2f", duration)
            ]
        )

        return RecordedAudio(fileURL: currentFileURL, duration: duration)
    }

    func cancelRecording(preserveFile: Bool) async {
        let fileURL = currentFileURL
        tapSession?.invalidate()
        await ioQueue.drain()
        if let activeWriter {
            try? await Self.closeWriter(activeWriter)
        }
        cleanupActiveState()

        guard !preserveFile, let fileURL else {
            return
        }

        await Self.removeItemIfPresent(at: fileURL)
    }

    private func cleanupActiveState() {
        tapSession = nil
        activeWriter = nil
        currentFileURL = nil
        recordingStartedAt = nil
    }

    private static func closeWriter(_ writer: SystemAudioFileWriter) async throws {
        try await Task.detached(priority: .userInitiated) {
            try writer.close()
        }.value
    }

    private static func removeItemIfPresent(at url: URL) async {
        await Task.detached(priority: .utility) {
            try? FileManager.default.removeItem(at: url)
        }.value
    }

    private static func validateRecordedAudioFile(at url: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            try validateRecordedAudioFileSynchronously(at: url)
        }.value
    }

    private nonisolated static func validateRecordedAudioFileSynchronously(at url: URL) throws {
        let attributes: [FileAttributeKey: Any]

        do {
            attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        } catch {
            throw AppError.recordingFailure("The recorded system audio file could not be found.")
        }

        let fileSize = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard fileSize > 0 else {
            throw AppError.recordingFailure("The recorded system audio file was empty.")
        }

        do {
            let audioFile = try AVAudioFile(forReading: url)
            guard audioFile.fileFormat.sampleRate > 0, audioFile.length > 0 else {
                throw AppError.recordingFailure("The recorded system audio file did not contain playable audio.")
            }
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.recordingFailure("The recorded system audio file could not be read.")
        }
    }

    private func makeRecoverableRecordingURL() -> URL {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        let timestamp = formatter
            .string(from: Date())
            .replacingOccurrences(of: ":", with: "-")

        return recoveryDirectoryURL
            .appendingPathComponent("\(timestamp)-system-audio-\(UUID().uuidString)")
            .appendingPathExtension("wav")
    }

    private func systemAudioRecoveryMessage(details: String) -> String {
        let trimmedDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = trimmedDetails.isEmpty ? "" : " \(trimmedDetails)"
        return "Open System Settings > Privacy & Security > Screen & System Audio Recording, enable BugNarrator, then try again.\(suffix)"
    }

    private func logAggregateDeviceCleanupSummary(_ summary: SystemAudioAggregateDeviceCleanupSummary) {
        guard summary.destroyedCount > 0 || summary.failedCount > 0 || summary.scanFailed else {
            return
        }

        let levelMessage = summary.failedCount > 0 || summary.scanFailed
            ? "BugNarrator found stale system audio devices, but some could not be cleaned up."
            : "BugNarrator cleaned up stale system audio devices before recording."
        let metadata = [
            "inspected_count": "\(summary.inspectedCount)",
            "destroyed_count": "\(summary.destroyedCount)",
            "failed_count": "\(summary.failedCount)",
            "scan_failed": "\(summary.scanFailed)"
        ]

        if summary.failedCount > 0 || summary.scanFailed {
            recordingLogger.warning(
                "system_audio_stale_aggregate_cleanup_partial",
                levelMessage,
                metadata: metadata
            )
        } else {
            recordingLogger.info(
                "system_audio_stale_aggregate_cleanup_succeeded",
                levelMessage,
                metadata: metadata
            )
        }
    }
}

private final class SystemAudioTapSession {
    private var processTapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
    private var deviceProcID: AudioDeviceIOProcID?
    private var outputDeviceID = AudioObjectID(kAudioObjectUnknown)
    private var nominalSampleRateListener: AudioObjectPropertyListenerBlock?
    private let listenerQueue = DispatchQueue(label: "BugNarrator.SystemAudioRecorder.FormatListener", qos: .userInitiated)
    private var audioFormat: AVAudioFormat?

    static func cleanupStaleAggregateDevices() -> SystemAudioAggregateDeviceCleanupSummary {
        var summary = SystemAudioAggregateDeviceCleanupSummary()

        let devices: [AudioObjectID]
        do {
            devices = try AudioObjectID.systemObject.audioDevices()
        } catch {
            summary.scanFailed = true
            return summary
        }

        for deviceID in devices {
            guard let deviceUID = try? deviceID.deviceUID(),
                  SystemAudioAggregateDeviceIdentity.isOwnedAggregateDeviceUID(deviceUID) else {
                continue
            }

            summary.inspectedCount += 1
            let status = AudioHardwareDestroyAggregateDevice(deviceID)
            if status == noErr {
                summary.destroyedCount += 1
            } else {
                summary.failedCount += 1
            }
        }

        return summary
    }

    @available(macOS 14.2, *)
    func prepare() throws -> AVAudioFormat {
        guard audioFormat == nil else {
            guard let audioFormat else {
                throw AppError.systemAudioUnavailable("The system audio tap was not prepared.")
            }
            return audioFormat
        }

        var preparedSuccessfully = false
        defer {
            if !preparedSuccessfully {
                invalidate()
            }
        }

        let excludedProcesses = (try? Self.currentProcessObjectIDs()) ?? []
        let tapDescription = CATapDescription(stereoGlobalTapButExcludeProcesses: excludedProcesses)
        tapDescription.uuid = UUID()
        tapDescription.name = SystemAudioAggregateDeviceIdentity.name
        tapDescription.isPrivate = true
        tapDescription.muteBehavior = .unmuted

        var tapID = AudioObjectID(kAudioObjectUnknown)
        var status = AudioHardwareCreateProcessTap(tapDescription, &tapID)
        guard status == noErr else {
            throw AppError.systemAudioUnavailable(Self.recoveryMessage("Core Audio tap creation failed with status \(status)."))
        }

        processTapID = tapID

        let outputDeviceID = try AudioObjectID.defaultSystemOutputDevice()
        self.outputDeviceID = outputDeviceID
        let outputDeviceUID = try outputDeviceID.deviceUID()
        let streamDescription = try tapID.audioTapStreamDescription()
        var mutableStreamDescription = streamDescription

        guard let format = AVAudioFormat(streamDescription: &mutableStreamDescription) else {
            throw AppError.systemAudioUnavailable("BugNarrator could not read the system audio format.")
        }

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: SystemAudioAggregateDeviceIdentity.name,
            kAudioAggregateDeviceUIDKey: SystemAudioAggregateDeviceIdentity.makeUID(),
            kAudioAggregateDeviceMainSubDeviceKey: outputDeviceUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [
                    kAudioSubDeviceUIDKey: outputDeviceUID
                ]
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: tapDescription.uuid.uuidString
                ]
            ]
        ]

        aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
        status = AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregateDeviceID)
        guard status == noErr else {
            throw AppError.systemAudioUnavailable(Self.recoveryMessage("Core Audio aggregate device creation failed with status \(status)."))
        }

        audioFormat = format
        preparedSuccessfully = true
        return format
    }

    @available(macOS 14.2, *)
    func start(on queue: DispatchQueue, writer: SystemAudioFileWriter) throws {
        guard aggregateDeviceID != AudioObjectID(kAudioObjectUnknown) else {
            throw AppError.systemAudioUnavailable("The system audio device was not prepared.")
        }

        var startedSuccessfully = false
        defer {
            if !startedSuccessfully {
                invalidate()
            }
        }

        var status = AudioDeviceCreateIOProcIDWithBlock(
            &deviceProcID,
            aggregateDeviceID,
            queue
        ) { _, inputData, _, _, _ in
            writer.write(bufferList: inputData)
        }
        guard status == noErr else {
            throw AppError.systemAudioUnavailable(Self.recoveryMessage("Core Audio could not create the system audio callback with status \(status)."))
        }

        try installFormatChangeListener(writer: writer)

        status = AudioDeviceStart(aggregateDeviceID, deviceProcID)
        guard status == noErr else {
            throw AppError.systemAudioUnavailable(Self.recoveryMessage("Core Audio refused to start system audio capture with status \(status)."))
        }
        startedSuccessfully = true
    }

    func invalidate() {
        removeFormatChangeListener()

        if aggregateDeviceID != AudioObjectID(kAudioObjectUnknown) {
            _ = AudioDeviceStop(aggregateDeviceID, deviceProcID)

            if let deviceProcID {
                _ = AudioDeviceDestroyIOProcID(aggregateDeviceID, deviceProcID)
                self.deviceProcID = nil
            }

            _ = AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
        }

        if processTapID != AudioObjectID(kAudioObjectUnknown) {
            if #available(macOS 14.2, *) {
                _ = AudioHardwareDestroyProcessTap(processTapID)
            }
            processTapID = AudioObjectID(kAudioObjectUnknown)
        }

        audioFormat = nil
        outputDeviceID = AudioObjectID(kAudioObjectUnknown)
    }

    deinit {
        invalidate()
    }

    private static func recoveryMessage(_ details: String) -> String {
        "Open System Settings > Privacy & Security > Screen & System Audio Recording, enable BugNarrator, then try again. \(details)"
    }

    private func installFormatChangeListener(writer: SystemAudioFileWriter) throws {
        guard outputDeviceID != AudioObjectID(kAudioObjectUnknown) else {
            return
        }

        var address = Self.nominalSampleRateAddress()
        let listenerBlock: AudioObjectPropertyListenerBlock = { _, _ in
            writer.markFormatInvalidated()
        }
        let status = AudioObjectAddPropertyListenerBlock(
            outputDeviceID,
            &address,
            listenerQueue,
            listenerBlock
        )
        guard status == noErr else {
            throw AppError.systemAudioUnavailable(Self.recoveryMessage("Core Audio could not monitor output device format changes with status \(status)."))
        }

        nominalSampleRateListener = listenerBlock
    }

    private func removeFormatChangeListener() {
        guard let nominalSampleRateListener,
              outputDeviceID != AudioObjectID(kAudioObjectUnknown) else {
            return
        }

        var address = Self.nominalSampleRateAddress()
        _ = AudioObjectRemovePropertyListenerBlock(
            outputDeviceID,
            &address,
            listenerQueue,
            nominalSampleRateListener
        )
        self.nominalSampleRateListener = nil
    }

    private static func nominalSampleRateAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func currentProcessObjectIDs() throws -> [AudioObjectID] {
        let processID = getpid()
        let objectID: AudioObjectID = try AudioObjectID.systemObject.read(
            kAudioHardwarePropertyTranslatePIDToProcessObject,
            defaultValue: AudioObjectID(kAudioObjectUnknown),
            qualifier: processID
        )
        return objectID == AudioObjectID(kAudioObjectUnknown) ? [] : [objectID]
    }
}

// Thread-safety invariant: every access to the mutable state (`file`,
// `writeError`, `formatInvalidated`) is serialized through `lock`, so this type
// is safe to share across the CoreAudio callback thread and the recording actor
// despite `AVAudioFile` not being Sendable. Hence the `@unchecked` is sound.
final class SystemAudioFileWriter: @unchecked Sendable {
    private let lock = NSLock()
    private let format: AVAudioFormat
    private var file: AVAudioFile?
    private var writeError: Error?
    private var formatInvalidated = false

    init(fileURL: URL, format: AVAudioFormat) throws {
        self.format = format
        self.file = try AVAudioFile(
            forWriting: fileURL,
            settings: format.settings,
            commonFormat: format.commonFormat,
            interleaved: format.isInterleaved
        )
    }

    func write(bufferList: UnsafePointer<AudioBufferList>) {
        lock.lock()
        defer {
            lock.unlock()
        }

        guard let file,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: bufferList, deallocator: nil) else {
            return
        }

        do {
            try file.write(from: buffer)
        } catch {
            writeError = error
        }
    }

    func markFormatInvalidated() {
        lock.lock()
        formatInvalidated = true
        lock.unlock()
    }

    func close() throws {
        lock.lock()
        let writeError = writeError
        let formatInvalidated = formatInvalidated
        file = nil
        self.writeError = nil
        self.formatInvalidated = false
        lock.unlock()

        if formatInvalidated {
            throw AppError.recordingFailure(
                "System audio format changed while recording. Stop and start a new recording after changing output devices or sample rate."
            )
        }

        if let writeError {
            throw AppError.recordingFailure("System audio could not be written. \(writeError.localizedDescription)")
        }
    }
}

private extension DispatchQueue {
    func drain() async {
        await withCheckedContinuation { continuation in
            async {
                continuation.resume()
            }
        }
    }
}

private extension AudioObjectID {
    static var systemObject: AudioObjectID {
        AudioObjectID(kAudioObjectSystemObject)
    }

    static func defaultSystemOutputDevice() throws -> AudioDeviceID {
        try systemObject.read(
            kAudioHardwarePropertyDefaultSystemOutputDevice,
            defaultValue: AudioDeviceID(kAudioObjectUnknown)
        )
    }

    func audioDevices() throws -> [AudioObjectID] {
        try readArray(kAudioHardwarePropertyDevices, defaultValue: AudioObjectID(kAudioObjectUnknown))
            .filter { $0 != AudioObjectID(kAudioObjectUnknown) }
    }

    func deviceUID() throws -> String {
        try readString(kAudioDevicePropertyDeviceUID)
    }

    func audioTapStreamDescription() throws -> AudioStreamBasicDescription {
        try read(kAudioTapPropertyFormat, defaultValue: AudioStreamBasicDescription())
    }

    func readString(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) throws -> String {
        let value: CFString = try read(
            selector,
            scope: scope,
            element: element,
            defaultValue: "" as CFString
        )
        return value as String
    }

    func read<T, Q>(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
        defaultValue: T,
        qualifier: Q
    ) throws -> T {
        var qualifier = qualifier
        let qualifierSize = UInt32(MemoryLayout<Q>.size)
        return try withUnsafeMutablePointer(to: &qualifier) { qualifierPointer in
            try read(
                selector,
                scope: scope,
                element: element,
                defaultValue: defaultValue,
                qualifierSize: qualifierSize,
                qualifierData: qualifierPointer
            )
        }
    }

    func read<T>(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
        defaultValue: T
    ) throws -> T {
        try read(
            selector,
            scope: scope,
            element: element,
            defaultValue: defaultValue,
            qualifierSize: 0,
            qualifierData: nil
        )
    }

    func readArray<T>(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
        defaultValue: T
    ) throws -> [T] {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: element
        )
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            self,
            &address,
            0,
            nil,
            &dataSize
        )

        guard status == noErr else {
            throw AppError.systemAudioUnavailable("Core Audio property size read failed with status \(status).")
        }

        let elementCount = Int(dataSize) / MemoryLayout<T>.stride
        guard elementCount > 0 else {
            return []
        }

        var values = Array(repeating: defaultValue, count: elementCount)
        status = values.withUnsafeMutableBufferPointer { buffer in
            AudioObjectGetPropertyData(
                self,
                &address,
                0,
                nil,
                &dataSize,
                buffer.baseAddress!
            )
        }

        guard status == noErr else {
            throw AppError.systemAudioUnavailable("Core Audio property read failed with status \(status).")
        }

        return values
    }

    private func read<T>(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        element: AudioObjectPropertyElement,
        defaultValue: T,
        qualifierSize: UInt32,
        qualifierData: UnsafeRawPointer?
    ) throws -> T {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: element
        )
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            self,
            &address,
            qualifierSize,
            qualifierData,
            &dataSize
        )

        guard status == noErr else {
            throw AppError.systemAudioUnavailable("Core Audio property size read failed with status \(status).")
        }

        var value = defaultValue
        status = withUnsafeMutablePointer(to: &value) { valuePointer in
            AudioObjectGetPropertyData(
                self,
                &address,
                qualifierSize,
                qualifierData,
                &dataSize,
                valuePointer
            )
        }

        guard status == noErr else {
            throw AppError.systemAudioUnavailable("Core Audio property read failed with status \(status).")
        }

        return value
    }
}
