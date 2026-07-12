import Foundation
import Network

enum ProxyHeaderPolicy {
    static func forwardsRequest(_ name: String) -> Bool {
        ![
            "host", "content-length", "connection", "authorization", "api-key",
            "accept-encoding"
        ].contains(name.lowercased())
    }

    static func forwardsResponse(_ name: String) -> Bool {
        ![
            "content-length", "transfer-encoding", "connection", "content-encoding"
        ].contains(name.lowercased())
    }
}

struct APIProxyRoute {
    let alias: String
    let profileName: String
    let baseURL: String
    let model: String
    let authenticationMode: AuthenticationMode
    let authenticationHeader: String
    let apiKey: String?
}

final class APIProxyServer {
    private let queue = DispatchQueue(label: "com.zps.codex-api-desktop.plus.router")
    private var listener: NWListener?
    private var routes: [String: APIProxyRoute] = [:]
    private var ready = false
    private var lastFailure: Error?

    func start(port: UInt16 = CodexConfigService.routerPort) throws {
        var startupError: Error?
        queue.sync {
            guard listener == nil else { return }
            guard let networkPort = NWEndpoint.Port(rawValue: port) else {
                startupError = APIProxyError.invalidPort
                return
            }
            do {
                let parameters = NWParameters.tcp
                parameters.requiredLocalEndpoint = .hostPort(
                    host: .ipv4(.loopback),
                    port: networkPort
                )
                let newListener = try NWListener(using: parameters)
                newListener.stateUpdateHandler = { [weak self, weak newListener] state in
                    guard let self, let newListener else { return }
                    switch state {
                    case .ready:
                        ready = true
                        lastFailure = nil
                    case .failed(let error):
                        ready = false
                        lastFailure = error
                        newListener.cancel()
                        if listener === newListener { listener = nil }
                    case .cancelled:
                        ready = false
                        if listener === newListener { listener = nil }
                    default:
                        break
                    }
                }
                newListener.newConnectionHandler = { [weak self] connection in
                    guard let self else { return }
                    connection.start(queue: self.queue)
                    self.receiveRequest(from: connection, accumulated: Data())
                }
                ready = false
                lastFailure = nil
                listener = newListener
                newListener.start(queue: queue)
            } catch {
                startupError = error
            }
        }
        if let startupError { throw startupError }
    }

    func ensureReady(
        port: UInt16 = CodexConfigService.routerPort,
        timeout: TimeInterval = 2
    ) throws {
        try start(port: port)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let state = queue.sync { (ready, lastFailure) }
            if state.0 { return }
            if let error = state.1 {
                throw APIProxyError.startupFailed(error.localizedDescription)
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        queue.sync {
            let stalledListener = listener
            listener = nil
            ready = false
            stalledListener?.cancel()
        }
        throw APIProxyError.startupTimedOut
    }

    var isReady: Bool {
        queue.sync { ready }
    }

    func stop() {
        queue.sync {
            let activeListener = listener
            listener = nil
            ready = false
            lastFailure = nil
            activeListener?.cancel()
        }
    }

    func update(routes: [APIProxyRoute]) {
        queue.async { self.routes = Dictionary(uniqueKeysWithValues: routes.map { ($0.alias, $0) }) }
    }

    private func receiveRequest(from connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1_048_576) { [weak self] data, _, complete, error in
            guard let self else { return }
            var buffer = accumulated
            if let data { buffer.append(data) }
            if let request = HTTPProxyRequest.parse(buffer) {
                self.forward(request, on: connection)
            } else if complete || error != nil || buffer.count > 16_777_216 {
                self.sendError(400, "无法读取 Codex API 请求", on: connection)
            } else {
                self.receiveRequest(from: connection, accumulated: buffer)
            }
        }
    }

