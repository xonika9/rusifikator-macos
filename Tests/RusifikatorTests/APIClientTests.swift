import Foundation
import XCTest
@testable import Rusifikator

final class APIClientTests: XCTestCase {
    override func setUp() {
        super.setUp()
        URLProtocolStub.reset()
    }

    override func tearDown() {
        URLProtocolStub.reset()
        super.tearDown()
    }

    func testEndpointNormalization() throws {
        let cases = [
            "https://example.com": "https://example.com/v1/chat/completions",
            "https://example.com/": "https://example.com/v1/chat/completions",
            "https://example.com/v1": "https://example.com/v1/chat/completions",
            "https://example.com/v1/": "https://example.com/v1/chat/completions",
            "https://example.com/chat/completions": "https://example.com/v1/chat/completions",
            "https://example.com/v1/chat/completions": "https://example.com/v1/chat/completions",
            "https://example.com/v1/chat/completions/": "https://example.com/v1/chat/completions"
        ]

        for (base, expected) in cases {
            XCTAssertEqual(
                try OpenAICompatibleClient.endpoint(for: XCTUnwrap(URL(string: base))).absoluteString,
                expected,
                "Unexpected endpoint for \(base)"
            )
        }
    }

    func testEndpointRejectsNonHTTPSAndMalformedBaseURLs() throws {
        let invalidURLs = [
            "http://example.com",
            "https://user:password@example.com",
            "https://example.com/v2",
            "https://example.com/v1?debug=true"
        ]

        for value in invalidURLs {
            XCTAssertThrowsError(
                try OpenAICompatibleClient.endpoint(for: XCTUnwrap(URL(string: value)))
            ) { error in
                XCTAssertEqual(error as? APIError, .invalidURL)
            }
        }
    }

