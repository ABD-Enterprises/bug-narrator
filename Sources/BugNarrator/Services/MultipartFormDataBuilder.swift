import Foundation

struct MultipartFormDataBuilder {
    let boundary: String
    private var body = Data()

    init(boundary: String) {
        self.boundary = boundary
    }

    mutating func appendField(named name: String, value: String) {
        appendLine("--\(boundary)")
        appendLine("Content-Disposition: form-data; name=\"\(name)\"")
        appendLine("")
        appendLine(value)
    }

    mutating func appendFile(named name: String, fileName: String, mimeType: String, data: Data) {
        appendLine("--\(boundary)")
        appendLine("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(fileName)\"")
        appendLine("Content-Type: \(mimeType)")
        appendLine("")
        body.append(data)
        appendLine("")
    }

    mutating func finalizedBody() -> Data {
        var finalizedBody = body
        finalizedBody.append(Data("--\(boundary)--\r\n".utf8))
        return finalizedBody
    }

    private mutating func appendLine(_ value: String) {
        body.append(Data("\(value)\r\n".utf8))
    }
}
