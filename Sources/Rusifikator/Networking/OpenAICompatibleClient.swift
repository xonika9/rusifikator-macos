import Foundation

struct OpenAICompatibleClient: Sendable {
    static let maximumResponseBytes = 4 * 1_024 * 1_024

    private let protocolClasses: [AnyClass]?

    init(protocolClasses: [AnyClass]? = nil) {
        self.protocolClasses = protocolClasses
    }

    func clean(
        text: String,
        baseURL: URL,
        model: String,
        apiKey: String,
        systemPrompt: String = FixedSystemPrompt.text
    ) async throws -> String {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw APIError.missingAPIKey
        }

        let endpoint = try Self.endpoint(for: baseURL)
        let payload = ChatCompletionRequest(
            model: model,
            messages: [
                .init(role: .system, content: systemPrompt),
                .init(role: .user, content: text)
            ],
            stream: false
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(payload)
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let transfer = StreamingRequest(
            maximumBytes: Self.maximumResponseBytes,
            allowedOrigin: Origin(url: endpoint)
        )

        let data: Data
        do {
            data = try await transfer.load(
                request,
                configuration: Self.makeConfiguration(
                    protocolClasses: protocolClasses
                )
            )
        } catch let error as APIError {
            throw error
        } catch is CancellationError {
            throw APIError.cancelled
        } catch let error as URLError {
            if error.code == .cancelled {
                throw APIError.cancelled
            }
            if error.code == .timedOut {
                throw APIError.timeout
            }
            throw APIError.transport
        } catch {
            throw APIError.transport
        }

        let response: ChatCompletionResponse
        do {
            response = try JSONDecoder().decode(
                ChatCompletionResponse.self,
                from: data
            )
        } catch {
            throw APIError.invalidResponse
        }

        guard let content = response.choices.first?.message.content else {
            throw APIError.emptyResponse
        }

        let normalized = Self.normalizeContent(content)
        guard !normalized.isEmpty else {
            throw APIError.emptyResponse
        }
        return normalized
    }

    func checkConnection(
        baseURL: URL,
        model: String,
        apiKey: String,
        systemPrompt: String = FixedSystemPrompt.text
    ) async throws {
        _ = try await clean(
            text: "Проверка.",
            baseURL: baseURL,
            model: model,
            apiKey: apiKey,
            systemPrompt: systemPrompt
        )
    }

    static func endpoint(for baseURL: URL) throws -> URL {
        guard var components = URLComponents(
            url: baseURL,
            resolvingAgainstBaseURL: false
        ),
        components.scheme?.lowercased() == "https",
        components.user == nil,
        components.password == nil,
        let host = components.host,
        !host.isEmpty,
        components.query == nil,
        components.fragment == nil
        else {
            throw APIError.invalidURL
        }

        let path = components.percentEncodedPath
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let acceptedPaths = [
            "",
            "v1",
            "chat/completions",
            "v1/chat/completions"
        ]
        guard acceptedPaths.contains(path) else {
            throw APIError.invalidURL
        }

        components.scheme = "https"
        components.percentEncodedPath = "/v1/chat/completions"
        guard let endpoint = components.url else {
            throw APIError.invalidURL
        }
        return endpoint
    }

    static func makeConfiguration(
        protocolClasses: [AnyClass]? = nil
    ) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 90
        configuration.waitsForConnectivity = false
        configuration.httpShouldSetCookies = false
        if let protocolClasses {
            configuration.protocolClasses = protocolClasses
        }
        return configuration
    }

    private static func normalizeContent(_ content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            return trimmed
        }

        let pairs: [(Character, Character)] = [
            ("\"", "\""),
            ("“", "”")
        ]
        guard let first = trimmed.first,
              let last = trimmed.last,
              pairs.contains(where: { $0 == (first, last) })
        else {
            return trimmed
        }

        return String(trimmed.dropFirst().dropLast())
    }
}

private struct Origin: Sendable, Equatable {
    let host: String
    let port: Int

    init(url: URL) {
        host = url.host?.lowercased() ?? ""
        port = url.port ?? 443
    }