    func testRequestHasOnlyRequiredFieldsAndExactlyTwoMessages() async throws {
        let requestID = UUID(uuidString: "A1B2C3D4-1111-2222-3333-444455556666")!
        URLProtocolStub.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "X-Request-ID"),
                requestID.uuidString
            )

            let body = try requestBody(request)
            let json = try XCTUnwrap(
                JSONSerialization.jsonObject(with: body) as? [String: Any]
            )
            XCTAssertEqual(Set(json.keys), ["model", "messages", "stream"])
            XCTAssertEqual(json["model"] as? String, "proxy/gpt-5.6-terra")
            XCTAssertEqual(json["stream"] as? Bool, false)

            let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
            XCTAssertEqual(messages.count, 2)
            XCTAssertEqual(Set(messages[0].keys), ["role", "content"])
            XCTAssertEqual(messages[0]["role"] as? String, "system")
            XCTAssertEqual(messages[0]["content"] as? String, "SYSTEM")
            XCTAssertEqual(Set(messages[1].keys), ["role", "content"])
            XCTAssertEqual(messages[1]["role"] as? String, "user")
            XCTAssertEqual(messages[1]["content"] as? String, "CURRENT")

            return .json(#"{"choices":[{"message":{"content":"Готово"}}]}"#)
        }

        let result = try await makeClient().clean(
            text: "CURRENT",
            baseURL: XCTUnwrap(URL(string: "https://example.com/v1")),
            model: "proxy/gpt-5.6-terra",
            apiKey: "test-key",
            systemPrompt: "SYSTEM",
            requestID: requestID
        )

        XCTAssertEqual(result, "Готово")
    }

    func testConsecutiveRequestsDoNotCarryHistory() async throws {
        let lock = NSLock()
        var bodies: [[String: Any]] = []
        URLProtocolStub.handler = { request in
            let body = try requestBody(request)
            let json = try XCTUnwrap(
                JSONSerialization.jsonObject(with: body) as? [String: Any]
            )
            lock.withLock {
                bodies.append(json)
            }

            let index = lock.withLock { bodies.count }
            return .json(
                index == 1
                    ? #"{"choices":[{"message":{"content":"FIRST RESULT"}}]}"#
                    : #"{"choices":[{"message":{"content":"SECOND RESULT"}}]}"#
            )
        }

        let client = makeClient()
        let baseURL = try XCTUnwrap(URL(string: "https://example.com"))
        _ = try await client.clean(
            text: "FIRST INPUT",
            baseURL: baseURL,
            model: "model",
            apiKey: "key",
            systemPrompt: "SYSTEM"
        )
        _ = try await client.clean(
            text: "SECOND INPUT",
            baseURL: baseURL,
            model: "model",
            apiKey: "key",
            systemPrompt: "SYSTEM"
        )

        let captured = lock.withLock { bodies }
        XCTAssertEqual(captured.count, 2)
        let secondData = try JSONSerialization.data(withJSONObject: captured[1])
        let secondBody = try XCTUnwrap(String(data: secondData, encoding: .utf8))
        XCTAssertFalse(secondBody.contains("FIRST INPUT"))
        XCTAssertFalse(secondBody.contains("FIRST RESULT"))

        let secondMessages = try XCTUnwrap(
            captured[1]["messages"] as? [[String: Any]]
        )
        XCTAssertEqual(secondMessages.count, 2)
        XCTAssertEqual(secondMessages.map { $0["role"] as? String }, ["system", "user"])
        XCTAssertEqual(secondMessages[1]["content"] as? String, "SECOND INPUT")
    }

    func testSuccessTrimsEdgesAndPreservesInternalLineBreaks() async throws {
        URLProtocolStub.handler = { _ in
            .json(#"{"choices":[{"message":{"content":" \nПервая строка\n\nВторая строка\t "}}]}"#)
        }

        let result = try await performRequest()

        XCTAssertEqual(result, "Первая строка\n\nВторая строка")
    }

    func testRemovesExactlyOneMatchingOuterQuotePair() async throws {
        let cases = [
            (#""Текст с "внутренними" кавычками""#, #"Текст с "внутренними" кавычками"#),
            ("“Текст с «внутренними» кавычками”", "Текст с «внутренними» кавычками"),
            (#"""Текст"""#, #""Текст""#),
            (#""Несовпадающие”"#, #""Несовпадающие”"#)
        ]

        for (responseContent, expected) in cases {
            URLProtocolStub.handler = { _ in
                let data = try JSONSerialization.data(
                    withJSONObject: [
                        "choices": [
                            ["message": ["content": responseContent]]
                        ]
                    ]
                )
                return .init(body: data)
            }

            let result = try await performRequest()
            XCTAssertEqual(result, expected)
        }
    }

    func testConnectionCheckUsesSameSettingsAndMinimalIndependentText() async throws {
        URLProtocolStub.handler = { request in
            let body = try requestBody(request)
            let json = try XCTUnwrap(
                JSONSerialization.jsonObject(with: body) as? [String: Any]
            )
            XCTAssertEqual(json["model"] as? String, "draft-model")
            let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
            XCTAssertEqual(messages.count, 2)
            XCTAssertEqual(messages[0]["content"] as? String, "SYSTEM")
            XCTAssertEqual(messages[1]["content"] as? String, "Проверка.")
            return .json(#"{"choices":[{"message":{"content":"ОК"}}]}"#)
        }

        try await makeClient().checkConnection(
            baseURL: XCTUnwrap(URL(string: "https://draft.example/v1")),
            model: "draft-model",
            apiKey: "draft-key",
            systemPrompt: "SYSTEM"
        )
    }

    func testHTTPStatusesMapToUserSafeErrors() async throws {
        let requestID = UUID(uuidString: "A1B2C3D4-1111-2222-3333-444455556666")!
        let cases: [(Int, APIError)] = [
            (401, .unauthorized),
            (403, .forbidden),
            (404, .notFound),
            (408, .httpTimeout(requestCode: "A1B2C3D4")),
            (429, .rateLimited),
            (500, .serverError),
            (503, .serverError)
        ]

        for (statusCode, expected) in cases {
            URLProtocolStub.handler = { _ in
                .init(statusCode: statusCode, body: Data())
            }

            await assertRequestThrows(expected, requestID: requestID)
        }
    }

    func testDecodeEmptyAndMissingKeyErrorsAreCategorized() async throws {
        URLProtocolStub.handler = { _ in
            .init(body: Data("not-json".utf8))
        }
        await assertRequestThrows(.invalidResponse)

        URLProtocolStub.handler = { _ in
            .json(#"{"choices":[]}"#)
        }
        await assertRequestThrows(.emptyResponse)

        URLProtocolStub.handler = { _ in
            .json(#"{"choices":[{"message":{"content":"  "}}]}"#)
        }
        await assertRequestThrows(.emptyResponse)

        do {
            _ = try await makeClient().clean(
                text: "text",
                baseURL: XCTUnwrap(URL(string: "https://example.com")),
                model: "model",
                apiKey: "  ",
                systemPrompt: "system"
            )
            XCTFail("Expected missing API key")
        } catch {
            XCTAssertEqual(error as? APIError, .missingAPIKey)
        }
    }

    func testTransportFailuresAreCategorized() async {
        for code in [URLError.cannotFindHost, .secureConnectionFailed, .networkConnectionLost] {
            URLProtocolStub.handler = { _ in
                throw URLError(code)
            }
            await assertRequestThrows(.transport(requestCode: "A1B2C3D4"), requestID: fixedRequestID)
        }
    }

    func testClientTimeoutIsDistinctAndIncludesSafeRequestCode() async {
        URLProtocolStub.handler = { _ in
            throw URLError(.timedOut)
        }

        await assertRequestThrows(
            .clientTimeout(seconds: 90, requestCode: "A1B2C3D4"),
            requestID: fixedRequestID
        )
    }

    func testCancellationIsCategorizedWithoutRetry() async throws {
        let lock = NSLock()
        var requestCount = 0
        URLProtocolStub.handler = { _ in
            lock.withLock {
                requestCount += 1
            }
            Thread.sleep(forTimeInterval: 1)
            return .json(#"{"choices":[{"message":{"content":"Поздно"}}]}"#)
        }

        let client = makeClient()
        let baseURL = try XCTUnwrap(URL(string: "https://example.com"))
        let task = Task {
            try await client.clean(
                text: "TEXT",
                baseURL: baseURL,
                model: "model",
                apiKey: "key",
                systemPrompt: "SYSTEM"
            )
        }
        while lock.withLock({ requestCount }) == 0 {
            await Task.yield()
        }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertEqual(error as? APIError, .cancelled)
        }
        XCTAssertEqual(lock.withLock { requestCount }, 1)
    }

    func testRejectsOversizedBodiesWithCorrectMissingAndFalseContentLength() async {
        let oversized = Data(repeating: 0x61, count: OpenAICompatibleClient.maximumResponseBytes + 1)
        let headers: [[String: String]] = [
            ["Content-Length": "\(oversized.count)"],
            [:],
            ["Content-Length": "1"]
        ]

        for responseHeaders in headers {
            URLProtocolStub.handler = { _ in
                .init(headers: responseHeaders, body: oversized, chunkSize: 16_384)
            }
            await assertRequestThrows(.responseTooLarge)
        }
    }

    func testRejectsCrossHostAndHTTPSDowngradeRedirectsWithoutSecondRequest() async {
        let lock = NSLock()
        var requestedURLs: [URL] = []
        let redirectTargets = [
            "https://attacker.example/v1/chat/completions",
            "http://example.com/v1/chat/completions"
        ]

        for target in redirectTargets {
            lock.withLock {
                requestedURLs = []
            }
            URLProtocolStub.handler = { request in
                lock.withLock {
                    requestedURLs.append(request.url!)
                }
                return .init(
                    statusCode: 307,
                    headers: ["Location": target],
                    body: Data()
                )
            }

            await assertRequestThrows(.unsafeRedirect)
            XCTAssertEqual(lock.withLock { requestedURLs.count }, 1)
        }
    }

    func testSessionConfigurationIsEphemeralAndDoesNotWaitOrCache() {
        let configuration = OpenAICompatibleClient.makeConfiguration(
            protocolClasses: [URLProtocolStub.self]
        )

        XCTAssertNil(configuration.urlCache)
        XCTAssertEqual(configuration.requestCachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(configuration.timeoutIntervalForRequest, 90)
        XCTAssertEqual(configuration.timeoutIntervalForResource, 90)
        XCTAssertFalse(configuration.waitsForConnectivity)
        XCTAssertTrue(configuration.protocolClasses?.first === URLProtocolStub.self)
    }

    func testConnectionCheckUsesThirtySecondTimeout() {
        let configuration = OpenAICompatibleClient.makeConfiguration(
            timeoutInterval: 30,
            protocolClasses: [URLProtocolStub.self]
        )

        XCTAssertEqual(configuration.timeoutIntervalForRequest, 30)
        XCTAssertEqual(configuration.timeoutIntervalForResource, 30)
    }

    func testConnectionCheckReportsItsThirtySecondClientTimeout() async {
        URLProtocolStub.handler = { _ in
            throw URLError(.timedOut)
        }

        do {
            try await makeClient().checkConnection(
                baseURL: XCTUnwrap(URL(string: "https://example.com")),
                model: "model",
                apiKey: "key",
                systemPrompt: "SYSTEM"
            )
            XCTFail("Expected timeout")
        } catch let APIError.clientTimeout(seconds, requestCode) {
            XCTAssertEqual(seconds, 30)
            XCTAssertEqual(requestCode.count, 8)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeClient() -> OpenAICompatibleClient {
        OpenAICompatibleClient(protocolClasses: [URLProtocolStub.self])
    }

    private func performRequest() async throws -> String {
        try await makeClient().clean(
            text: "TEXT",
            baseURL: XCTUnwrap(URL(string: "https://example.com")),
            model: "model",
            apiKey: "key",
            systemPrompt: "SYSTEM",
            requestID: fixedRequestID
        )
    }

    private func assertRequestThrows(
        _ expected: APIError,
        requestID: UUID? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await makeClient().clean(
                text: "TEXT",
                baseURL: XCTUnwrap(URL(string: "https://example.com")),
                model: "model",
                apiKey: "key",
                systemPrompt: "SYSTEM",
                requestID: requestID ?? fixedRequestID
            )
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? APIError, expected, file: file, line: line)
        }
    }

    private var fixedRequestID: UUID {
        UUID(uuidString: "A1B2C3D4-1111-2222-3333-444455556666")!
    }
}

private final class URLProtocolStub: URLProtocol, @unchecked Sendable {
    struct Stub {
        let statusCode: Int
        let headers: [String: String]
        let body: Data
        let chunkSize: Int?

        init(
            statusCode: Int = 200,
            headers: [String: String] = ["Content-Type": "application/json"],
            body: Data,
            chunkSize: Int? = nil
        ) {
            self.statusCode = statusCode
            self.headers = headers
            self.body = body
            self.chunkSize = chunkSize
        }

        static func json(_ value: String) -> Stub {
            Stub(body: Data(value.utf8))
        }
    }

    typealias Handler = (URLRequest) throws -> Stub

    private static let lock = NSLock()
    nonisolated(unsafe) private static var storedHandler: Handler?

    static var handler: Handler? {
        get { lock.withLock { storedHandler } }
        set { lock.withLock { storedHandler = newValue } }
    }

    static func reset() {
        handler = nil
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(
                self,
                didFailWithError: URLError(.resourceUnavailable)
            )
            return
        }

        do {
            let stub = try handler(request)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: stub.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: stub.headers
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)

            if let chunkSize = stub.chunkSize {
                var offset = 0
                while offset < stub.body.count {
                    let end = min(offset + chunkSize, stub.body.count)
                    client?.urlProtocol(self, didLoad: stub.body[offset..<end])
                    offset = end
                }
            } else if !stub.body.isEmpty {
                client?.urlProtocol(self, didLoad: stub.body)
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func requestBody(_ request: URLRequest) throws -> Data {
    if let body = request.httpBody {
        return body
    }
    let stream = try XCTUnwrap(request.httpBodyStream)
    stream.open()
    defer { stream.close() }

    var body = Data()
    var bytes = [UInt8](repeating: 0, count: 4_096)
    while stream.hasBytesAvailable {
        let count = stream.read(&bytes, maxLength: bytes.count)
        if count < 0 {
            throw stream.streamError ?? URLError(.cannotDecodeContentData)
        }
        if count == 0 {
            break
        }
        body.append(bytes, count: count)
    }
    return body
}
