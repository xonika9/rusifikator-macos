import Foundation
import OSLog

protocol NetworkClock: Sendable {
    var now: ContinuousClock.Instant { get }
    func sleep(until deadline: ContinuousClock.Instant) async throws
}

struct ContinuousNetworkClock: NetworkClock {
    var now: ContinuousClock.Instant { ContinuousClock.now }
    func sleep(until deadline: ContinuousClock.Instant) async throws {
        try await ContinuousClock().sleep(until: deadline)
    }
}

struct OpenAICompatibleClient: Sendable {
    static let maximumResponseBytes = 4 * 1_024 * 1_024
    static let processingTimeout: TimeInterval = 90
    static let connectionCheckTimeout: TimeInterval = 30
    private static let secureConnectionRetryDelay: TimeInterval = 0.5
    private static let logger = Logger(
        subsystem: "dev.gotacat.Rusifikator",
        category: "network"
    )

    private let sessionOwner: NetworkSessionOwner
    private let clock: any NetworkClock
    private let diagnosticSink: @Sendable (NetworkDiagnosticEvent) -> Void

    init(
        protocolClasses: [AnyClass]? = nil,
        sessionOwner: NetworkSessionOwner? = nil,
        clock: any NetworkClock = ContinuousNetworkClock(),
        diagnosticSink: @escaping @Sendable (NetworkDiagnosticEvent) -> Void = {
            OpenAICompatibleClient.log($0)
        }
    ) {
        self.sessionOwner = sessionOwner ?? NetworkSessionOwner(protocolClasses: protocolClasses)
        self.clock = clock
        self.diagnosticSink = diagnosticSink
    }

    func clean(
        text: String,
        baseURL: URL,
        model: String,
        apiKey: String,
        systemPrompt: String = FixedSystemPrompt.text,
        requestID: UUID = UUID(),
        partialPreviewEnabled: Bool = false,
        onPreview: @escaping @Sendable (String) -> Void = { _ in }
    ) async throws -> String {
        try await clean(
            text: text,
            baseURL: baseURL,
            model: model,
            apiKey: apiKey,
            systemPrompt: systemPrompt,
            requestID: requestID,
            timeoutInterval: Self.processingTimeout,
            partialPreviewEnabled: partialPreviewEnabled,
            onPreview: onPreview
        )
    }

