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
///
/// The server listens on the loopback address only, on a port the system
/// picks, and it answers until it is stopped.
final class RedirectServer: @unchecked Sendable {
    private let descriptor: Int32
    private let queue = DispatchQueue(label: "BugNarrator.RedirectServer")
    private let state = RedirectServerState()
    private let closeLock = NSLock()
    private var isClosed = false

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

        // The address may be reused: a socket that answered a connection and
        // was closed leaves the port in TIME_WAIT, and the next server the
        // system hands that port to would not be able to bind it.
        var reuse: Int32 = 1
        setsockopt(opened, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

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

        // The socket does not block. The loop checks whether the server has
        // been stopped between connections, so stopping it does not depend on
        // a connection arriving.
        let flags = fcntl(opened, F_GETFL, 0)
        _ = fcntl(opened, F_SETFL, flags | O_NONBLOCK)

        descriptor = opened
        self.location = location
        port = UInt16(bigEndian: listening.sin_port)
    }

    deinit {
        stop()
    }

    /// How many requests the server answered.
    var requestCount: Int {
        state.count
    }

    /// Answers requests with a redirect to `location` until the server is
    /// stopped.
    ///
    /// The loop does not retain the server: it owns the counter and the
    /// socket, and the server owns them in turn. A loop that retained the
    /// server would keep the socket open for the rest of the test run, and
    /// the port would go on answering after the test that opened it ended.
    func serve() {
        state.begin()
        queue.async { [descriptor, location, state] in
            while !state.isStopRequested {
                let client = accept(descriptor, nil, nil)
                guard client >= 0 else {
                    // No connection is waiting. The socket does not block, so
                    // this is not a failure.
                    Thread.sleep(forTimeInterval: 0.005)
                    continue
                }
                defer { close(client) }

                // A client that sends nothing must not hold the server: the
                // read is given a moment and the connection is dropped after.
                var timeout = timeval(tv_sec: 2, tv_usec: 0)
                setsockopt(
                    client,
                    SOL_SOCKET,
                    SO_RCVTIMEO,
                    &timeout,
                    socklen_t(MemoryLayout<timeval>.size)
                )

                var buffer = [UInt8](repeating: 0, count: 4096)
                _ = buffer.withUnsafeMutableBytes { pointer in
                    read(client, pointer.baseAddress, pointer.count)
                }

                state.record()

                let response = "HTTP/1.1 307 Temporary Redirect\r\n"
                    + "Location: \(location)\r\n"
                    + "Content-Length: 0\r\n"
                    + "Connection: close\r\n\r\n"
                response.withCString { pointer in
                    _ = write(client, pointer, strlen(pointer))
                }
            }
            state.markStopped()
        }
    }

    /// Stops the server and releases the socket.
    ///
    /// The socket is closed once the loop that answers on it has stopped, so
    /// the loop never accepts on a closed descriptor.
    func stop() {
        state.requestStop()
        let deadline = Date().addingTimeInterval(2)
        while !state.isStopped && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.005)
        }
        closeSocket()
    }

    private func closeSocket() {
        closeLock.lock()
        defer { closeLock.unlock() }
        guard !isClosed else { return }
        isClosed = true
        close(descriptor)
    }
}

/// What a `RedirectServer` has answered, and whether it should stop.
///
/// It is a separate object so that the serving loop does not have to retain
/// the server it belongs to.
private final class RedirectServerState: @unchecked Sendable {
    private let lock = NSLock()
    private var answered = 0
    private var stopRequested = false
    private var stopped = true

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return answered
    }

    var isStopRequested: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopRequested
    }

    var isStopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }

    func begin() {
        lock.lock()
        stopped = false
        lock.unlock()
    }

    func record() {
        lock.lock()
        answered += 1
        lock.unlock()
    }

    func requestStop() {
        lock.lock()
        stopRequested = true
        lock.unlock()
    }

    func markStopped() {
        lock.lock()
        stopped = true
        lock.unlock()
    }
}

/// Whether something is listening on `port` right now.
///
/// The server binds to the loopback address on a port the system picks, so
/// nothing outside the machine can reach it.
func acceptsConnections(on port: UInt16) -> Bool {
    let descriptor = socket(AF_INET, SOCK_STREAM, 0)
    defer { close(descriptor) }

    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = port.bigEndian
    address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
    let result = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    return result == 0
}

func makeMockURLSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: configuration)
}