    private func forward(_ incoming: HTTPProxyRequest, on connection: NWConnection) {
        guard incoming.method == "POST" else {
            sendError(405, "Plus 本机路由仅接受 Responses API POST 请求", on: connection)
            return
        }
        guard incoming.path.split(separator: "?", maxSplits: 1).first == "/v1/responses" else {
            sendError(404, "Plus 本机路由仅提供 /v1/responses", on: connection)
            return
        }
        guard var object = try? JSONSerialization.jsonObject(with: incoming.body) as? [String: Any],
              let alias = object["model"] as? String,
              let route = routes[alias] else {
            sendError(400, "所选模型未对应到 API Plus 配置，请重新保存配置后再试", on: connection)
            return
        }
        object["model"] = route.model
        guard let body = try? JSONSerialization.data(withJSONObject: object),
              let url = upstreamURL(baseURL: route.baseURL, requestPath: incoming.path) else {
            sendError(400, "配置“\(route.profileName)”的 Base URL 无效", on: connection)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = incoming.method
        request.httpBody = body
        for (name, value) in incoming.headers {
            guard ProxyHeaderPolicy.forwardsRequest(name) else { continue }
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        switch route.authenticationMode {
        case .bearer:
            guard let key = route.apiKey else {
                sendError(401, "配置“\(route.profileName)”尚未保存 API Key", on: connection)
                return
            }
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        case .customHeader:
            guard let key = route.apiKey else {
                sendError(401, "配置“\(route.profileName)”尚未保存 API Key", on: connection)
                return
            }
            request.setValue(key, forHTTPHeaderField: route.authenticationHeader)
        case .none:
            break
        }

        ProxyURLSession(request: request, connection: connection).start()
    }

    private func upstreamURL(baseURL: String, requestPath: String) -> URL? {
        let root = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let suffix = requestPath.hasPrefix("/v1/") ? String(requestPath.dropFirst(3)) : requestPath
        return URL(string: root + (suffix.hasPrefix("/") ? suffix : "/" + suffix))
    }

    private func sendError(_ status: Int, _ message: String, on connection: NWConnection) {
        let payload = (try? JSONSerialization.data(withJSONObject: ["error": ["message": message]])) ?? Data()
        let reason = status == 401 ? "Unauthorized" : status == 405 ? "Method Not Allowed" : "Bad Request"
        let header = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: \(payload.count)\r\nConnection: close\r\n\r\n"
        var response = Data(header.utf8)
        response.append(payload)
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }
}

struct HTTPProxyRequest {
    private static let maximumBodySize = 16_777_216
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data

    static func parse(_ data: Data) -> HTTPProxyRequest? {
        let marker = Data("\r\n\r\n".utf8)
        guard let boundary = data.range(of: marker),
              let headerText = String(data: data[..<boundary.lowerBound], encoding: .utf8) else { return nil }
        let lines = headerText.components(separatedBy: "\r\n")
        let requestLine = lines.first?.split(separator: " ") ?? []
        guard requestLine.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }
        let bodyStart = boundary.upperBound
        let body: Data
        if headers.contains(where: {
            $0.key.caseInsensitiveCompare("Transfer-Encoding") == .orderedSame
                && $0.value.lowercased().contains("chunked")
        }) {
            guard let decoded = decodeChunked(data.subdata(in: bodyStart..<data.count)) else { return nil }
            body = decoded
        } else {
            guard let expectedLength = headers.first(where: {
                $0.key.caseInsensitiveCompare("Content-Length") == .orderedSame
            }).map({ Int($0.value) }), let expectedLength,
                  expectedLength >= 0, expectedLength <= maximumBodySize,
                  bodyStart <= data.count, expectedLength <= data.count - bodyStart else { return nil }
            body = data.subdata(in: bodyStart..<(bodyStart + expectedLength))
        }
        return HTTPProxyRequest(
            method: String(requestLine[0]),
            path: String(requestLine[1]),
            headers: headers,
            body: body
        )
    }

    private static func decodeChunked(_ data: Data) -> Data? {
        let separator = Data("\r\n".utf8)
        var cursor = data.startIndex
        var decoded = Data()
        while cursor < data.endIndex {
            guard let lineEnd = data[cursor...].range(of: separator) else { return nil }
            guard let sizeLine = String(data: data[cursor..<lineEnd.lowerBound], encoding: .utf8) else {
                return nil
            }
            let sizeText = sizeLine.split(separator: ";", maxSplits: 1).first ?? ""
            guard let size = Int(sizeText.trimmingCharacters(in: .whitespaces), radix: 16), size >= 0 else {
                return nil
            }
            cursor = lineEnd.upperBound
            if size == 0 {
                guard cursor <= data.count, data.count - cursor >= 2 else { return nil }
                return decoded
            }
            guard size <= maximumBodySize - decoded.count,
                  cursor <= data.count, data.count - cursor >= 2,
                  size <= data.count - cursor - 2 else { return nil }
            decoded.append(data[cursor..<(cursor + size)])
            cursor += size
            guard data[cursor..<(cursor + 2)] == separator else { return nil }
            cursor += 2
        }
        return nil
    }
}

private final class ProxyURLSession: NSObject, URLSessionDataDelegate {
    private static let maximumQueuedBytes = 8 * 1_024 * 1_024
    private let request: URLRequest
    private let connection: NWConnection
    private var session: URLSession?
    private var completed = false
    private var upstreamResponse: HTTPURLResponse?
    private var errorBody = Data()
    private let writeLock = NSLock()
    private var pendingWrites: [(data: Data, final: Bool)] = []
    private var writeInFlight = false
    private var queuedBytes = 0
    private var overflowed = false

