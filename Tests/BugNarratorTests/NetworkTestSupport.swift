import Foundation
#if canImport(Darwin)
import Darwin
#endif

final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let requestHandler = Self.requestHandler else {
            fatalError("MockURLProtocol.requestHandler was not set.")
        }

        do {
            let (response, data) = try requestHandler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

/// A local HTTP server that answers every request with a redirect.
///
/// The redirect has to come from a real server. A mock protocol that answers
/// with a 3xx is surfaced as the final response: the loading system never
/// asks the session's delegate whether such a redirect may be followed, so a
/// test built on one cannot tell whether the policy is wired into the
/// session at all.
final class RedirectServer: @unchecked Sendable {
    private let descriptor: Int32
    private let queue = DispatchQueue(label: "BugNarrator.RedirectServer")
    private let lock = NSLock()
    private var answered = 0

    /// The port the server listens on.
    let port: UInt16

    /// Where the server sends the request that answers it.
    let location: String

    init(location: String) throws {
        // The socket is set up through local variables: a closure that reads
        // `self` before every stored property is initialised is not allowed,
        // and the port is only known once the socket is bound.
        let opened = socket(AF_INET, SOCK_STREAM, 0)
        guard opened >= 0 else {
            throw NSError(
                domain: "RedirectServer",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "could not create a socket"]
            )
        }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(opened, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, listen(opened, 8) == 0 else {
            close(opened)
            throw NSError(
                domain: "RedirectServer",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "could not listen on a socket"]
            )
        }

        var listening = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &listening) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(opened, $0, &length)
            }
        }
        guard named == 0 else {
            close(opened)
            throw NSError(
                domain: "RedirectServer",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "could not read the port"]
            )
        }

        descriptor = opened
        self.location = location
        port = UInt16(bigEndian: listening.sin_port)
    }

    deinit {
        close(descriptor)
    }

    /// How many requests the server answered.
    var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return answered
    }

    /// Answers requests with a redirect to `location` until the test ends.
    func serve() {
        queue.async { [descriptor, location] in
            while true {
                let client = accept(descriptor, nil, nil)
                guard client >= 0 else { return }
                defer { close(client) }

                var buffer = [UInt8](repeating: 0, count: 4096)
                _ = buffer.withUnsafeMutableBytes { pointer in
                    read(client, pointer.baseAddress, pointer.count)
                }

                self.lock.lock()
                self.answered += 1
                self.lock.unlock()

                let response = "HTTP/1.1 307 Temporary Redirect\r\n"
                    + "Location: \(location)\r\n"
                    + "Content-Length: 0\r\n"
                    + "Connection: close\r\n\r\n"
                response.withCString { pointer in
                    _ = write(client, pointer, strlen(pointer))
                }
            }
        }
    }
}

func makeMockURLSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: configuration)
}