    func permits(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https"
            && Origin(url: url) == self
    }
}

private final class StreamingRequest: NSObject, @unchecked Sendable {
    private let maximumBytes: Int
    private let allowedOrigin: Origin
    private let lock = NSLock()

    private var continuation: CheckedContinuation<Data, Error>?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var buffer = Data()
    private var isFinished = false
    private var cancellationRequested = false

    init(maximumBytes: Int, allowedOrigin: Origin) {
        self.maximumBytes = maximumBytes
        self.allowedOrigin = allowedOrigin
    }

    func load(
        _ request: URLRequest,
        configuration: URLSessionConfiguration
    ) async throws -> Data {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                if cancellationRequested {
                    lock.unlock()
                    continuation.resume(throwing: APIError.cancelled)
                    return
                }

                self.continuation = continuation
                let session = URLSession(
                    configuration: configuration,
                    delegate: self,
                    delegateQueue: nil
                )
                let task = session.dataTask(with: request)
                self.session = session
                self.task = task
                lock.unlock()

                task.resume()
            }
        } onCancel: {
            self.cancel()
        }
    }

    private func cancel() {
        lock.lock()
        cancellationRequested = true
        lock.unlock()
        finish(.failure(APIError.cancelled), cancelTask: true)
    }

    private func finish(
        _ result: Result<Data, Error>,
        cancelTask: Bool = false
    ) {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        isFinished = true
        let continuation = self.continuation
        self.continuation = nil
        let task = self.task
        let session = self.session
        self.task = nil
        self.session = nil
        lock.unlock()

        if cancelTask {
            task?.cancel()
            session?.invalidateAndCancel()
        } else {
            session?.finishTasksAndInvalidate()
        }
        continuation?.resume(with: result)
    }

    private static func error(for statusCode: Int) -> APIError? {
        switch statusCode {
        case 200..<300:
            nil
        case 401:
            .unauthorized
        case 403:
            .forbidden
        case 404:
            .notFound
        case 408:
            .timeout
        case 429:
            .rateLimited
        case 500..<600:
            .serverError
        default:
            .httpError(statusCode)
        }
    }
}

extension StreamingRequest: URLSessionDataDelegate {
    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let httpResponse = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            finish(.failure(APIError.invalidResponse), cancelTask: true)
            return
        }
        if (300..<400).contains(httpResponse.statusCode),
           let location = httpResponse.value(forHTTPHeaderField: "Location"),
           let redirectURL = URL(
               string: location,
               relativeTo: httpResponse.url
           )?.absoluteURL,
           !allowedOrigin.permits(redirectURL) {
            completionHandler(.cancel)
            finish(.failure(APIError.unsafeRedirect), cancelTask: true)
            return
        }
        if let error = Self.error(for: httpResponse.statusCode) {
            completionHandler(.cancel)
            finish(.failure(error), cancelTask: true)
            return
        }
        if httpResponse.expectedContentLength > Int64(maximumBytes) {
            completionHandler(.cancel)
            finish(.failure(APIError.responseTooLarge), cancelTask: true)
            return
        }
        completionHandler(.allow)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        let exceedsLimit = data.count > maximumBytes - buffer.count
        if !exceedsLimit {
            buffer.append(data)
        }
        lock.unlock()

        if exceedsLimit {
            finish(
                .failure(APIError.responseTooLarge),
                cancelTask: true
            )
        }
    }
}

extension StreamingRequest: URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let url = request.url, allowedOrigin.permits(url) else {
            completionHandler(nil)
            finish(.failure(APIError.unsafeRedirect), cancelTask: true)
            return
        }
        completionHandler(request)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: (any Error)?
    ) {
        if let urlError = error as? URLError {
            if urlError.code == .cancelled {
                finish(.failure(APIError.cancelled))
            } else if urlError.code == .timedOut {
                finish(.failure(APIError.timeout))
            } else {
                finish(.failure(APIError.transport))
            }
            return
        }
        if error != nil {
            finish(.failure(APIError.transport))
            return
        }

        lock.lock()
        let data = buffer
        lock.unlock()
        finish(.success(data))
    }
}
