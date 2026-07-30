import Foundation

enum NetworkDiagnosticEvent: Equatable, Sendable {
    case started(
        requestCode: String,
        host: String,
        model: String,
        timeoutSeconds: Int,
        requestBodyBytes: Int
    )
    case response(
        requestCode: String,
        statusCode: Int,
        expectedBodyBytes: Int64
    )
    case metrics(requestCode: String, summary: String)
    case completed(
        requestCode: String,
        failure: NetworkDiagnosticFailure?,
        bytesSent: Int64,
        bytesReceived: Int64
    )

    var message: String {
        switch self {
        case let .started(
            requestCode,
            host,
            model,
            timeoutSeconds,
            requestBodyBytes
        ):
            "Request \(requestCode) started; host=\(Self.singleLine(host)); "
                + "model=\(Self.singleLine(model)); timeout=\(timeoutSeconds)s; "
                + "requestBody=\(requestBodyBytes)B"
        case let .response(requestCode, statusCode, expectedBodyBytes):
            "Request \(requestCode) received HTTP \(statusCode); "
                + "expectedBody=\(expectedBodyBytes)B"
        case let .metrics(requestCode, summary):
            "Request \(requestCode) metrics; \(Self.singleLine(summary))"
        case let .completed(requestCode, failure, bytesSent, bytesReceived):
            if let failure {
                "Request \(requestCode) transport failed; "
                    + "errorDomain=\(Self.singleLine(failure.domain)); "
                    + "errorCode=\(failure.code); "
                    + "error=\(Self.singleLine(failure.description)); "
                    + "sent=\(bytesSent)B; received=\(bytesReceived)B"
            } else {
                "Request \(requestCode) transport completed; "
                    + "sent=\(bytesSent)B; received=\(bytesReceived)B"
            }
        }
    }

    private static func singleLine(_ value: String) -> String {
        var sanitized = ""
        sanitized.reserveCapacity(min(value.utf8.count, 240))
        for scalar in value.unicodeScalars.prefix(240) {
            sanitized.unicodeScalars.append(
                CharacterSet.controlCharacters.contains(scalar) ? " " : scalar
            )
        }
        return sanitized.trimmingCharacters(in: .whitespaces)
    }
}

struct NetworkDiagnosticFailure: Equatable, Sendable {
    let domain: String
    let code: Int
    let description: String
}

enum NetworkMetricsFormatter {
    static func summary(for metrics: URLSessionTaskMetrics) -> String {
        let transaction = metrics.transactionMetrics.last
        let total = milliseconds(
            from: metrics.taskInterval.start,
            to: metrics.taskInterval.end
        )
        let dns = milliseconds(
            from: transaction?.domainLookupStartDate,
            to: transaction?.domainLookupEndDate
        )
        let connect = milliseconds(
            from: transaction?.connectStartDate,
            to: transaction?.connectEndDate
        )
        let tls = milliseconds(
            from: transaction?.secureConnectionStartDate,
            to: transaction?.secureConnectionEndDate
        )
        let request = milliseconds(
            from: transaction?.requestStartDate,
            to: transaction?.requestEndDate
        )
        let serverWait = milliseconds(
            from: transaction?.requestEndDate,
            to: transaction?.responseStartDate
        )
        let response = milliseconds(
            from: transaction?.responseStartDate,
            to: transaction?.responseEndDate
        )

        return [
            "total=\(total)",
            "dns=\(dns)",
            "connect=\(connect)",
            "tls=\(tls)",
            "request=\(request)",
            "serverWait=\(serverWait)",
            "response=\(response)",
            "protocol=\(transaction?.networkProtocolName ?? "-")",
            "proxy=\(transaction?.isProxyConnection ?? false)",
            "reused=\(transaction?.isReusedConnection ?? false)",
            "redirects=\(metrics.redirectCount)",
            "transactions=\(metrics.transactionMetrics.count)"
        ].joined(separator: "; ")
    }

    private static func milliseconds(from start: Date?, to end: Date?) -> String {
        guard let start, let end else {
            return "-"
        }
        return "\(max(0, Int(end.timeIntervalSince(start) * 1_000)))ms"
    }
}
