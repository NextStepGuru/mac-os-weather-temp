import Foundation

enum MockURLProtocol {
    typealias Handler = (URLRequest) throws -> (HTTPURLResponse, Data)

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handlers: [String: Handler] = [:]

    static func makeSession(handler: @escaping Handler) -> URLSession {
        let sessionID = UUID().uuidString
        lock.lock()
        handlers[sessionID] = handler
        lock.unlock()

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolSubclass.self]
        config.httpAdditionalHeaders = ["X-Mock-Session-ID": sessionID]
        return URLSession(configuration: config)
    }

    static func reset() {
        lock.lock()
        handlers = [:]
        lock.unlock()
    }

    private static func handler(for sessionID: String) -> Handler? {
        lock.lock()
        defer { lock.unlock() }
        return handlers[sessionID]
    }

    private final class URLProtocolSubclass: URLProtocol {
        override class func canInit(with request: URLRequest) -> Bool {
            request.value(forHTTPHeaderField: "X-Mock-Session-ID") != nil
        }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest {
            request
        }

        override func startLoading() {
            guard let sessionID = request.value(forHTTPHeaderField: "X-Mock-Session-ID") else {
                client?.urlProtocol(self, didFailWithError: URLError(.badURL))
                return
            }

            guard let handler = MockURLProtocol.handler(for: sessionID) else {
                client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
                return
            }

            do {
                let (response, data) = try handler(request)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }

        override func stopLoading() {}
    }
}

extension MockURLProtocol {
    static func jsonResponse(statusCode: Int = 200, body: String) -> (HTTPURLResponse, Data) {
        let url = URL(string: "https://example.com")!
        let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
        return (response, Data(body.utf8))
    }
}
