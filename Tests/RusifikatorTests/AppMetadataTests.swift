import XCTest
@testable import Rusifikator

final class AppMetadataTests: XCTestCase {
    func testMenuHeaderContainsNameVersionAndDistinctBuild() {
        XCTAssertEqual(
            AppMetadata.menuHeader(
                info: [
                    "CFBundleShortVersionString": "1.2",
                    "CFBundleVersion": "7"
                ]
            ),
            "Русификатор 1.2 (7)"
        )
    }

    func testMenuHeaderDoesNotRepeatMatchingCalendarVersion() {
        let info: [String: Any] = [
            "CFBundleShortVersionString": "26.11.22.1",
            "CFBundleVersion": "26.11.22.1"
        ]

        XCTAssertEqual(AppMetadata.displayVersion(info: info), "26.11.22.1")
        XCTAssertEqual(AppMetadata.canonicalVersion(info: info), "26.11.22.1")
        XCTAssertEqual(AppMetadata.menuHeader(info: info), "Русификатор 26.11.22.1")
    }

    func testNonNumericBuildIsNeverHidden() {
        XCTAssertEqual(
            AppMetadata.menuHeader(
                info: [
                    "CFBundleShortVersionString": "1.0",
                    "CFBundleVersion": "1.0-beta"
                ]
            ),
            "Русификатор 1.0 (1.0-beta)"
        )
    }

    func testMissingMetadataFallsBackToAPlaceholder() {
        XCTAssertEqual(AppMetadata.displayVersion(info: [:]), "—")
        XCTAssertEqual(AppMetadata.canonicalVersion(info: [:]), "—")
        XCTAssertEqual(AppMetadata.menuHeader(info: [:]), "Русификатор —")
    }
}
