import Foundation
import XCTest
@testable import Rusifikator

final class UpdateErrorMappingTests: XCTestCase {
    func testAbsenceOfAnUpdateIsNotAFailure() {
        XCTAssertEqual(
            UpdateErrorMapping.report(forErrorCode: UpdateErrorMapping.noUpdateCode),
            .noUpdateFound
        )
    }

    func testUserDismissalReturnsToTheNeutralState() {
        XCTAssertEqual(
            UpdateErrorMapping.report(
                forErrorCode: UpdateErrorMapping.installationCanceledCode
            ),
            .cancelledByUser
        )
        XCTAssertEqual(
            UpdateErrorMapping.report(
                forErrorCode: UpdateErrorMapping.installationAuthorizeLaterCode
            ),
            .cancelledByUser
        )
    }

    func testRunningFromAMountedImageIsExplainedToTheOwner() {
        guard case let .failed(message) = UpdateErrorMapping.report(
            forErrorCode: UpdateErrorMapping.runningFromDiskImageCode
        ) else {
            return XCTFail("Expected a failure report")
        }
        XCTAssertTrue(message.contains("Программы"))
    }

    func testAuthenticityAndDownloadProblemsAreDistinguished() {
        XCTAssertEqual(
            UpdateErrorMapping.report(forErrorCode: 3001),
            .failed(message: "Не удалось проверить подлинность обновления.")
        )
        XCTAssertEqual(
            UpdateErrorMapping.report(forErrorCode: 2001),
            .failed(message: "Не удалось загрузить обновление. Проверь соединение.")
        )
    }

    func testInsecureFeedIsReportedSeparatelyFromSignatureProblems() {
        XCTAssertEqual(
            UpdateErrorMapping.report(
                forErrorCode: UpdateErrorMapping.insecureFeedURLCode
            ),
            .failed(message: "Адрес обновлений должен быть HTTPS.")
        )
    }

    func testUnknownCodesFallBackToAGenericMessage() {
        XCTAssertEqual(
            UpdateErrorMapping.report(forErrorCode: 99_999),
            .failed(message: "Не удалось проверить обновления. Попробуй позже.")
        )
    }

    func testNoMessageLeaksTechnicalDetail() {
        for code in [0, 1, 3, 1000, 1003, 1005, 2000, 3002, 4005, 5000, 12_345] {
            guard case let .failed(message) = UpdateErrorMapping.report(
                forErrorCode: code
            ) else {
                continue
            }
            XCTAssertFalse(message.contains("\(code)"))
            XCTAssertFalse(message.lowercased().contains("error"))
        }
    }
}

@MainActor
final class UpdateViewModelTests: XCTestCase {
    func testCheckMovesToCheckingAndAsksTheMechanismExactlyOnce() {
        let checker = UpdateCheckerSpy()
        let model = makeModel(checker: checker)

        model.checkForUpdates()

        XCTAssertEqual(model.state, .checking)
        XCTAssertEqual(checker.checkCount, 1)
        XCTAssertFalse(model.canCheck)

        model.checkForUpdates()
        XCTAssertEqual(checker.checkCount, 1)
    }

    func testFoundVersionIsShownAndAnotherCheckBecomesPossible() {
        let checker = UpdateCheckerSpy()
        let model = makeModel(checker: checker)

        model.checkForUpdates()
        model.handle(.foundUpdate(version: "1.1"))

        XCTAssertEqual(model.state, .available(version: "1.1"))
        XCTAssertTrue(model.canCheck)
    }

    func testAbsenceOfAnUpdateIsShownAsUpToDate() {
        let checker = UpdateCheckerSpy()
        let model = makeModel(checker: checker)

        model.checkForUpdates()
        model.handle(.noUpdateFound)

        XCTAssertEqual(model.state, .upToDate)
    }

    func testDismissalReturnsToTheNeutralState() {
        let checker = UpdateCheckerSpy()
        let model = makeModel(checker: checker)

        model.checkForUpdates()
        model.handle(.cancelledByUser)

        XCTAssertEqual(model.state, .idle)
    }

    func testFailureIsShownAndDoesNotBlockTheNextCheck() {
        let checker = UpdateCheckerSpy()
        let model = makeModel(checker: checker)

        model.checkForUpdates()
        model.handle(.failed(message: "Не удалось проверить обновления. Попробуй позже."))

        XCTAssertEqual(
            model.state,
            .failed("Не удалось проверить обновления. Попробуй позже.")
        )
        XCTAssertTrue(model.canCheck)

        model.checkForUpdates()
        XCTAssertEqual(checker.checkCount, 2)
    }

    func testCheckIsRefusedWhileTheMechanismIsBusy() {
        let checker = UpdateCheckerSpy()
        checker.canCheckForUpdates = false
        let model = makeModel(checker: checker)

        model.checkForUpdates()

        XCTAssertEqual(checker.checkCount, 0)
        XCTAssertEqual(model.state, .idle)
    }

    func testBuildWithoutAnUpdateMechanismSaysSoInsteadOfPretending() {
        let model = UpdateViewModel(
            installedVersion: "1.0",
            canonicalVersion: "1.0.0"
        )

        XCTAssertFalse(model.isAvailable)
        XCTAssertFalse(model.canCheck)

        model.checkForUpdates()
        XCTAssertEqual(model.state, .failed("Обновления недоступны в этой сборке."))
    }

    func testInstalledVersionMentionsTheCanonicalFormOnlyWhenItDiffers() {
        let checker = UpdateCheckerSpy()
        XCTAssertEqual(
            makeModel(checker: checker).installedVersionDescription,
            "Установлена версия 1.0 (1.0.0)"
        )

        let same = UpdateViewModel(installedVersion: "1.1.0", canonicalVersion: "1.1.0")
        XCTAssertEqual(same.installedVersionDescription, "Установлена версия 1.1.0")
    }

    private func makeModel(checker: UpdateCheckerSpy) -> UpdateViewModel {
        let model = UpdateViewModel(
            installedVersion: "1.0",
            canonicalVersion: "1.0.0"
        )
        model.attach(checker)
        return model
    }
}

@MainActor
private final class UpdateCheckerSpy: UpdateChecking {
    var canCheckForUpdates = true
    private(set) var checkCount = 0

    func checkForUpdates() {
        checkCount += 1
    }
}
