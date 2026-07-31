import Foundation

/// Turns an update-mechanism error code into a report the settings screen can
/// show. Messages are fixed strings: nothing from the editor, the history or
/// the provider ever reaches this path.
enum UpdateErrorMapping {
    // Codes come from Sparkle's `SUError` enumeration. They are spelled out
    // here so the mapping can be tested on its own.
    static let noUpdateCode = 1001
    static let installationCanceledCode = 4007
    static let installationAuthorizeLaterCode = 4008
    static let runningFromDiskImageCode = 1003
    static let runningTranslocatedCode = 1005
    static let insecureFeedURLCode = 3

    static func report(forErrorCode code: Int) -> UpdateReport {
        switch code {
        case noUpdateCode:
            return .noUpdateFound

        case installationCanceledCode, installationAuthorizeLaterCode:
            return .cancelledByUser

        case runningFromDiskImageCode:
            return .failed(
                message: "Скопируй приложение в «Программы» — из образа диска обновление не ставится."
            )

        case runningTranslocatedCode:
            return .failed(
                message: "Скопируй приложение в «Программы» и запусти оттуда, иначе обновление не ставится."
            )

        case insecureFeedURLCode:
            return .failed(message: "Адрес обновлений должен быть HTTPS.")

        case 1000, 1002, 1004:
            return .failed(message: "Не удалось прочитать данные об обновлениях.")

        case 2000, 2001:
            return .failed(message: "Не удалось загрузить обновление. Проверь соединение.")

        case 3000...3999:
            return .failed(message: "Не удалось проверить подлинность обновления.")

        case 4000...4999:
            return .failed(message: "Не удалось установить обновление.")

        default:
            return .failed(message: "Не удалось проверить обновления. Попробуй позже.")
        }
    }
}
