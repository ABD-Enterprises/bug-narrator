import Foundation

struct DiagnosticsEventName: RawRepresentable, ExpressibleByStringLiteral, Equatable, Hashable {
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(stringLiteral value: String) {
        self.rawValue = value
    }
}