    private func clean(
        text: String,
        baseURL: URL,
        model: String,
        apiKey: String,
        systemPrompt: String,
        requestID: UUID,
        timeoutInterval: TimeInterval,
        partialPreviewEnabled: Bool = false,
        onPreview: @escaping @Sendable (String) -> Void = { _ in }
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
            stream: partialPreviewEnabled
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
        let startedAt = Date()
        diagnosticSink(
            .started(
                requestCode: requestCode,
                host: endpoint.host ?? "-",
                model: model,
                timeoutSeconds: Int(timeoutInterval),
                requestBodyBytes: request.httpBody?.count ?? 0
            )
        )

        let body: ResponseBody
        do {
            body = try await load(
                request,
                allowedOrigin: allowedOrigin,
                requestCode: requestCode,
                startedAt: startedAt,
                timeoutInterval: timeoutInterval,
                partialPreviewEnabled: partialPreviewEnabled,
                onPreview: onPreview
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
                let apiError = Self.apiError(
                    for: error,
                    elapsedSeconds: Date().timeIntervalSince(startedAt),
                    timeoutSeconds: Int(timeoutInterval),
                    requestCode: requestCode
                )
                Self.logFailure(
                    apiError,
                    requestCode: requestCode,
                    startedAt: startedAt
                )
                throw apiError
            }
            let apiError: APIError = error.code == .secureConnectionFailed
                ? .secureConnectionFailed(requestCode: requestCode)
                : .transport(requestCode: requestCode)
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

        let content: String
        switch body {
        case let .streamed(text):
            content = text
        case let .json(data):
            let response: ChatCompletionResponse
            do { response = try JSONDecoder().decode(ChatCompletionResponse.self, from: data) }
            catch { throw partialPreviewEnabled ? APIError.invalidStreamingResponse : APIError.invalidResponse }
            guard let value = response.choices.first?.message.content else { throw APIError.emptyResponse }
            content = value
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

    private func load(
        _ request: URLRequest,
        allowedOrigin: ProviderOrigin,
        requestCode: String,
        startedAt: Date,
        timeoutInterval: TimeInterval,
        partialPreviewEnabled: Bool,
        onPreview: @escaping @Sendable (String) -> Void
    ) async throws -> ResponseBody {
        let clock = self.clock
        let deadline = clock.now.advanced(by: .seconds(timeoutInterval))
        return try await withThrowingTaskGroup(of: ResponseBody.self) { group in
            group.addTask {
                try await clock.sleep(until: deadline)
                throw APIError.clientTimeout(seconds: Int(timeoutInterval), requestCode: requestCode)
            }
            group.addTask {
                var canRetrySecureConnectionFailure = true
                while true {
                    try Task.checkCancellation()
                    let lease = try await sessionOwner.acquire(origin: allowedOrigin, timeout: timeoutInterval)
                    let transfer = StreamingRequest(
                        maximumBytes: Self.maximumResponseBytes,
                        allowedOrigin: allowedOrigin,
                        requestCode: requestCode,
                        timeoutSeconds: Int(timeoutInterval),
                        startedAt: startedAt,
                        diagnosticSink: diagnosticSink,
                        partialPreviewEnabled: partialPreviewEnabled,
                        onPreview: onPreview
                    )
                    do {
                        return try await transfer.load(request, lease: lease)
                    } catch let error as URLError
                        where error.code == .secureConnectionFailed && canRetrySecureConnectionFailure {
                        let remaining = clock.now.duration(to: deadline)
                        let remainingSeconds = TimeInterval(remaining.components.seconds)
                            + TimeInterval(remaining.components.attoseconds) / 1e18
                        guard Self.retryTimeout(
                            totalTimeout: remainingSeconds,
                            elapsed: 0,
                            retryDelay: Self.secureConnectionRetryDelay
                        ) != nil else {
                            throw error
                        }
                        canRetrySecureConnectionFailure = false
                        diagnosticSink(.retryingTLS(
                            requestCode: requestCode,
                            delayMilliseconds: Int(Self.secureConnectionRetryDelay * 1_000)
                        ))
                        try await clock.sleep(until: clock.now.advanced(by: .seconds(Self.secureConnectionRetryDelay)))
                    }
                }
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }

    static func retryTimeout(
        totalTimeout: TimeInterval,
        elapsed: TimeInterval,
        retryDelay: TimeInterval
    ) -> TimeInterval? {
        let remaining = totalTimeout - elapsed - retryDelay
        return remaining > 0 ? remaining : nil
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

    static func apiError(
        for urlError: URLError,
        elapsedSeconds: TimeInterval,
        timeoutSeconds: Int,
        requestCode: String
    ) -> APIError {
        guard urlError.code == .timedOut else {
            return .transport(requestCode: requestCode)
        }
        if elapsedSeconds >= max(0, TimeInterval(timeoutSeconds) - 1) {
            return .clientTimeout(
                seconds: timeoutSeconds,
                requestCode: requestCode
            )
        }
        return .networkTimeout(requestCode: requestCode)
    }

    private static func log(_ event: NetworkDiagnosticEvent) {
        switch event {
        case .completed(_, .some, _, _):
            logger.error("\(event.message, privacy: .public)")
        case .started, .response, .retryingTLS, .metrics:
            logger.info("\(event.message, privacy: .public)")
        case .completed:
            logger.debug("\(event.message, privacy: .public)")
        }
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
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
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

private enum ResponseBody: Sendable { case json(Data), streamed(String) }

private final class StreamingRequest: NSObject, @unchecked Sendable {
    private let maximumBytes: Int
    private let allowedOrigin: ProviderOrigin
    private let requestCode: String
    private let timeoutSeconds: Int
    private let startedAt: Date
    private let diagnosticSink: @Sendable (NetworkDiagnosticEvent) -> Void
    private let lock = NSLock()

    private var continuation: CheckedContinuation<ResponseBody, Error>?
    private var lease: NetworkSessionOwner.Lease?
    private var task: URLSessionDataTask?
    private var buffer = Data()
    private var receivedBytes = 0
    private var decoder: StreamingResponseDecoder?
    private let partialPreviewEnabled: Bool
    private let onPreview: @Sendable (String) -> Void
    private var isFinished = false
    private var cancellationRequested = false

    init(
        maximumBytes: Int,
        allowedOrigin: ProviderOrigin,
        requestCode: String,
        timeoutSeconds: Int,
        startedAt: Date,
        diagnosticSink: @escaping @Sendable (NetworkDiagnosticEvent) -> Void,
        partialPreviewEnabled: Bool,
        onPreview: @escaping @Sendable (String) -> Void
    ) {
        self.partialPreviewEnabled = partialPreviewEnabled
        self.onPreview = onPreview
        self.maximumBytes = maximumBytes
        self.allowedOrigin = allowedOrigin
        self.requestCode = requestCode
        self.timeoutSeconds = timeoutSeconds
        self.startedAt = startedAt
        self.diagnosticSink = diagnosticSink
    }

    func load(
        _ request: URLRequest,
        lease: NetworkSessionOwner.Lease
    ) async throws -> ResponseBody {
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                do {
                    let task = try lock.withLock { () throws -> URLSessionDataTask? in
                        guard !cancellationRequested else { return nil }
                        let task = try lease.dataTask(with: request, delegate: self)
                        self.continuation = continuation
                        self.lease = lease
                        self.task = task
                        return task
                    }
                    guard let task else {
                        continuation.resume(throwing: APIError.cancelled)
                        return
                    }
                    task.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
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
        _ result: Result<ResponseBody, Error>,
        cancelTask: Bool = false
    ) {
        let resources = lock.withLock {
            guard !isFinished else {
                return nil as (
                    CheckedContinuation<ResponseBody, Error>?,
                    URLSessionDataTask?
                )?
            }
            isFinished = true
            let resources = (continuation, task)
            continuation = nil
            task = nil
            return resources
        }
        guard let (continuation, task) = resources else {
            return
        }

        if cancelTask {
            task?.cancel()
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
        diagnosticSink(
            .response(
                requestCode: requestCode,
                statusCode: httpResponse.statusCode,
                expectedBodyBytes: httpResponse.expectedContentLength
            )
        )
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
        if partialPreviewEnabled {
            let type = httpResponse.value(forHTTPHeaderField: "Content-Type")?
                .split(separator: ";", maxSplits: 1).first?
                .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            switch type {
            case "text/event-stream":
                lock.withLock { decoder = StreamingResponseDecoder() }
            case "application/json": break
            default:
                completionHandler(.cancel)
                finish(.failure(APIError.invalidStreamingResponse), cancelTask: true)
                return
            }
        }
        completionHandler(.allow)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        do {
            let preview = try lock.withLock { () throws -> String? in
                guard !isFinished else { return nil }
                guard data.count <= maximumBytes - receivedBytes else { throw APIError.responseTooLarge }
                receivedBytes += data.count
                if decoder != nil { return try decoder!.append(data) }
                buffer.append(data)
                return nil
            }
            // User code can cancel/reenter; never invoke it under the request lock.
            if let preview { onPreview(preview) }
        } catch {
            finish(.failure(error), cancelTask: true)
        }
    }
}

extension StreamingRequest: URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didFinishCollecting metrics: URLSessionTaskMetrics
    ) {
        diagnosticSink(
            .metrics(
                requestCode: requestCode,
                summary: NetworkMetricsFormatter.summary(for: metrics)
            )
        )
    }

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
        let lease = lock.withLock { () -> NetworkSessionOwner.Lease? in
            let lease = self.lease
            self.lease = nil
            return lease
        }
        lease?.release()
        let nsError = error as NSError?
        diagnosticSink(
            .completed(
                requestCode: requestCode,
                failure: nsError.map {
                    NetworkDiagnosticFailure(
                        domain: $0.domain == NSURLErrorDomain ? NSURLErrorDomain : "Transport",
                        code: $0.code,
                        description: "Transport failure"
                    )
                },
                bytesSent: task.countOfBytesSent,
                bytesReceived: task.countOfBytesReceived
            )
        )
        if let urlError = error as? URLError {
            if urlError.code == .cancelled {
                finish(.failure(APIError.cancelled))
            } else if urlError.code == .timedOut {
                finish(
                    .failure(
                        OpenAICompatibleClient.apiError(
                            for: urlError,
                            elapsedSeconds: Date().timeIntervalSince(startedAt),
                            timeoutSeconds: timeoutSeconds,
                            requestCode: requestCode
                        )
                    )
                )
            } else if urlError.code == .secureConnectionFailed {
                let receivedData = lock.withLock { receivedBytes > 0 }
                finish(.failure(receivedData ? APIError.transport(requestCode: requestCode) : urlError))
            } else {
                finish(.failure(APIError.transport(requestCode: requestCode)))
            }
            return
        }
        if error != nil {
            finish(.failure(APIError.transport(requestCode: requestCode)))
            return
        }

        do {
            let body = try lock.withLock { () throws -> ResponseBody in
                if decoder != nil { return .streamed(try decoder!.finish()) }
                return .json(buffer)
            }
            finish(.success(body))
        } catch { finish(.failure(error)) }
    }
}
