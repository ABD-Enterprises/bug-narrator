import Darwin
import Foundation

enum SystemDiagnosticsInfo {
    static func currentArchitecture() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineField = systemInfo.machine

        let machine = withUnsafePointer(to: machineField) { pointer -> String in
            pointer.withMemoryRebound(
                to: CChar.self,
                capacity: MemoryLayout.size(ofValue: machineField)
            ) { reboundPointer in
                String(cString: reboundPointer)
            }
        }

        return machine.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
