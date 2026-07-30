import Foundation

enum APIError: Error, Equatable, Sendable {
    case missingAPIKey
    case invalidURL
    case unauthorized
    case forbidden
    case notFound
    case httpTimeout(requestCode: String)
    case clientTimeout(seconds: Int, requestCode: String)
    case networkTimeout(requestCode: String)
    case rateLimited
    case serverError
    case httpError(Int)
    case transport(requestCode: String)
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
        case let .httpTimeout(requestCode):
            "Сервер остановил запрос по тайм-ауту. Код запроса: \(requestCode)."
        case let .clientTimeout(seconds, requestCode):
            "Сервис не ответил за \(seconds) секунд. Код запроса: \(requestCode)."
        case let .networkTimeout(requestCode):
            "Сетевой запрос прервался по тайм-ауту. Проверь соединение и повтори запрос. Код запроса: \(requestCode)."
        case .rateLimited:
            "Слишком много запросов. Подожди и попробуй снова."
        case .serverError:
            "Сервис временно недоступен. Попробуй позже."
        case let .httpError(statusCode):
            "Сервис вернул ошибку HTTP \(statusCode)."
        case let .transport(requestCode):
            "Не удалось связаться с сервисом. Проверь сеть и адрес API. Код запроса: \(requestCode)."
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
