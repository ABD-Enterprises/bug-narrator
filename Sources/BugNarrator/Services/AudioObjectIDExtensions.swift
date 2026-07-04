import CoreAudio
import Foundation

extension AudioObjectID {
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
