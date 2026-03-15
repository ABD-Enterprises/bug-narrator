import Foundation

enum BugNarratorLinks {
    static let repository = URL(string: "https://github.com/deffenda/bugnarrator")!
    static let documentation = URL(string: "https://github.com/deffenda/bugnarrator/blob/main/docs/UserGuide.md")!
    static let issues = URL(string: "https://github.com/deffenda/bugnarrator/issues/new")!
    static let releases = URL(string: "https://github.com/deffenda/bugnarrator/releases")!
    static let supportDevelopment = URL(string: "https://www.paypal.com/donate/?hosted_button_id=FWFQ6KCZBWWH8")!
    static let microphonePrivacySettings = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
    static let screenRecordingPrivacySettings = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
    static let securityPrivacySettings = URL(fileURLWithPath: "/System/Library/PreferencePanes/Security.prefPane")
    static let systemSettingsApp = URL(fileURLWithPath: "/System/Applications/System Settings.app")
}
