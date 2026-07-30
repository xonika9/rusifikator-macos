import Foundation
import OSLog

struct OpenAICompatibleClient: Sendable {
    static let maximumResponseBytes = 4 * 1_024 * 1_024
    static let processingTimeout: TimeInterval = 90
    static let connectionCheckTimeout: TimeInterval = 30
    private static let logger = Logger(
        subsystem: "dev.gotacat.Rusifikator",
        category: "network"
    )

    private let protocolClasses: [AnyClass]?

    init(protocolClasses: [AnyClass]? = nil) {
        self.protocolClasses = protocolClasses
    }

    func clean(
        text: String,
        baseURL: URL,
        model: String,
        apiKey: String,
        systemPrompt: String = FixedSystemPrompt.text,
        requestID: UUID = UUID()
    ) async throws -> String {
        try await clean(
            text: text,
            baseURL: baseURL,
            model: model,
            apiKey: apiKey,
            systemPrompt: systemPrompt,
            requestID: requestID,
            timeoutInterval: Self.processingTimeout
        )
    }

    private func clean(
        text: String,
        baseURL: URL,
        model: String,
        apiKey: String,
        systemPrompt: String,
        requestID: UUID,
        timeoutInterval: TimeInterval
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
        request.setValue(requestID.uuidString, forHTTPHeaderField: "X-Request-ID")
        request.httpBody = try JSONEncoder().encode(payload)
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let allowedOrigin: ProviderOrigin
        do {
            allowedOrigin = try ProviderOrigin(url: endpoint)
        } catch {
            throw APIError.invalidURL
        }
        let requestCode = Self.requestCode(for: requestID)
        let transfer = StreamingRequest(
            maximumBytes: Self.maximumResponseBytes,
            allowedOrigin: allowedOrigin,
            requestCode: requestCode,
            timeoutSeconds: Int(timeoutInterval)
        )
        let startedAt = Date()
        Self.logger.info(
            "Request \(requestCode, privacy: .public) started; host=\(endpoint.host ?? "-", privacy: .public); timeout=\(Int(timeoutInterval), privacy: .public)s"
        )

        let data: Data
        do {
            data = try await transfer.load(
                request,
                configuration: Self.makeConfiguration(
                    timeoutInterval: timeoutInterval,
                    protocolClasses: protocolClasses
                )
            )
        } catch let error as APIError {
            Self.logFailure(
                error,
                requestCode: requestCode,
                startedAt: startedAt
            )
            throw error
        } catch is CancellationError {
            Self.logFailure(
                APIError.cancelled,
                requestCode: requestCode,
                startedAt: startedAt
            )
            throw APIError.cancelled
        } catch let error as URLError {
            if error.code == .cancelled {
                Self.logFailure(
                    APIError.cancelled,
                    requestCode: requestCode,
                    startedAt: startedAt
                )
                throw APIError.cancelled
            }
            if error.code == .timedOut {
                let apiError = APIError.clientTimeout(
                    seconds: Int(timeoutInterval),
                    requestCode: requestCode
                )
                Self.logFailure(
                    apiError,
                    requestCode: requestCode,
                    startedAt: startedAt
                )
                throw apiError
            }
            let apiError = APIError.transport(requestCode: requestCode)
            Self.logFailure(
                apiError,
                requestCode: requestCode,
                startedAt: startedAt
            )
            throw apiError
        } catch {
            let apiError = APIError.transport(requestCode: requestCode)
            Self.logFailure(
                apiError,
                requestCode: requestCode,
                startedAt: startedAt
            )
            throw apiError
        }

        let response: ChatCompletionResponse
        do {
            response = try JSONDecoder().decode(
                ChatCompletionResponse.self,
                from: data
            )
        } catch {
            Self.logFailure(
                APIError.invalidResponse,
                requestCode: requestCode,
                startedAt: startedAt
            )
            throw APIError.invalidResponse
        }

        guard let content = response.choices.first?.message.content else {
            Self.logFailure(
                APIError.emptyResponse,
                requestCode: requestCode,
                startedAt: startedAt
            )
            throw APIError.emptyResponse
        }

        let normalized = Self.normalizeContent(content)
        guard !normalized.isEmpty else {
            Self.logFailure(
                APIError.emptyResponse,
                requestCode: requestCode,
                startedAt: startedAt
            )
            throw APIError.emptyResponse
        }
        let elapsedMilliseconds = Int(
            Date().timeIntervalSince(startedAt) * 1_000
        )
        Self.logger.info(
            "Request \(requestCode, privacy: .public) succeeded in \(elapsedMilliseconds, privacy: .public)ms"
        )
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
            systemPrompt: systemPrompt,
            requestID: UUID(),
            timeoutInterval: Self.connectionCheckTimeout
        )
    }

    static func requestCode(for requestID: UUID) -> String {
        String(requestID.uuidString.prefix(8))
    }

    private static func logFailure(
        _ error: APIError,
        requestCode: String,
        startedAt: Date
    ) {
        let elapsedMilliseconds = Int(
            Date().timeIntervalSince(startedAt) * 1_000
        )
        logger.error(
            "Request \(requestCode, privacy: .public) failed as \(String(describing: error), privacy: .public) after \(elapsedMilliseconds, privacy: .public)ms"
        )
    }

    static func endpoint(for baseURL: URL) throws -> URL {
        do {
            _ = try ProviderOrigin(url: baseURL)
        } catch {
            throw APIError.invalidURL
        }

        guard var components = URLComponents(
            url: baseURL,
            resolvingAgainstBaseURL: false
        ),
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
        timeoutInterval: TimeInterval = processingTimeout,
        protocolClasses: [AnyClass]? = nil
    ) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = timeoutInterval
        configuration.timeoutIntervalForResource = timeoutInterval
        configuration.waitsForConnectivity = false
        configuration.httpShouldSetCookies = false
        if let protocolClasses {
            configuration.protocolClasses = protocolClasses
        }
        return configuration
    }

    private static func normalizeContent(_ content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let firstIndex = trimmed.indices.first,
              trimmed.index(after: firstIndex) < trimmed.endIndex
        else {
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

private final class StreamingRequest: NSObject, @unchecked Sendable {
    private let maximumBytes: Int
    private let allowedOrigin: ProviderOrigin
    private let requestCode: String
    private let timeoutSeconds: Int
    private let lock = NSLock()

    private var continuation: CheckedContinuation<Data, Error>?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var buffer = Data()
    private var isFinished = false
    private var cancellationRequested = false

    init(
        maximumBytes: Int,
        allowedOrigin: ProviderOrigin,
        requestCode: String,
        timeoutSeconds: Int
    ) {
        self.maximumBytes = maximumBytes
        self.allowedOrigin = allowedOrigin
        self.requestCode = requestCode
        self.timeoutSeconds = timeoutSeconds
    }

    func load(
        _ request: URLRequest,
        configuration: URLSessionConfiguration
    ) async throws -> Data {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = lock.withLock { () -> URLSessionDataTask? in
                    guard !cancellationRequested else {
                        return nil
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
                    return task
                }
                guard let task else {
                    continuation.resume(throwing: APIError.cancelled)
                    return
                }
                task.resume()
            }
        } onCancel: {
            self.cancel()
        }
    }

    private func cancel() {
        lock.withLock {
            cancellationRequested = true
        }
        finish(.failure(APIError.cancelled), cancelTask: true)
    }

    private func finish(
        _ result: Result<Data, Error>,
        cancelTask: Bool = false
    ) {
        let resources = lock.withLock {
            guard !isFinished else {
                return nil as (
                    CheckedContinuation<Data, Error>?,
                    URLSessionDataTask?,
                    URLSession?
                )?
            }
            isFinished = true
            let resources = (continuation, task, session)
            continuation = nil
            task = nil
            session = nil
            return resources
        }
        guard let (continuation, task, session) = resources else {
            return
        }

        if cancelTask {
            task?.cancel()
            session?.invalidateAndCancel()
        } else {
            session?.finishTasksAndInvalidate()
        }
        continuation?.resume(with: result)
    }

    private func error(for statusCode: Int) -> APIError? {
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
            .httpTimeout(requestCode: requestCode)
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
        if let error = error(for: httpResponse.statusCode) {
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
        let exceedsLimit = lock.withLock {
            guard !isFinished else {
                return false
            }
            let exceedsLimit = data.count > maximumBytes - buffer.count
            if !exceedsLimit {
                buffer.append(data)
            }
            return exceedsLimit
        }

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
                finish(
                    .failure(
                        APIError.clientTimeout(
                            seconds: timeoutSeconds,
                            requestCode: requestCode
                        )
                    )
                )
            } else {
                finish(.failure(APIError.transport(requestCode: requestCode)))
            }
            return
        }
        if error != nil {
            finish(.failure(APIError.transport(requestCode: requestCode)))
            return
        }

        let data = lock.withLock { buffer }
        finish(.success(data))
    }
}
