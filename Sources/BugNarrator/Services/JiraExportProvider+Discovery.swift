import Foundation

extension JiraExportProvider {
    func validate(configuration: JiraExportConfiguration) async throws {
        guard configuration.isComplete else {
            throw AppError.exportConfigurationMissing(
                "Jira export requires a base URL, email, API token, project key, and issue type."
            )
        }

        let issueTypes = try await fetchIssueTypes(
            for: configuration.projectKey,
            projectID: configuration.projectID,
            configuration: JiraConnectionConfiguration(
                baseURL: configuration.baseURL,
                email: configuration.email,
                apiToken: configuration.apiToken
            )
        )

        guard let issueType = issueTypes.first(where: {
            $0.id == configuration.issueTypeID
                || $0.name.compare(configuration.issueTypeName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) else {
            throw AppError.exportFailure(
                "Jira project \(configuration.projectKey) does not expose issue type \(configuration.issueTypeName)."
            )
        }

        let requiredFields = try await fetchRequiredCreateFields(
            for: configuration.projectKey,
            issueTypeID: issueType.id,
            configuration: JiraConnectionConfiguration(
                baseURL: configuration.baseURL,
                email: configuration.email,
                apiToken: configuration.apiToken
            )
        )

        let unsupportedRequiredFields = requiredFields.filter {
            !$0.isSystemFieldSupportedByBugNarrator
        }

        if !unsupportedRequiredFields.isEmpty {
            let fieldList = unsupportedRequiredFields.map(\.displayName).joined(separator: ", ")
            throw AppError.exportFailure(
                "Jira requires additional fields before BugNarrator can create issues in \(configuration.projectKey): \(fieldList)."
            )
        }
    }

    func fetchProjects(
        configuration: JiraConnectionConfiguration
    ) async throws -> [JiraProjectOption] {
        guard configuration.isComplete else {
            throw AppError.exportConfigurationMissing(
                "Jira project discovery requires a base URL, email, and API token."
            )
        }

        var startAt = 0
        var projects: [JiraProjectOption] = []

        while true {
            let request = try makeProjectSearchRequest(configuration: configuration, startAt: startAt)
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw AppError.exportFailure("Jira returned an invalid response.")
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                throw mapJiraError(
                    statusCode: httpResponse.statusCode,
                    data: data,
                    configuration: JiraExportConfiguration(
                        baseURL: configuration.baseURL,
                        email: configuration.email,
                        apiToken: configuration.apiToken,
                        projectKey: "",
                        issueType: ""
                    )
                )
            }

            let payload = try decodeJiraPayload(
                JiraCreateMetadataProjectsResponse.self,
                from: data,
                description: "project metadata"
            )
            projects.append(
                contentsOf: payload.projects.compactMap(\.option)
            )

            let nextStartAt = startAt + (payload.maxResults ?? payload.projects.count)
            if payload.projects.isEmpty || nextStartAt <= startAt || nextStartAt >= payload.total {
                break
            }

            startAt = nextStartAt
        }

        return projects.sorted {
            if $0.key.caseInsensitiveCompare($1.key) == .orderedSame {
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }

            return $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending
        }
    }

    func fetchIssueTypes(
        for projectKey: String,
        projectID: String? = nil,
        configuration: JiraConnectionConfiguration
    ) async throws -> [JiraIssueTypeOption] {
        guard configuration.isComplete, !projectKey.isEmpty else {
            throw AppError.exportConfigurationMissing(
                "Jira issue type discovery requires a base URL, email, API token, and project key."
            )
        }

        let payload = try await fetchCreateIssueTypesPayload(
            for: projectKey,
            projectID: projectID,
            configuration: configuration
        )
        var seenNames = Set<String>()
        return payload.issueTypes.compactMap { issueType in
            guard let option = issueType.option else {
                return nil
            }

            let key = option.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard seenNames.insert(key).inserted else {
                return nil
            }

            return option
        }
    }

    private func makeProjectSearchRequest(
        configuration: JiraConnectionConfiguration,
        startAt: Int
    ) throws -> URLRequest {
        let url = try jiraRequestURL(
            baseURL: configuration.baseURL,
            path: "rest/api/3/project/search",
            queryItems: [
                .init(name: "startAt", value: "\(startAt)"),
                .init(name: "maxResults", value: "50")
            ]
        )

        return authenticatedRequest(
            url: url,
            httpMethod: "GET",
            email: configuration.email,
            apiToken: configuration.apiToken,
            includesJSONContentType: false
        )
    }

    private func makeProjectIssueTypesRequest(
        configuration: JiraConnectionConfiguration,
        projectKey: String,
        projectID: String?
    ) throws -> URLRequest {
        let url: URL
        if let normalizedProjectID = projectID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            url = try jiraRequestURL(
                baseURL: configuration.baseURL,
                path: "rest/api/3/issuetype/project",
                queryItems: [.init(name: "projectId", value: normalizedProjectID)]
            )
        } else {
            url = configuration.baseURL.appending(path: "rest/api/3/project/\(projectKey)")
        }

        return authenticatedRequest(
            url: url,
            httpMethod: "GET",
            email: configuration.email,
            apiToken: configuration.apiToken,
            includesJSONContentType: false
        )
    }

