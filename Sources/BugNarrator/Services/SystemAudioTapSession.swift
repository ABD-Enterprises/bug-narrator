import AudioToolbox
@preconcurrency import AVFoundation
import Foundation

final class SystemAudioTapSession {
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
            throw AppError.systemAudioUnavailable(Self.tapPermissionRecoveryMessage(status: status))
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

    private static func tapPermissionRecoveryMessage(status: OSStatus) -> String {
        "macOS refused to create the system audio tap. This usually means System Audio Recording permission has not been granted to BugNarrator yet. Open System Settings > Privacy & Security > Screen & System Audio Recording, enable BugNarrator, then try again. (Core Audio status \(status).)"
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
