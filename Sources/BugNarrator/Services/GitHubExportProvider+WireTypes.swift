import Foundation

struct GitHubIssueRequest: Encodable {
    let title: String
    let body: String
    let labels: [String]?
}

struct GitHubIssueResponse: Decodable {
    let number: Int
    let htmlURL: URL?

    enum CodingKeys: String, CodingKey {
        case number
        case htmlURL = "html_url"
    }
}

struct GitHubRepositoryValidationResponse: Decodable {
    let nodeID: String?
    let name: String?
    let owner: GitHubRepositoryOwner?
    let hasIssues: Bool
    let permissions: GitHubRepositoryPermissions?

    enum CodingKeys: String, CodingKey {
        case nodeID = "node_id"
        case name
        case owner
        case hasIssues = "has_issues"
        case permissions
    }
}

struct GitHubRepositoryListItem: Decodable {
    let nodeID: String?
    let name: String
    let description: String?
    let hasIssues: Bool
    let permissions: GitHubRepositoryPermissions?
    let owner: GitHubRepositoryOwner

    enum CodingKeys: String, CodingKey {
        case nodeID = "node_id"
        case name
        case description
        case hasIssues = "has_issues"
        case permissions
        case owner
    }
}

struct GitHubRepositoryOwner: Decodable {
    let login: String
}

struct GitHubRepositoryPermissions: Decodable {
    let admin: Bool?
    let maintain: Bool?
    let push: Bool?
    let triage: Bool?

    var canCreateIssues: Bool {
        admin == true || maintain == true || push == true || triage == true
    }
}

struct GitHubSearchResponse: Decodable {
    let items: [GitHubSearchItem]
}

struct GitHubSearchItem: Decodable {
    let number: Int
    let title: String
    let body: String?
    let htmlURL: URL?

    enum CodingKeys: String, CodingKey {
        case number
        case title
        case body
        case htmlURL = "html_url"
    }
}

struct GitHubErrorResponse: Decodable {
    let message: String
}