    private func makeCreateFieldMetadataRequest(
        configuration: JiraConnectionConfiguration,
        projectKey: String,
        issueTypeID: String
    ) throws -> URLRequest {
        let url = try jiraRequestURL(
            baseURL: configuration.baseURL,
            path: "rest/api/3/issue/createmeta/\(projectKey)/issuetypes/\(issueTypeID)",
            queryItems: [
                .init(name: "startAt", value: "0"),
                .init(name: "maxResults", value: "100")
            ]
        )

        return authenticatedRequest(
            url: url,
            httpMethod: "GET",
            email: configuration.email,
            apiToken: configuration.apiToken,
            includesJSONContentType: false
        )
    }

    private func fetchCreateIssueTypesPayload(
        for projectKey: String,
        projectID: String?,
        configuration: JiraConnectionConfiguration
    ) async throws -> JiraCreateMetaIssueTypesResponse {
        let request = try makeProjectIssueTypesRequest(
            configuration: configuration,
            projectKey: projectKey,
            projectID: projectID
        )
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.exportFailure("Jira returned an invalid response.")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw mapJiraError(
                statusCode: httpResponse.statusCode,
                data: data,
                configuration: JiraExportConfiguration(
                    baseURL: configuration.baseURL,
                    email: configuration.email,
                    apiToken: configuration.apiToken,
                    projectKey: projectKey,
                    issueType: ""
                )
            )
        }

        return try decodeJiraPayload(
            JiraCreateMetaIssueTypesResponse.self,
            from: data,
            description: "issue type metadata"
        )
    }

    private func fetchRequiredCreateFields(
        for projectKey: String,
        issueTypeID: String,
        configuration: JiraConnectionConfiguration
    ) async throws -> [JiraCreateFieldMetadata] {
        let request = try makeCreateFieldMetadataRequest(
            configuration: configuration,
            projectKey: projectKey,
            issueTypeID: issueTypeID
        )
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.exportFailure("Jira returned an invalid response.")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw mapJiraError(
                statusCode: httpResponse.statusCode,
                data: data,
                configuration: JiraExportConfiguration(
                    baseURL: configuration.baseURL,
                    email: configuration.email,
                    apiToken: configuration.apiToken,
                    projectKey: projectKey,
                    issueType: issueTypeID
                )
            )
        }

        let payload = try decodeJiraPayload(
            JiraCreateFieldMetadataResponse.self,
            from: data,
            description: "field metadata"
        )
        return payload.fields.filter(\.required)
    }
}

struct JiraCreateMetadataProjectsResponse: Decodable {
    let projects: [JiraProjectSummary]
    let maxResults: Int?
    let total: Int

    private enum CodingKeys: String, CodingKey {
        case projects
        case values
        case maxResults
        case total
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        projects = try container.decodeIfPresent([JiraProjectSummary].self, forKey: .projects)
            ?? container.decodeIfPresent([JiraProjectSummary].self, forKey: .values)
            ?? []
        maxResults = try container.decodeIfPresent(Int.self, forKey: .maxResults)
        total = try container.decodeIfPresent(Int.self, forKey: .total) ?? projects.count
    }
}

struct JiraProjectSummary: Decodable {
    let id: String?
    let key: String?
    let name: String?

    var option: JiraProjectOption? {
        guard let normalizedKey = key?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else {
            return nil
        }

        let normalizedName = name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? normalizedKey
        return JiraProjectOption(projectID: id, key: normalizedKey, name: normalizedName)
    }
}

struct JiraCreateMetaIssueTypesResponse: Decodable {
    let issueTypes: [JiraProjectIssueType]

    private enum CodingKeys: String, CodingKey {
        case issueTypes
        case values
    }

    init(from decoder: any Decoder) throws {
        if let issueTypes = try? [JiraProjectIssueType](from: decoder) {
            self.issueTypes = issueTypes
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        issueTypes = try container.decodeIfPresent([JiraProjectIssueType].self, forKey: .issueTypes)
            ?? container.decodeIfPresent([JiraProjectIssueType].self, forKey: .values)
            ?? []
    }
}

struct JiraProjectIssueType: Decodable {
    let id: String?
    let name: String?

    var option: JiraIssueTypeOption? {
        guard let normalizedID = id?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
              let normalizedName = name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else {
            return nil
        }

        return JiraIssueTypeOption(id: normalizedID, name: normalizedName)
    }
}

struct JiraCreateFieldMetadataResponse: Decodable {
    let fields: [JiraCreateFieldMetadata]

    private enum CodingKeys: String, CodingKey {
        case fields
        case values
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fields = try container.decodeIfPresent([JiraCreateFieldMetadata].self, forKey: .fields)
            ?? container.decodeIfPresent([JiraCreateFieldMetadata].self, forKey: .values)
            ?? []
    }
}

struct JiraCreateFieldMetadata: Decodable {
    let fieldID: String?
    let key: String?
    let name: String?
    let required: Bool

    enum CodingKeys: String, CodingKey {
        case fieldID = "fieldId"
        case key
        case name
        case required
    }

    var isSystemFieldSupportedByBugNarrator: Bool {
        switch key {
        case "project", "summary", "issuetype", "description":
            return true
        default:
            return false
        }
    }

    var displayName: String {
        let normalizedName = name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let normalizedFieldID = fieldID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        return normalizedName ?? normalizedFieldID ?? key ?? "Unknown field"
    }
}
