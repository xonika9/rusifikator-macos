import Foundation

enum APIError: Error, Equatable, Sendable {
    case missingAPIKey
    case invalidURL
    case unauthorized
    case forbidden
    case notFound
    case timeout
    case rateLimited
    case serverError
    case httpError(Int)
    case transport
    case invalidResponse
    case emptyResponse
    case responseTooLarge
    case unsafeRedirect
    case cancelled
}

extension APIError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "Добавь API-ключ в настройках."
        case .invalidURL:
            "Проверь адрес API. Нужен корректный HTTPS-адрес."
        case .unauthorized:
            "API-ключ не принят. Проверь ключ в настройках."
        case .forbidden:
            "У ключа нет доступа к выбранной модели."
        case .notFound:
            "Маршрут API не найден. Проверь адрес сервера."
        case .timeout:
            "Сервер не ответил вовремя. Попробуй ещё раз."
        case .rateLimited:
            "Слишком много запросов. Подожди и попробуй снова."
        case .serverError:
            "Сервис временно недоступен. Попробуй позже."
        case let .httpError(statusCode):
            "Сервис вернул ошибку HTTP \(statusCode)."
        case .transport:
            "Не удалось связаться с сервисом. Проверь сеть и адрес API."
        case .invalidResponse:
            "Сервис вернул ответ в несовместимом формате."
        case .emptyResponse:
            "Сервис вернул пустой результат."
        case .responseTooLarge:
            "Ответ сервиса слишком большой."
        case .unsafeRedirect:
            "Сервис попытался перенаправить запрос на небезопасный адрес."
        case .cancelled:
            "Запрос отменён."
        }
    }
}
