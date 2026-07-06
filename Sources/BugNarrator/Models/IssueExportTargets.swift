import Foundation

struct GitHubIssueExportTarget: Codable, Equatable {
    var repositoryID: String?
    var owner: String
    var repository: String
    var labels: [String]

    init(
        repositoryID: String? = nil,
        owner: String = "",
        repository: String = "",
        labels: [String] = []
    ) {
        self.repositoryID = repositoryID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.owner = owner.trimmingCharacters(in: .whitespacesAndNewlines)
        self.repository = repository.trimmingCharacters(in: .whitespacesAndNewlines)
        self.labels = labels
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var isComplete: Bool {
        !owner.isEmpty && !repository.isEmpty
    }

    var displayLabel: String {
        isComplete ? "\(owner)/\(repository)" : "Choose a GitHub repository"
    }
}

struct JiraIssueExportTarget: Codable, Equatable {
    var projectID: String?
    var projectKey: String
    var projectName: String?
    var issueTypeID: String
    var issueTypeName: String

    init(
        projectID: String? = nil,
        projectKey: String = "",
        projectName: String? = nil,
        issueTypeID: String = "",
        issueTypeName: String = ""
    ) {
        self.projectID = projectID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.projectKey = projectKey.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        self.projectName = projectName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.issueTypeID = issueTypeID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.issueTypeName = issueTypeName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isComplete: Bool {
        !projectKey.isEmpty && (!issueTypeID.isEmpty || !issueTypeName.isEmpty)
    }

    var projectDisplayLabel: String {
        guard let projectName else {
            return projectKey.isEmpty ? "Choose a Jira project" : projectKey
        }

        return "\(projectKey) - \(projectName)"
    }
}

struct IssueExtractionResult: Codable, Equatable {
    let generatedAt: Date
    var summary: String
    var guidanceNote: String
    var issues: [ExtractedIssue]

    init(
        generatedAt: Date = Date(),
        summary: String,
        guidanceNote: String = "Extracted issues are draft suggestions and should be reviewed before export.",
        issues: [ExtractedIssue]
    ) {
        self.generatedAt = generatedAt
        self.summary = summary
        self.guidanceNote = guidanceNote
        self.issues = issues
    }

    var selectedIssues: [ExtractedIssue] {
        issues.filter(\.isSelectedForExport)
    }
}
struct ExportResult: Identifiable, Equatable {
    let id: UUID
    let sourceIssueID: UUID
    let destination: ExportDestination
    let remoteIdentifier: String
    let remoteURL: URL?
    let exportedAt: Date

    init(
        id: UUID = UUID(),
        sourceIssueID: UUID,
        destination: ExportDestination,
        remoteIdentifier: String,
        remoteURL: URL?,
        exportedAt: Date = Date()
    ) {
        self.id = id
        self.sourceIssueID = sourceIssueID
        self.destination = destination
        self.remoteIdentifier = remoteIdentifier
        self.remoteURL = remoteURL
        self.exportedAt = exportedAt
    }
}