    init(request: URLRequest, connection: NWConnection) {
        self.request = request
        self.connection = connection
    }

    func start() {
        let operationQueue = OperationQueue()
        operationQueue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: operationQueue)
        self.session = session
        session.dataTask(with: request).resume()
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let response = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            return
        }
        upstreamResponse = response
        if response.statusCode >= 300 {
            completionHandler(.allow)
            return
        }
        var header = "HTTP/1.1 \(response.statusCode) OK\r\n"
        for (key, value) in response.allHeaderFields {
            let name = String(describing: key)
            guard ProxyHeaderPolicy.forwardsResponse(name) else { continue }
            header += "\(name): \(value)\r\n"
        }
        header += "Transfer-Encoding: chunked\r\nConnection: close\r\n\r\n"
        enqueue(Data(header.utf8))
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if let status = upstreamResponse?.statusCode, status >= 300 {
            if errorBody.count < 1_048_576 { errorBody.append(data) }
            return
        }
        var chunk = Data(String(data.count, radix: 16).utf8)
        chunk.append(Data("\r\n".utf8))
        chunk.append(data)
        chunk.append(Data("\r\n".utf8))
        enqueue(chunk)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard !completed else { return }
        completed = true
        if let error {
            sendFailure(status: 502, message: "API Plus 无法连接上游服务：\(error.localizedDescription)")
        } else if overflowed {
            connection.cancel()
        } else if let response = upstreamResponse, response.statusCode >= 300 {
            let upstreamMessage = Self.upstreamMessage(from: errorBody)
            sendFailure(
                status: response.statusCode,
                message: "上游 API 返回 HTTP \(response.statusCode)\(upstreamMessage.map { "：\($0)" } ?? "")"
            )
        } else {
            enqueue(Data("0\r\n\r\n".utf8), final: true)
        }
    }

    private func sendFailure(status: Int, message: String) {
        let payload = (try? JSONSerialization.data(withJSONObject: ["error": ["message": message]])) ?? Data()
        let reason = HTTPURLResponse.localizedString(forStatusCode: status)
        let header = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: \(payload.count)\r\nConnection: close\r\n\r\n"
        var response = Data(header.utf8)
        response.append(payload)
        enqueue(response, final: true)
    }

    private func enqueue(_ data: Data, final: Bool = false) {
        writeLock.lock()
        guard !overflowed, data.count <= Self.maximumQueuedBytes - queuedBytes else {
            overflowed = true
            writeLock.unlock()
            session?.invalidateAndCancel()
            connection.cancel()
            return
        }
        pendingWrites.append((data, final))
        queuedBytes += data.count
        let shouldStart = !writeInFlight
        if shouldStart { writeInFlight = true }
        writeLock.unlock()
        if shouldStart { sendNextWrite() }
    }

    private func sendNextWrite() {
        writeLock.lock()
        guard let next = pendingWrites.first else {
            writeInFlight = false
            writeLock.unlock()
            return
        }
        writeLock.unlock()

        connection.send(content: next.data, completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            self.writeLock.lock()
            if !self.pendingWrites.isEmpty {
                self.queuedBytes -= self.pendingWrites.removeFirst().data.count
            }
            self.writeLock.unlock()
            if error != nil || next.final {
                self.connection.cancel()
                self.session?.finishTasksAndInvalidate()
                return
            }
            self.sendNextWrite()
        })
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard Self.sameOrigin(task.originalRequest?.url, request.url) else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }

    private static func sameOrigin(_ lhs: URL?, _ rhs: URL?) -> Bool {
        guard let lhs, let rhs else { return false }
        return lhs.scheme?.lowercased() == rhs.scheme?.lowercased()
            && lhs.host?.lowercased() == rhs.host?.lowercased()
            && (lhs.port ?? (lhs.scheme == "https" ? 443 : 80)) == (rhs.port ?? (rhs.scheme == "https" ? 443 : 80))
    }

    private static func upstreamMessage(from data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = object["error"] as? [String: Any], let message = error["message"] as? String {
                return message.prefix(300).description
            }
            if let message = object["message"] as? String { return message.prefix(300).description }
            if let detail = object["detail"] as? String { return detail.prefix(300).description }
        }
        return String(data: data.prefix(300), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum APIProxyError: LocalizedError {
    case invalidPort
    case startupFailed(String)
    case startupTimedOut

    var errorDescription: String? {
        switch self {
        case .invalidPort:
            "API Plus 本机路由端口无效"
        case .startupFailed(let detail):
            "API Plus 本机路由启动失败：\(detail)"
        case .startupTimedOut:
            "API Plus 本机路由启动超时；可能已有另一份管理器占用端口"
        }
    }
}
