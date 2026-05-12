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

        do {
            let probe = SystemAudioTapSession()
            _ = try probe.prepare()
            probe.invalidate()
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

        do {
            try FileManager.default.createDirectory(at: recoveryDirectoryURL, withIntermediateDirectories: true)
            let session = SystemAudioTapSession()
            let format = try session.prepare()
            let fileURL = makeRecoverableRecordingURL()
            let writer = try SystemAudioFileWriter(fileURL: fileURL, format: format)

            try session.start(on: ioQueue, writer: writer)

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
            recordingLogger.error("system_audio_recording_start_failed", error.userMessage)
            throw error
        } catch {
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
        activeWriter.close()
        cleanupActiveState()

        try validateRecordedAudioFile(at: currentFileURL)

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
        activeWriter?.close()
        cleanupActiveState()

        guard !preserveFile, let fileURL else {
            return
        }

        try? FileManager.default.removeItem(at: fileURL)
    }

    private func cleanupActiveState() {
        tapSession = nil
        activeWriter = nil
        currentFileURL = nil
        recordingStartedAt = nil
    }

    private func validateRecordedAudioFile(at url: URL) throws {
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
}

private final class SystemAudioTapSession {
    private var processTapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
    private var deviceProcID: AudioDeviceIOProcID?
    private var audioFormat: AVAudioFormat?

    @available(macOS 14.2, *)
    func prepare() throws -> AVAudioFormat {
        guard audioFormat == nil else {
            guard let audioFormat else {
                throw AppError.systemAudioUnavailable("The system audio tap was not prepared.")
            }
            return audioFormat
        }

        let excludedProcesses = (try? Self.currentProcessObjectIDs()) ?? []
        let tapDescription = CATapDescription(stereoGlobalTapButExcludeProcesses: excludedProcesses)
        tapDescription.uuid = UUID()
        tapDescription.name = "BugNarrator System Audio"
        tapDescription.isPrivate = true
        tapDescription.muteBehavior = .unmuted

        var tapID = AudioObjectID(kAudioObjectUnknown)
        var status = AudioHardwareCreateProcessTap(tapDescription, &tapID)
        guard status == noErr else {
            throw AppError.systemAudioUnavailable(Self.recoveryMessage("Core Audio tap creation failed with status \(status)."))
        }

        processTapID = tapID

        let outputDeviceID = try AudioObjectID.defaultSystemOutputDevice()
        let outputDeviceUID = try outputDeviceID.deviceUID()
        let streamDescription = try tapID.audioTapStreamDescription()
        var mutableStreamDescription = streamDescription

        guard let format = AVAudioFormat(streamDescription: &mutableStreamDescription) else {
            throw AppError.systemAudioUnavailable("BugNarrator could not read the system audio format.")
        }

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "BugNarrator System Audio",
            kAudioAggregateDeviceUIDKey: "BugNarrator.SystemAudio.\(UUID().uuidString)",
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
        return format
    }

    @available(macOS 14.2, *)
    func start(on queue: DispatchQueue, writer: SystemAudioFileWriter) throws {
        guard aggregateDeviceID != AudioObjectID(kAudioObjectUnknown) else {
            throw AppError.systemAudioUnavailable("The system audio device was not prepared.")
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

        status = AudioDeviceStart(aggregateDeviceID, deviceProcID)
        guard status == noErr else {
            throw AppError.systemAudioUnavailable(Self.recoveryMessage("Core Audio refused to start system audio capture with status \(status)."))
        }
    }

    func invalidate() {
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
    }

    deinit {
        invalidate()
    }

    private static func recoveryMessage(_ details: String) -> String {
        "Open System Settings > Privacy & Security > Screen & System Audio Recording, enable BugNarrator, then try again. \(details)"
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

private final class SystemAudioFileWriter: @unchecked Sendable {
    private let lock = NSLock()
    private let format: AVAudioFormat
    private var file: AVAudioFile?

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

        try? file.write(from: buffer)
    }

    func close() {
        lock.lock()
        file = nil
        lock.unlock()
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
