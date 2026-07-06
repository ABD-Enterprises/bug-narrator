import Foundation

enum OpenAIEndpointBuilder {
    static func endpoint(for path: String, baseURL: URL) -> URL {
        var pathComponents = path.split(separator: "/").map(String.init)

        if let firstComponent = pathComponents.first,
           baseURL.lastPathComponent.caseInsensitiveCompare(firstComponent) == .orderedSame {
            pathComponents.removeFirst()
        }

        return pathComponents.reduce(baseURL) { url, component in
            url.appendingPathComponent(component)
        }
    }
}
