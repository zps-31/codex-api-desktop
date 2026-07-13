import Foundation

final class BoundedHTTPClient: NSObject, URLSessionDataDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    enum ClientError: Error {
        case invalidLimit, responseTooLarge, crossOriginRedirect, missingResponse
    }

    private let limit: Int
    private var data = Data()
    private var response: URLResponse?
    private var continuation: CheckedContinuation<(Data, URLResponse), Error>?
    private var session: URLSession?
    private var finished = false

    private init(limit: Int) { self.limit = limit }

    static func data(for request: URLRequest, limit: Int = 4 * 1_024 * 1_024) async throws -> (Data, URLResponse) {
        guard limit > 0 else { throw ClientError.invalidLimit }
        let client = BoundedHTTPClient(limit: limit)
        return try await client.run(request)
    }

    private func run(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let queue = OperationQueue()
            queue.maxConcurrentOperationCount = 1
            let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: queue)
            self.session = session
            session.dataTask(with: request).resume()
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        self.response = response
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        guard data.count <= limit, chunk.count <= limit - data.count else {
            finish(.failure(ClientError.responseTooLarge))
            session.invalidateAndCancel()
            return
        }
        data.append(chunk)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)); return }
        guard let response else { finish(.failure(ClientError.missingResponse)); return }
        finish(.success((data, response)))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        guard Self.sameOrigin(task.originalRequest?.url, request.url) else {
            finish(.failure(ClientError.crossOriginRedirect))
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }

    private func finish(_ result: Result<(Data, URLResponse), Error>) {
        guard !finished else { return }
        finished = true
        continuation?.resume(with: result)
        continuation = nil
        session?.finishTasksAndInvalidate()
    }

    private static func sameOrigin(_ lhs: URL?, _ rhs: URL?) -> Bool {
        guard let lhs, let rhs else { return false }
        return lhs.scheme?.lowercased() == rhs.scheme?.lowercased()
            && lhs.host?.lowercased() == rhs.host?.lowercased()
            && (lhs.port ?? (lhs.scheme == "https" ? 443 : 80)) == (rhs.port ?? (rhs.scheme == "https" ? 443 : 80))
    }
}
