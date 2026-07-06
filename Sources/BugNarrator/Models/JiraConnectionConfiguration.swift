import Foundation

struct JiraConnectionConfiguration: Equatable {
    let baseURL: URL
    let email: String
    let apiToken: String

    var isComplete: Bool {
        !email.isEmpty && !apiToken.isEmpty
    }
}
